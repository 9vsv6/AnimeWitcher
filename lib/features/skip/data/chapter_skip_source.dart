import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'skip_service.dart';

/// Skip segments read from the file's own chapter markers.
///
/// Many anime releases ship chapters named "Opening", "OP", "Ending",
/// "Credits", ... . That is per-file data, so it covers episodes nobody has
/// submitted to a crowd-sourced service — the gap AniSkip leaves on a
/// currently-airing show. Only mpv exposes chapters here; the ExoPlayer path
/// has no equivalent, so it simply yields nothing there.
class ChapterSkipSource {
  const ChapterSkipSource._();

  static final List<RegExp> _introPatterns = <RegExp>[
    RegExp(r'\b(opening|op)\b', caseSensitive: false),
    RegExp(r'\bintro\b', caseSensitive: false),
    RegExp(r'\bopening\s*credits\b', caseSensitive: false),
    RegExp(r'\btheme\s*song\b', caseSensitive: false),
  ];

  static final List<RegExp> _outroPatterns = <RegExp>[
    RegExp(r'\b(ending|ed)\b', caseSensitive: false),
    RegExp(r'\b(outro|outtro)\b', caseSensitive: false),
    RegExp(r'\bend\s*credits?\b', caseSensitive: false),
    RegExp(r'\bclosing\s*credits?\b', caseSensitive: false),
    RegExp(r'\bcredits?\b', caseSensitive: false),
  ];

  static final List<RegExp> _recapPatterns = <RegExp>[
    RegExp(r'\b(recap|previously)\b', caseSensitive: false),
  ];

  static SkipType? classify(String title) {
    final value = title.trim();
    if (value.isEmpty) return null;
    for (final pattern in _recapPatterns) {
      if (pattern.hasMatch(value)) return SkipType.recap;
    }
    for (final pattern in _introPatterns) {
      if (pattern.hasMatch(value)) return SkipType.intro;
    }
    for (final pattern in _outroPatterns) {
      if (pattern.hasMatch(value)) return SkipType.outro;
    }
    return null;
  }

  /// Reads `chapter-list` off the running mpv instance. Each recognised
  /// chapter runs until the next one starts (or the end of the episode).
  static Future<List<SkipSegment>> read(
    Player player, {
    double? durationSec,
  }) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const <SkipSegment>[];

    final chapters = <({double start, String title})>[];
    try {
      final rawCount = await platform.getProperty('chapter-list/count');
      final count = int.tryParse(rawCount.trim()) ?? 0;
      if (kDebugMode) {
        debugPrint('Chapters: chapter-list/count = "$rawCount" -> $count');
      }
      if (count <= 0) return const <SkipSegment>[];

      for (var i = 0; i < count; i++) {
        final rawTime = await platform.getProperty('chapter-list/$i/time');
        final start = double.tryParse(rawTime.trim());
        if (start == null || start.isNaN || start.isInfinite) continue;
        final title = await platform.getProperty('chapter-list/$i/title');
        chapters.add((start: start < 0 ? 0 : start, title: title));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Chapters: read failed ($e)');
      // No chapters, or the property is unavailable on this build.
      return const <SkipSegment>[];
    }

    if (chapters.isEmpty) return const <SkipSegment>[];
    chapters.sort((a, b) => a.start.compareTo(b.start));

    final segments = <SkipSegment>[];
    for (var i = 0; i < chapters.length; i++) {
      final type = classify(chapters[i].title);
      if (type == null) continue;
      final start = chapters[i].start;
      // A chapter ends where the next begins; the last one runs to the end of
      // the episode, falling back to a typical 90s theme when the duration
      // isn't known yet.
      final double end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (durationSec != null && durationSec > start
                ? durationSec
                : start + 90);
      if (end <= start) continue;
      segments.add(SkipSegment(startTime: start, endTime: end, type: type));
    }

    return SkipSegment.sanitize(segments, durationSec: durationSec);
  }
}
