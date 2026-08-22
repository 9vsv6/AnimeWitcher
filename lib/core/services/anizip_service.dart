import 'package:dio/dio.dart';

import '../domain/entity/multimedia_item.dart';

/// Best-effort AniZip enrichment for anime episode metadata.
///
/// AniZip is used for episode artwork and optional season metadata. The
/// canonical episode identity (including a known season) remains owned by the
/// source provider so multi-season anime cannot disappear from the UI.
class AniZipService {
  AniZipService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.ani.zip',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 8),
                responseType: ResponseType.json,
              ),
            );

  final Dio _dio;

  Future<List<Episode>?> enrichEpisodes(
    MultimediaItem item,
    List<Episode> sourceEpisodes,
  ) async {
    if (sourceEpisodes.isEmpty) return null;

    final ids = _candidateIds(item.syncData);
    if (ids.isEmpty) return null;

    _AniZipPayload? payload;
    for (final id in ids) {
      final result = await _fetchMappings(id.type, id.value);
      if (result != null && result.episodes.isNotEmpty) {
        payload = result;
        break;
      }
    }
    if (payload == null || payload.episodes.isEmpty) return null;

    final mappings = payload.episodes;
    final sharedSeason = payload.seasonNumber;
    var changed = false;

    final enriched = sourceEpisodes.map((source) {
      final candidates = mappings[source.episode];
      if (candidates == null || candidates.isEmpty) return source;

      _AniZipEpisode? match;
      if (source.season > 0) {
        match = candidates.firstWhereOrNull(
          (candidate) => candidate.seasonNumber == source.season,
        );
      }
      match ??= candidates.first;

      final image = match.image?.trim();
      // AnimeWitcher is the canonical source for episode season identity.
      // AniZip's season is metadata only: never overwrite a known source season,
      // otherwise Season 2+ titles can be moved into Season 1 and disappear
      // from the selected-season list. If the source has no season, resolve it
      // once from the shared AniZip response (or the matched episode).
      final nextSeason = source.season > 0
          ? source.season
          : (sharedSeason > 0
              ? sharedSeason
              : (match.seasonNumber > 0 ? match.seasonNumber : source.season));
      final nextPoster = image != null && image.isNotEmpty
          ? image
          : source.posterUrl;

      if (nextSeason == source.season && nextPoster == source.posterUrl) {
        return source;
      }
      changed = true;
      return Episode(
        name: source.name,
        url: source.url,
        season: nextSeason,
        episode: source.episode,
        description: source.description,
        posterUrl: nextPoster,
        headers: source.headers,
        isFiller: source.isFiller,
        rating: source.rating,
        runtime: source.runtime,
        airDate: source.airDate,
        dubStatus: source.dubStatus,
        playbackPolicy: source.playbackPolicy,
        streams: source.streams,
      );
    }).toList(growable: false);

    return changed ? enriched : sourceEpisodes;
  }

  Future<_AniZipPayload?> _fetchMappings(
    String type,
    int id,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/mappings',
        queryParameters: {type: id},
      );
      final data = response.data;
      if (response.statusCode != 200 || data == null) return null;

      final rawEpisodes = data['episodes'];
      final result = <int, List<_AniZipEpisode>>{};
      if (rawEpisodes is Map) {
        for (final value in rawEpisodes.values) {
          if (value is! Map) continue;
          final episode = _AniZipEpisode.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (episode.episodeNumber <= 0) continue;
          result.putIfAbsent(episode.episodeNumber, () => []).add(episode);
        }
      } else if (rawEpisodes is List) {
        for (final value in rawEpisodes) {
          if (value is! Map) continue;
          final episode = _AniZipEpisode.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (episode.episodeNumber <= 0) continue;
          result.putIfAbsent(episode.episodeNumber, () => []).add(episode);
        }
      }

      final seasons = result.values
          .expand((items) => items)
          .map((episode) => episode.seasonNumber)
          .where((season) => season > 0)
          .toList(growable: false);
      final sharedSeason = seasons.isEmpty
          ? 0
          : seasons.fold<int>(
              seasons.first,
              (current, value) => value == current ? current : 0,
            );

      return _AniZipPayload(
        episodes: result,
        seasonNumber: sharedSeason,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  List<_AniZipId> _candidateIds(Map<String, String>? syncData) {
    if (syncData == null || syncData.isEmpty) return const [];
    final result = <_AniZipId>[];
    final seen = <String>{};
    for (final entry in syncData.entries) {
      final key = entry.key.toLowerCase();
      final value = int.tryParse(entry.value.trim());
      if (value == null || value <= 0) continue;
      final type = switch (key) {
        'mal_id' || 'mal' || 'myanimelist_id' => 'mal_id',
        'anilist_id' || 'anilist' => 'anilist_id',
        _ => null,
      };
      if (type == null) continue;
      final unique = '$type:$value';
      if (seen.add(unique)) {
        result.add(_AniZipId(type: type, value: value));
      }
    }
    return result;
  }
}

class _AniZipId {
  final String type;
  final int value;
  const _AniZipId({required this.type, required this.value});
}

class _AniZipPayload {
  final Map<int, List<_AniZipEpisode>> episodes;
  final int seasonNumber;
  const _AniZipPayload({required this.episodes, required this.seasonNumber});
}

class _AniZipEpisode {
  final int episodeNumber;
  final int seasonNumber;
  final String? image;
  const _AniZipEpisode({
    required this.episodeNumber,
    required this.seasonNumber,
    required this.image,
  });

  factory _AniZipEpisode.fromJson(Map<String, dynamic> json) {
    return _AniZipEpisode(
      episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      image: json['image']?.toString(),
    );
  }
}

extension on Iterable<_AniZipEpisode> {
  _AniZipEpisode? firstWhereOrNull(bool Function(_AniZipEpisode) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
