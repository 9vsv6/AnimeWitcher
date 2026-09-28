import 'multimedia_item.dart';

const List<String> defaultStreamServerPriority = <String>[
  'PD',
  'MF',
  'ST',
  'SF',
  'GF',
  'KF',
];

const List<String> defaultStreamQualityPriority = <String>[
  '2160p',
  '1080p',
  '720p',
  '480p',
  '360p',
  'متعدد',
];

List<String> normalizeStreamPriority(
  Iterable<Object?>? raw,
  List<String> defaults,
) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in raw ?? const <Object?>[]) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || !seen.add(text.toLowerCase())) continue;
    result.add(text);
  }
  for (final value in defaults) {
    if (seen.add(value.toLowerCase())) result.add(value);
  }
  return List<String>.unmodifiable(result);
}

StreamResult? selectPreferredStreamSource(
  List<StreamResult> sources, {
  required List<String> qualityPriority,
  required List<String> serverPriority,
}) {
  if (sources.isEmpty) return null;
  final ordered = List<({StreamResult source, int index})>.generate(
    sources.length,
    (index) => (source: sources[index], index: index),
    growable: false,
  );

  int rank(List<String> priority, String value) {
    final wanted = value.toLowerCase();
    final index = priority.indexWhere(
      (entry) => entry.toLowerCase() == wanted,
    );
    return index < 0 ? priority.length : index;
  }

  ordered.sort((a, b) {
    final qualityA = streamQualityPreferenceKey(a.source.quality);
    final qualityB = streamQualityPreferenceKey(b.source.quality);
    final rankA = rank(qualityPriority, qualityA);
    final rankB = rank(qualityPriority, qualityB);
    final qualityCompare = rankA.compareTo(rankB);
    if (qualityCompare != 0) return qualityCompare;

    if (rankA == qualityPriority.length) {
      final scoreCompare = _qualityScore(
        b.source.quality,
      ).compareTo(_qualityScore(a.source.quality));
      if (scoreCompare != 0) return scoreCompare;
    }

    final serverA = streamServerPreferenceKey(a.source.source);
    final serverB = streamServerPreferenceKey(b.source.source);
    final serverCompare = rank(
      serverPriority,
      serverA,
    ).compareTo(rank(serverPriority, serverB));
    if (serverCompare != 0) return serverCompare;

    return a.index.compareTo(b.index);
  });

  return ordered.first.source;
}

String streamServerPreferenceKey(String source) {
  final normalized = source.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (normalized.startsWith('PD') || normalized.contains('PIXELDRAIN')) {
    return 'PD';
  }
  if (normalized.startsWith('MF') ||
      normalized == 'MD' ||
      normalized.contains('MEDIAFIRE')) {
    return 'MF';
  }
  if (normalized.startsWith('ST') || normalized.contains('STREAMTAPE')) {
    return 'ST';
  }
  if (normalized.startsWith('SF')) return 'SF';
  return source.trim().toUpperCase();
}

String streamQualityPreferenceKey(String? quality) {
  final score = _qualityScore(quality);
  if (score > 0) return '${score}p';

  final raw = quality?.trim() ?? '';
  final lower = raw.toLowerCase();
  if (raw.contains('متعدد') ||
      lower.contains('multi') ||
      lower.contains('auto')) {
    return 'متعدد';
  }
  return raw;
}

int _qualityScore(String? quality) {
  final raw = quality?.trim();
  if (raw == null || raw.isEmpty) return -1;
  final lower = raw.toLowerCase();
  final numeric = RegExp(r'(\d{3,4})').firstMatch(lower);
  if (numeric != null) return int.tryParse(numeric.group(1)!) ?? -1;
  if (lower.contains('4k') || lower.contains('uhd')) return 2160;
  if (lower.contains('fhd') || lower.contains('fullhd')) return 1080;
  if (lower == 'hd' || lower.contains('hd')) return 720;
  if (lower.contains('sd')) return 480;
  return -1;
}
