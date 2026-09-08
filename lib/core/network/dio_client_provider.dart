import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'stale_connection_retry.dart';

part 'dio_client_provider.g.dart';

const List<String> _similarCardMetadataAttributes = <String>[
  'details',
  'rating',
  'year',
  'imdb_rate',
  'imdbRate',
  'imdb_score',
  'imdbScore',
  'mal_id',
  'malId',
];

/// `series_similar` used to return a deliberately lightweight hit and the UI
/// then issued a separate Firestore `batchGet` for year/rating. Keep cards on
/// one network request instead: extend the original Algolia request so its hit
/// already contains every field `_mapHit` needs for year and rating.
void _includeSimilarCardMetadata(RequestOptions options) {
  if (!options.path.contains('/1/indexes/series_similar/query')) return;

  final rawData = options.data;
  if (rawData is! Map) return;
  final rawParams = rawData['params'];
  if (rawParams is! String || rawParams.isEmpty) return;

  final parts = rawParams.split('&');
  const key = 'attributesToRetrieve=';
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    if (!part.startsWith(key)) continue;

    try {
      final decoded = Uri.decodeQueryComponent(part.substring(key.length));
      final rawAttributes = jsonDecode(decoded);
      if (rawAttributes is! List) return;

      final attributes = rawAttributes
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: true);
      for (final attribute in _similarCardMetadataAttributes) {
        if (!attributes.contains(attribute)) attributes.add(attribute);
      }

      parts[index] = '$key${Uri.encodeQueryComponent(jsonEncode(attributes))}';
      options.data = <String, dynamic>{
        ...Map<String, dynamic>.from(rawData),
        'params': parts.join('&'),
      };
    } catch (_) {
      // Preserve the original request if its Algolia params are malformed.
    }
    return;
  }
}

@riverpod
Dio dioClient(Ref ref) {
  final dio = createAnimeWitcherDio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        _includeSimilarCardMetadata(options);
        handler.next(options);
      },
    ),
  );
  return dio;
}
