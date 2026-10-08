import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'skip_service.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/network/dio_client_provider.dart';

/// Two more keyless, IMDb-keyed databases of intros, recaps and credits.
/// Each is crowd-sourced on its own, so together they cover episodes that
/// AniSkip and TheIntroDB have no submissions for:
///
/// - IntroDB.app (https://introdb.app): `GET /segments`.
/// - SkipDB (https://skipdb.tv): `GET /api/segments`, which also takes the
///   stream's length and shifts its times to fit a cut that is a few seconds
///   longer or shorter than the one submitted.

/// IntroDB.app's answer: one object or null per kind, in milliseconds. A
/// post-credits scene is something to watch, not skip, so it is left out.
List<SkipSegment> parseIntroDbAppSegments(Object? body, {double? durationSec}) {
  if (body is! Map) return const <SkipSegment>[];
  final out = <SkipSegment>[];
  void collect(String key, SkipType type) {
    final span = _span(body[key], durationSec: durationSec, type: type);
    if (span != null) out.add(span);
  }

  collect('intro', SkipType.intro);
  collect('recap', SkipType.recap);
  collect('outro', SkipType.outro);
  out.sort((a, b) => a.startTime.compareTo(b.startTime));
  return out;
}

/// SkipDB's answer: `segments` holds one object or null per kind, in
/// milliseconds. A match SkipDB itself calls out of range was made for a
/// different cut of the episode, so its times cannot be trusted here.
List<SkipSegment> parseSkipDbSegments(Object? body, {double? durationSec}) {
  final segments = body is Map ? body['segments'] : null;
  if (segments is! Map) return const <SkipSegment>[];
  final out = <SkipSegment>[];
  void collect(String key, SkipType type) {
    final raw = segments[key];
    if (raw is Map && raw['match'] == 'out-of-range') return;
    final span = _span(raw, durationSec: durationSec, type: type);
    if (span != null) out.add(span);
  }

  collect('intro', SkipType.intro);
  collect('recap', SkipType.recap);
  collect('outro', SkipType.outro);
  // The next episode's preview runs after the credits; skipping it is
  // skipping to the end, as TheIntroDB's previews are treated.
  collect('preview', SkipType.outro);
  out.sort((a, b) => a.startTime.compareTo(b.startTime));
  return out;
}

SkipSegment? _span(Object? raw, {double? durationSec, required SkipType type}) {
  if (raw is! Map) return null;
  double? seconds(String msKey, String secKey) {
    final ms = raw[msKey];
    if (ms is num) return ms / 1000;
    final sec = raw[secKey];
    return sec is num ? sec.toDouble() : null;
  }

  final start = seconds('start_ms', 'start_sec') ?? 0;
  // An open end runs to the last frame.
  final end = seconds('end_ms', 'end_sec') ?? durationSec;
  if (end == null || end <= start) return null;
  return SkipSegment(startTime: start, endTime: end, type: type);
}

/// One IMDb-keyed source: a request, a parser, and the caching and rate-limit
/// manners TheIntroDB's lookup has, so a fast seek or a binge does not hammer
/// a free public API.
class ImdbSkipSource implements SkipService {
  ImdbSkipSource({
    required this.dio,
    required this.name,
    required this.endpoint,
    required this.query,
    required this.parse,
  });

  final Dio dio;
  final String endpoint;
  final Map<String, dynamic> Function(
    String imdbId,
    int season,
    int episode,
    int? duration,
  )
  query;
  final List<SkipSegment> Function(Object? body, {double? durationSec}) parse;

  @override
  final String name;

  static const int _cacheMax = 500;
  static const Duration _cacheTtl = Duration(hours: 1);
  final LinkedHashMap<String, _CachedSegments> _cache =
      LinkedHashMap<String, _CachedSegments>();
  DateTime? _rateLimitUntil;

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
    final id = imdbId?.trim() ?? '';
    if (!RegExp(r'^tt\d+$').hasMatch(id)) return const <SkipSegment>[];

    final key = '$id:$season:$episode:${duration ?? ''}';
    final cached = _lookupCached(key);
    if (cached != null) return cached;
    final until = _rateLimitUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      return const <SkipSegment>[];
    }

    var answered = false;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: query(id, season, episode, duration),
      );
      answered = response.statusCode == 200;
      if (answered) {
        final cleaned = SkipSegment.sanitize(
          parse(response.data, durationSec: duration?.toDouble()),
          durationSec: duration?.toDouble(),
        );
        _store(key, cleaned);
        return cleaned;
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) {
        _rateLimitUntil = DateTime.now().add(
          _retryAfter(e.response?.headers.value('retry-after')),
        );
        talker.debug('$name rate-limited; holding off');
      }
      // "Nothing for this episode" is an answer worth remembering; a rate
      // limit or a dropped connection is not.
      if (status == 404) answered = true;
    } catch (_) {
      // No skip data from this source.
    }
    if (answered) _store(key, const <SkipSegment>[]);
    return const <SkipSegment>[];
  }

  List<SkipSegment>? _lookupCached(String key) {
    final entry = _cache.remove(key);
    if (entry == null || DateTime.now().isAfter(entry.expiresAt)) return null;
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

  static Duration _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
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

final introDbAppServiceProvider = Provider<ImdbSkipSource>(
  (ref) => ImdbSkipSource(
    dio: ref.watch(dioClientProvider),
    name: 'IntroDB.app',
    endpoint: 'https://api.introdb.app/segments',
    query: (imdbId, season, episode, _) => <String, dynamic>{
      'imdb_id': imdbId,
      'season': season,
      'episode': episode,
    },
    parse: parseIntroDbAppSegments,
  ),
);

final skipDbServiceProvider = Provider<ImdbSkipSource>(
  (ref) => ImdbSkipSource(
    dio: ref.watch(dioClientProvider),
    name: 'SkipDB',
    endpoint: 'https://api.skipdb.tv/api/segments',
    query: (imdbId, season, episode, duration) => <String, dynamic>{
      'imdb_id': imdbId,
      'season': season,
      'episode': episode,
      // Lets SkipDB fit submitted times to this exact cut.
      if (duration != null && duration > 0) 'duration': duration,
    },
    parse: parseSkipDbSegments,
  ),
);
