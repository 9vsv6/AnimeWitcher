import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/entity/multimedia_item.dart';

/// Best-effort AniZip enrichment for anime episode metadata.
///
/// AniZip is used once per anime to resolve one shared season number and
/// episode artwork. The season is intentionally shared across every episode;
/// when AniZip cannot resolve it, Season 1 is used as the fallback.
class AniZipService {
  final Dio _dio;

  AniZipService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.ani.zip',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  Future<List<Episode>?> enrichEpisodes(
    MultimediaItem item,
    List<Episode> sourceEpisodes,
  ) async {
    if (sourceEpisodes.isEmpty) return null;

    const fallbackSeason = 1;
    final ids = _candidateIds(item.syncData);
    if (ids.isEmpty) {
      return _applySharedSeason(sourceEpisodes, fallbackSeason);
    }

    _AniZipPayload? payload;
    for (final id in ids) {
      final result = await _fetchMappings(id.type, id.value);
      if (result != null && result.episodes.isNotEmpty) {
        payload = result;
        break;
      }
    }

    // AniZip is queried once for the anime. Its seasonNumber is shared by
    // every episode; the source does not provide a meaningful season value.
    // If AniZip fails or has no valid season, the whole anime is Season 1.
    final sharedSeason = payload?.seasonNumber ?? fallbackSeason;
    if (payload == null || payload.episodes.isEmpty) {
      return _applySharedSeason(sourceEpisodes, fallbackSeason);
    }

    final mappings = payload.episodes;
    var changed = false;
    final enriched = sourceEpisodes.map((source) {
      final candidates = mappings[source.episode];
      final match = candidates != null && candidates.isNotEmpty
          ? candidates.first
          : null;
      final image = match?.image?.trim();
      final nextPoster = image != null && image.isNotEmpty
          ? image
          : source.posterUrl;

      if (sharedSeason == source.season && nextPoster == source.posterUrl) {
        return source;
      }
      changed = true;
      return Episode(
        name: source.name,
        url: source.url,
        season: sharedSeason,
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

  List<Episode> _applySharedSeason(List<Episode> episodes, int season) {
    var changed = false;
    final resolvedSeason = season > 0 ? season : 1;
    final result = episodes.map((source) {
      if (source.season == resolvedSeason) return source;
      changed = true;
      return Episode(
        name: source.name,
        url: source.url,
        season: resolvedSeason,
        episode: source.episode,
        description: source.description,
        posterUrl: source.posterUrl,
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
    return changed ? result : episodes;
  }

  Future<_AniZipPayload?> _fetchMappings(
    String type,
    String value,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/mappings', queryParameters: {type: value});
      final data = response.data;
      if (response.statusCode != 200 || data == null) return null;

      final rawEpisodes = data['episodes'];
      final result = <int, List<_AniZipEpisode>>{};
      if (rawEpisodes is Map) {
        for (final value in rawEpisodes.values) {
          if (value is! Map) continue;
          final episode = _AniZipEpisode.fromJson(Map<String, dynamic>.from(value));
          if (episode.episodeNumber <= 0) continue;
          result.putIfAbsent(episode.episodeNumber, () => []).add(episode);
        }
      } else if (rawEpisodes is List) {
        for (final value in rawEpisodes) {
          if (value is! Map) continue;
          final episode = _AniZipEpisode.fromJson(Map<String, dynamic>.from(value));
          if (episode.episodeNumber <= 0) continue;
          result.putIfAbsent(episode.episodeNumber, () => []).add(episode);
        }
      }

      final sharedSeason = result.values
          .expand((items) => items)
          .map((episode) => episode.seasonNumber)
          .firstWhere((season) => season > 0, orElse: () => 1);

      // The source provider uses season 1 for every title. AniZip is the
      // authoritative source for the single season assigned to this anime.
      // We intentionally resolve it once from the response and apply it to
      // every episode; episode-level season values are never used separately.
      return _AniZipPayload(episodes: result, seasonNumber: sharedSeason);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  List<_AniZipId> _candidateIds(Map<String, dynamic>? syncData) {
    if (syncData == null) return const [];
    final result = <_AniZipId>[];
    final anilist = syncData['anilist_id'] ?? syncData['anilistId'];
    final mal = syncData['mal_id'] ?? syncData['malId'];
    if (anilist != null && anilist.toString().isNotEmpty) {
      result.add(_AniZipId('anilist_id', anilist.toString()));
    }
    if (mal != null && mal.toString().isNotEmpty) {
      result.add(_AniZipId('mal_id', mal.toString()));
    }
    return result;
  }
}

class _AniZipPayload {
  final Map<int, List<_AniZipEpisode>> episodes;
  final int seasonNumber;
  const _AniZipPayload({required this.episodes, required this.seasonNumber});
}

class _AniZipId {
  final String type;
  final String value;
  const _AniZipId(this.type, this.value);
}

class _AniZipEpisode {
  final int episodeNumber;
  final int seasonNumber;
  final String? image;
  const _AniZipEpisode({required this.episodeNumber, required this.seasonNumber, this.image});

  factory _AniZipEpisode.fromJson(Map<String, dynamic> json) => _AniZipEpisode(
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 0,
        seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
        image: json['image']?.toString(),
      );
}
