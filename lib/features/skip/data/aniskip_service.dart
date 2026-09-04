import 'dart:collection';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'skip_service.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/network/dio_client_provider.dart';

part 'aniskip_service.g.dart';

/// AniSkip (https://github.com/aniskip) — crowd-sourced opening/ending
/// timestamps keyed by MyAnimeList id.
///
/// Unlike anime-skip.com this needs no client id, so it works in every
/// build; it is the primary source for anime intro/credits segments.
class AniSkipService implements SkipService {
  final Dio _dio;

  AniSkipService(this._dio);

  @override
  String get name => 'AniSkip';

  /// Only the clean-cut types. `mixed-op` / `mixed-ed` are openings and
  /// endings that play over episode content — skipping those would skip
  /// story, and they also come back even when their timings belong to a
  /// different release, which would show a second, wrong "Skip intro".
  static const List<String> _types = <String>['op', 'ed', 'recap'];

  // Same caching shape as IntroDB: an hour of results, LRU-capped, so
  // seeking around an episode doesn't re-query per seek.
  static const int _cacheMax = 500;
  static const Duration _cacheTtl = Duration(hours: 1);
  static final LinkedHashMap<String, _CachedSegments> _cache =
      LinkedHashMap<String, _CachedSegments>();

  // Global cool-off after a 429 so we don't amplify a rate limit.
  static DateTime? _rateLimitUntil;

  // The response depends on the episode length we send, so it is part of
  // the key — a lookup made before the duration was known must not shadow
  // the better-matched one that follows.
  String _key(int malId, int episode, int episodeLength) =>
      '$malId:$episode:$episodeLength';

  List<SkipSegment>? _lookupCached(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    _cache.remove(key);
    _cache[key] = entry;
    return entry.segments;
  }

  void _store(String key, List<SkipSegment> segments) {
    _cache.remove(key);
    _cache[key] = _CachedSegments(segments, DateTime.now().add(_cacheTtl));
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
  }

