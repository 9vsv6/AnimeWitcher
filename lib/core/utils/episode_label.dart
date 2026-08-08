String formatEpisodeLabel({
  required int episode,
  required bool isArabic,
  String? title,
}) {
  final baseLabel = isArabic ? 'حلقة $episode' : 'Episode $episode';
  final normalizedTitle = title?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';

  if (!_hasMeaningfulEpisodeTitle(normalizedTitle)) return baseLabel;
  return '$baseLabel: $normalizedTitle';
}

bool _hasMeaningfulEpisodeTitle(String title) {
  if (title.isEmpty || title.toLowerCase() == 'null') return false;

  final normalized = _normalizeDigits(title.toLowerCase());
  if (RegExp(r'^\d+$').hasMatch(normalized)) return false;

  return !RegExp(
    r'^(?:(?:الحلقة|حلقه|حلقة)|(?:episode|ep\.?))\s*[-:#.]?\s*\d+$',
    caseSensitive: false,
  ).hasMatch(normalized);
}

String _normalizeDigits(String value) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabic = '۰۱۲۳۴۵۶۷۸۹';

  return value
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (match) => '${arabicIndic.indexOf(match.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (match) => '${easternArabic.indexOf(match.group(0)!)}',
      );
}
