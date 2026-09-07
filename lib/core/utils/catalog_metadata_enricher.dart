import 'dart:convert';

import 'package:dio/dio.dart';

import '../account/animewitcher_account_config.dart';
import '../account/firestore_rest_client.dart';
import '../domain/entity/multimedia_item.dart';
import 'catalog_rating.dart';

/// Fills the lightweight card metadata that some AnimeWitcher list sources do
/// not persist or return (release year and catalog rating).
///
/// Metadata is read with Firestore `batchGet` and a field mask, so a grid is
/// enriched in a few small requests instead of issuing one details request for
/// every poster.
class CatalogMetadataEnricher {
  const CatalogMetadataEnricher._();

  static const int _batchSize = 30;

  static Future<List<MultimediaItem>> enrich(
    Dio dio,
    List<MultimediaItem> items,
  ) async {
    if (items.isEmpty) return items;

    final pendingById = <String, List<int>>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item.year != null && preferredCatalogRating(item) != null) continue;
      final animeId = _animeId(item);
      if (animeId.isEmpty) continue;
      pendingById.putIfAbsent(animeId, () => <int>[]).add(index);
    }
    if (pendingById.isEmpty) return items;

    final result = List<MultimediaItem>.from(items);
    final ids = pendingById.keys.toList(growable: false);
    for (var start = 0; start < ids.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, ids.length).toInt();
      final batch = ids.sublist(start, end);
      final metadata = await _fetchBatch(dio, batch);
      for (final entry in metadata.entries) {
        for (final index in pendingById[entry.key] ?? const <int>[]) {
          result[index] = merge(result[index], entry.value);
        }
      }
    }
    return result;
  }

  /// Keeps the card/list-specific fields from [item] and overlays only catalog
  /// metadata from [metadata].
  static MultimediaItem merge(
    MultimediaItem item,
    MultimediaItem metadata,
  ) {
    final syncData = <String, String>{
      ...?metadata.syncData,
      ...?item.syncData,
    };
    return item.copyWith(
      year: item.year ?? metadata.year,
      score: item.score ?? metadata.score,
      syncData: syncData.isEmpty ? null : syncData,
    );
  }

  static Future<Map<String, MultimediaItem>> _fetchBatch(
    Dio dio,
    List<String> animeIds,
  ) async {
    if (animeIds.isEmpty) return const <String, MultimediaItem>{};
    final projectId = AnimeWitcherAccountConfig.projectId.trim();
    if (projectId.isEmpty) return const <String, MultimediaItem>{};
    final endpoint =
        'https://firestore.googleapis.com/v1/projects/'
        '${Uri.encodeComponent(projectId)}'
        '/databases/(default)/documents:batchGet';

    try {
      final response = await dio.post<dynamic>(
        endpoint,
        data: <String, dynamic>{
          'documents': <String>[
            for (final id in animeIds)
              'projects/$projectId/databases/(default)/documents/anime_list/$id',
          ],
          'mask': const <String, dynamic>{
            'fieldPaths': <String>[
              'details',
              'rating',
              'year',
              'imdb_rate',
              'imdbRate',
              'imdb_score',
              'imdbScore',
            ],
          },
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final output = <String, MultimediaItem>{};
      for (final row in _list(response.data)) {
        if (row is! Map) continue;
        final foundRaw = row['found'];
        if (foundRaw is! Map) continue;
        final found = Map<String, dynamic>.from(foundRaw);
        final name = (found['name'] ?? '').toString();
        final id = name.split('/').last.trim();
        if (id.isEmpty) continue;
        final rawFields = found['fields'];
        if (rawFields is! Map) continue;
        final fields = FirestoreValueCodec.decodeFields(
          Map<String, dynamic>.from(rawFields),
        );
        output[id] = _metadataItem(id, fields);
      }
      return output;
    } on DioException {
      return const <String, MultimediaItem>{};
    } catch (_) {
      return const <String, MultimediaItem>{};
    }
  }

  static MultimediaItem _metadataItem(
    String animeId,
    Map<String, dynamic> source,
  ) {
    final details = _map(source['details']);
    final rating = _map(source['rating']);
    final syncData = <String, String>{};

    void put(String key, dynamic raw) {
      final value = raw?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        syncData[key] = value;
      }
    }

    put('awMalScore', details['mal_mean'] ?? details['mal_score']);
    put(
      'awImdbScore',
      details['imdb_rate'] ??
          details['imdbRate'] ??
          details['imdb_score'] ??
          details['imdbScore'] ??
          rating['imdb_rate'] ??
          rating['imdbRate'] ??
          rating['imdb_score'] ??
          rating['imdbScore'] ??
          source['imdb_rate'] ??
          source['imdbRate'] ??
          source['imdb_score'] ??
          source['imdbScore'],
    );
    put('awScore', rating['rate']);

    final year = _year(details['year'] ?? source['year']);
    final score = _positiveDouble(
      details['mal_mean'] ??
          details['mal_score'] ??
          rating['rate'] ??
          source['score'],
    );
    return MultimediaItem(
      title: '',
      url: 'https://animewitcher.com/watch/${Uri.encodeComponent(animeId)}',
      posterUrl: '',
      year: year,
      score: score,
      syncData: syncData.isEmpty ? null : syncData,
    );
  }

  static String _animeId(MultimediaItem item) {
    final uri = Uri.tryParse(item.url.trim());
    if (uri == null || uri.pathSegments.length < 2) return '';
    final host = uri.host.toLowerCase();
    if (host != 'animewitcher.com' && host != 'www.animewitcher.com') {
      return '';
    }
    if (uri.pathSegments.first.toLowerCase() != 'watch') return '';
    return uri.pathSegments[1].trim();
  }

  static List<dynamic> _list(dynamic raw) {
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : const <dynamic>[];
      } catch (_) {
        return const <dynamic>[];
      }
    }
    return const <dynamic>[];
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is! Map) return const <String, dynamic>{};
    return raw.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static int? _year(dynamic raw) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(
      raw?.toString() ?? '',
    );
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static double? _positiveDouble(dynamic raw) {
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString().trim() ?? '');
    return value != null && value > 0 ? value : null;
  }
}