  static SkipType _typeFor(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'op':
      case 'mixed-op':
        return SkipType.intro;
      case 'ed':
      case 'mixed-ed':
        return SkipType.outro;
      case 'recap':
        return SkipType.recap;
      default:
        return SkipType.unknown;
    }
  }

  @override
  Future<List<SkipSegment>> getSkipSegments({
    int? tmdbId,
    String? imdbId,
    int? anilistId,
    int? malId,
    required int season,
    required int episode,
    int? duration,
  }) async {
    if (malId == null || malId <= 0) return [];

    // `episodeLength` is required by the API — 0 means "unknown", which
    // returns every submission unscaled. Dio's default list encoding writes
    // the repeated `types[]=op&types[]=ed&...` form the API expects.
    final episodeLength = (duration != null && duration > 0) ? duration : 0;

    final key = _key(malId, episode, episodeLength);
    final cached = _lookupCached(key);
    if (cached != null) return cached;

    final until = _rateLimitUntil;
    if (until != null && DateTime.now().isBefore(until)) return [];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.aniskip.com/v2/skip-times/$malId/$episode',
        queryParameters: <String, dynamic>{
          'types': _types,
          'episodeLength': episodeLength,
        },
      );
      final data = response.data;
      if (response.statusCode == 200 && data != null && data['found'] == true) {
        final results = data['results'];
        // The API can return several submissions of the same type, each
        // timed against a different release length. Keep one per type —
        // the one whose episodeLength sits closest to this file's.
        final best = <SkipType, _Candidate>{};
        if (results is List) {
          for (final raw in results) {
            if (raw is! Map) continue;
            final interval = raw['interval'];
            if (interval is! Map) continue;
            final start = (interval['startTime'] as num?)?.toDouble();
            final end = (interval['endTime'] as num?)?.toDouble();
            if (start == null || end == null) continue;
            final type = _typeFor(raw['skipType']);
            if (type == SkipType.unknown) continue;

            final entryLength = (raw['episodeLength'] as num?)?.toDouble();
            final drift = (duration != null && entryLength != null)
                ? (entryLength - duration).abs()
                : double.infinity;
            final current = best[type];
            if (current == null || drift < current.drift) {
              best[type] = _Candidate(
                SkipSegment(startTime: start, endTime: end, type: type),
                drift,
              );
            }
          }
        }

        final cleaned = SkipSegment.sanitize(
          best.values.map((c) => c.segment).toList(),
          durationSec: duration?.toDouble(),
        );
        _store(key, cleaned);
        return cleaned;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final retryAfter = _parseRetryAfter(
          e.response?.headers.value('retry-after'),
        );
        _rateLimitUntil = DateTime.now().add(retryAfter);
        talker.debug(
          'AniSkip rate-limited; holding off ${retryAfter.inSeconds}s',
        );
      }
      // 404 simply means nobody has submitted timestamps for this episode.
    } catch (_) {
      // Ignore — the caller treats an empty list as "no skip data".
    }

    // Cache the miss too, so a seek-heavy session doesn't re-ask every time.
    _store(key, const []);
    return [];
  }

  /// Derives segments for an episode nobody has submitted from the episodes
  /// around it, and only when those agree closely.
  ///
  /// Endings sit at a near-fixed offset from the end of an episode, so they
  /// cluster tightly and can be placed confidently. Openings often move by
  /// minutes between episodes, and the spread check rejects them rather than
  /// putting the button somewhere that would skip real story.
  Future<List<SkipSegment>> estimateFromNeighbours({
    required int malId,
    required int episode,
    required int episodeLength,
    int radius = 4,
  }) async {
    if (malId <= 0 || episodeLength <= 0) return const <SkipSegment>[];

    // Offsets measured from the start for openings and from the end for
    // endings, which is what actually stays constant across episodes.
    final introStarts = <double>[];
    final introEnds = <double>[];
    final outroFromEndStarts = <double>[];
    final outroFromEndEnds = <double>[];

    for (var offset = 1; offset <= radius; offset++) {
      for (final neighbour in <int>[episode - offset, episode + offset]) {
        if (neighbour < 1 || neighbour == episode) continue;
        final segments = await getSkipSegments(
          malId: malId,
          season: 1,
          episode: neighbour,
          duration: episodeLength,
        );
        for (final segment in segments) {
          if (segment.type == SkipType.intro) {
            introStarts.add(segment.startTime);
            introEnds.add(segment.endTime);
          } else if (segment.type == SkipType.outro) {
            outroFromEndStarts.add(episodeLength - segment.startTime);
            outroFromEndEnds.add(episodeLength - segment.endTime);
          }
        }
      }
    }

    final out = <SkipSegment>[];
    final intro = _agreedSegment(introStarts, introEnds);
    if (intro != null) {
      out.add(
        SkipSegment(
          startTime: intro.$1,
          endTime: intro.$2,
          type: SkipType.intro,
        ),
      );
    }
    final outro = _agreedSegment(outroFromEndStarts, outroFromEndEnds);
    if (outro != null) {
      final start = episodeLength - outro.$1;
      final end = episodeLength - outro.$2;
      if (end > start) {
        out.add(
          SkipSegment(startTime: start, endTime: end, type: SkipType.outro),
        );
      }
    }

    return SkipSegment.sanitize(out, durationSec: episodeLength.toDouble());
  }

  /// At least three neighbours, all within [_agreementToleranceSec] of each
  /// other on both edges. Anything looser is a guess, not an estimate.
  static const int _minAgreeingNeighbours = 3;
  static const double _agreementToleranceSec = 8;

  static (double, double)? _agreedSegment(
    List<double> starts,
    List<double> ends,
  ) {
    if (starts.length < _minAgreeingNeighbours) return null;
    if (starts.length != ends.length) return null;
    final startSpread = starts.reduce(max) - starts.reduce(min);
    final endSpread = ends.reduce(max) - ends.reduce(min);
    if (startSpread > _agreementToleranceSec) return null;
    if (endSpread > _agreementToleranceSec) return null;
    final medianStart = _median(starts);
    final medianEnd = _median(ends);
    if (medianEnd <= medianStart) return null;
    return (medianStart, medianEnd);
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  Duration _parseRetryAfter(String? header) {
    if (header == null) return const Duration(seconds: 60);
    final seconds = int.tryParse(header.trim());
    if (seconds == null || seconds < 0) return const Duration(seconds: 60);
    if (seconds > 300) return const Duration(minutes: 5);
    return Duration(seconds: seconds);
  }
}

class _CachedSegments {
  _CachedSegments(this.segments, this.expiresAt);
  final List<SkipSegment> segments;
  final DateTime expiresAt;
}

/// A candidate segment plus how far its submitted episode length is from
/// the file being played — lower wins when a type has several entries.
class _Candidate {
  _Candidate(this.segment, this.drift);
  final SkipSegment segment;
  final double drift;
}

@riverpod
AniSkipService aniSkipService(Ref ref) {
  return AniSkipService(ref.watch(dioClientProvider));
}
