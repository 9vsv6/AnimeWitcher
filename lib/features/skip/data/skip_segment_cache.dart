import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/storage/storage_service.dart';
import 'skip_service.dart';

part 'skip_segment_cache.g.dart';

/// Skip segments kept on disk so they survive going offline.
///
/// Every online source needs the network, which a downloaded episode played
/// on a plane does not have. Whatever gets resolved while online is written
/// here, and downloading an episode resolves its segments up front, so the
/// skip button still works with no connection.
class SkipSegmentCache {
  final StorageService _storage;

  SkipSegmentCache(this._storage);

  static const String _key = 'skip_segments_cache_json';

  /// Enough for a long backlog of downloads without growing without bound;
  /// the oldest entries fall off first.
  static const int _maxEntries = 1000;

  /// Keyed by the episode's catalog URL, which is the one identifier that is
  /// still known with no network. A MyAnimeList id has to be resolved online,
  /// so it can only ever be a secondary key.
  static String keyForEpisodeUrl(String episodeUrl) => 'url:${episodeUrl.trim()}';

  static String keyForMal(int malId, int episode) => 'mal:$malId:$episode';

  Map<String, dynamic> _readAll() {
    try {
      final raw = _storage.getString(_key);
      if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> value) async {
    try {
      await _storage.setString(_key, jsonEncode(value));
    } catch (_) {}
  }

  List<SkipSegment> read(String key) {
    final entry = _readAll()[key];
    if (entry is! List) return const <SkipSegment>[];
    final out = <SkipSegment>[];
    for (final raw in entry) {
      if (raw is! Map) continue;
      final start = (raw['start'] as num?)?.toDouble();
      final end = (raw['end'] as num?)?.toDouble();
      final type = SkipType.fromString('${raw['type']}');
      if (start == null || end == null || end <= start) continue;
      if (type == SkipType.unknown) continue;
      out.add(SkipSegment(startTime: start, endTime: end, type: type));
    }
    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    return out;
  }

  /// Reads whichever key has data, preferring the offline-safe URL key.
  List<SkipSegment> readAny(List<String> keys) {
    for (final key in keys) {
      final segments = read(key);
      if (segments.isNotEmpty) return segments;
    }
    return const <SkipSegment>[];
  }

  Future<void> write(List<String> keys, List<SkipSegment> segments) async {
    if (keys.isEmpty || segments.isEmpty) return;
    final all = _readAll();
    final encoded = segments
        .map(
          (s) => <String, dynamic>{
            'type': s.type.name,
            'start': s.startTime,
            'end': s.endTime,
          },
        )
        .toList();
    for (final key in keys) {
      // Re-inserting moves the entry to the end, so the eviction below drops
      // the least recently written rather than an episode still in use.
      all.remove(key);
      all[key] = encoded;
    }
    while (all.length > _maxEntries) {
      all.remove(all.keys.first);
    }
    await _writeAll(all);
  }
}

@riverpod
SkipSegmentCache skipSegmentCache(Ref ref) {
  return SkipSegmentCache(ref.watch(storageServiceProvider));
}
