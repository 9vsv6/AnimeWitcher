import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/dio_client_provider.dart';

part 'mal_id_resolver.g.dart';

/// Resolves an anime title to a MyAnimeList id through AniList's public
/// GraphQL API (free, no key, generous rate limit).
///
/// AniSkip is keyed by MAL id, but the catalog provider identifies anime by
/// title — most items reach the player with no ids at all. This bridges the
/// two so intro/credits skipping works for titles the provider can't key.
class MalIdResolver {
  final Dio _dio;

  MalIdResolver(this._dio);

  static const String _endpoint = 'https://graphql.anilist.co';

  static const String _query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME) {
    idMal
  }
}
''';

  // Titles resolve to the same id forever, so cache generously — including
  // misses, so a title AniList doesn't know isn't re-queried every episode.
  static const int _cacheMax = 300;
  static final LinkedHashMap<String, int?> _cache = LinkedHashMap<String, int?>();

  static DateTime? _rateLimitUntil;

  /// Strips the release noise a catalog title often carries so the search
  /// text stays close to the official title AniList indexes.
  static String normalizeTitle(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    value = value.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  Future<int?> resolve(String title) async {
    final search = normalizeTitle(title);
    if (search.isEmpty) return null;

    final key = search.toLowerCase();
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached; // LRU touch
      return cached;
    }

    final until = _rateLimitUntil;
    if (until != null && DateTime.now().isBefore(until)) return null;

    int? resolved;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: <String, dynamic>{
          'query': _query,
          'variables': <String, dynamic>{'search': search},
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final media = response.data?['data']?['Media'];
      if (media is Map) {
        final idMal = media['idMal'];
        if (idMal is num && idMal > 0) resolved = idMal.toInt();
      }
    } on DioException catch (e) {
      // 404 simply means AniList has no match for this title.
      if (e.response?.statusCode == 429) {
        _rateLimitUntil = DateTime.now().add(const Duration(minutes: 1));
        return null; // don't cache a miss caused by throttling
      }
    } catch (_) {
      // Ignore — the caller treats null as "no id".
    }

    _cache[key] = resolved;
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
    return resolved;
  }
}

@riverpod
MalIdResolver malIdResolver(Ref ref) {
  return MalIdResolver(ref.watch(dioClientProvider));
}
