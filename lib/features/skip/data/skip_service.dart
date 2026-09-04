abstract class SkipService {
  /// Unique identifier for the skip service
  String get name;

  /// Fetch skip segments for a specific episode
  ///
  /// The [tmdbId], [imdbId], [anilistId], or [malId] can be used depending on
  /// the service (AniSkip keys off MyAnimeList ids, IntroDB off IMDb, ...).
  Future<List<SkipSegment>> getSkipSegments({
    int? tmdbId,
    String? imdbId,
    int? anilistId,
    int? malId,
    required int season,
    required int episode,
    int? duration,
  });
}

class SkipSegment {
  final double startTime; // in seconds
  final double endTime; // in seconds
  final SkipType type;

  SkipSegment({
    required this.startTime,
    required this.endTime,
    required this.type,
  });

  /// Filter / repair / sort a raw list of skip segments before handing it
  /// to the UI. Crowdsourced segment data (IntroDB, AnimeSkip) regularly
  /// contains:
  ///
  /// - **Zero-length segments** (`start == end`) — the position check
  ///   `pos >= start && pos < end` never matches, so they're dead weight
  ///   that we still pay to walk every frame.
  /// - **Backwards segments** (`start > end`) — `_handleSkip` would seek
  ///   to a point earlier than the current position, sending the user
  ///   *backwards*. Almost always a data-entry mistake; reorder them.
  /// - **Out-of-range segments** (`end > duration`, negative starts) —
  ///   tapping Skip would seek past the end of the file. media_kit clamps
  ///   but the UX is a jarring snap-to-EOF.
  ///
  /// Sorting by startTime also lets `_checkPosition` early-exit once it
  /// finds a match (segments cannot overlap after sorting + dedupe).
  static List<SkipSegment> sanitize(
    List<SkipSegment> raw, {
    double? durationSec,
  }) {
    if (raw.isEmpty) return raw;
    final cleaned = <SkipSegment>[];
    for (final seg in raw) {
      var start = seg.startTime;
      var end = seg.endTime;
      // Swap if backwards.
      if (start > end) {
        final tmp = start;
        start = end;
        end = tmp;
      }
      // Drop negative starts (clamp to 0).
      if (start < 0) start = 0;
      // Clamp to known duration if we have one.
      if (durationSec != null && durationSec > 0) {
        if (start >= durationSec) continue; // segment is entirely past end
        if (end > durationSec) end = durationSec;
      }
      // Drop zero/negative-length after clamps.
      if (end - start < 1.0) continue;
      // Filter out unknown segments to avoid random "Skip" buttons
      if (seg.type == SkipType.unknown) continue;

      cleaned.add(SkipSegment(startTime: start, endTime: end, type: seg.type));
    }
    cleaned.sort((a, b) => a.startTime.compareTo(b.startTime));
    return cleaned;
  }

  /// Longest run a real opening/ending/recap takes. Anything past this is a
  /// mislabelled chapter covering the body of the episode.
  static const double _maxSegmentSec = 360;

  /// An ending never starts in the first half of an episode. Guards against
  /// a chapter called "credits" that actually marks an opening credit roll.
  static const double _minOutroStartFraction = 0.5;

  /// Combines several sources, best first: a segment is kept only when it
  /// does not overlap one an earlier source already provided. That lets a
  /// lower-priority source fill the gaps — chapters covering the episodes
  /// nobody submitted to AniSkip — without ever contradicting a better one.
  static List<SkipSegment> merge(
    List<List<SkipSegment>> sourcesInPriority, {
    double? durationSec,
  }) {
    final merged = <SkipSegment>[];
    for (final source in sourcesInPriority) {
      for (final segment in source) {
        final overlaps = merged.any(
          (existing) =>
              segment.startTime < existing.endTime &&
              segment.endTime > existing.startTime,
        );
        if (!overlaps) merged.add(segment);
      }
    }

    final hasDuration = durationSec != null && durationSec > 0;
    final minOutroStart = hasDuration
        ? durationSec * _minOutroStartFraction
        : 0.0;

    final result = <SkipSegment>[];
    for (final segment in merged) {
      if (hasDuration && segment.startTime >= durationSec) continue;
      final end = hasDuration && segment.endTime > durationSec
          ? durationSec
          : segment.endTime;
      final length = end - segment.startTime;
      if (length < 2 || length > _maxSegmentSec) continue;
      if (segment.type == SkipType.outro && segment.startTime < minOutroStart) {
        continue;
      }
      result.add(
        SkipSegment(
          startTime: segment.startTime,
          endTime: end,
          type: segment.type,
        ),
      );
    }

    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }
}

enum SkipType {
  intro,
  outro,
  recap,
  unknown;

  static SkipType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'intro':
      case 'new intro':
        return SkipType.intro;
      case 'outro':
      case 'credits':
        return SkipType.outro;
      case 'recap':
        return SkipType.recap;
      default:
        return SkipType.unknown;
    }
  }
}
