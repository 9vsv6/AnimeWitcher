String _normalizeEpisodeDigits(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const eastern = '۰۱۲۳۴۵۶۷۸۹';
  return value
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (m) => '${arabic.indexOf(m.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (m) => '${eastern.indexOf(m.group(0)!)}',
      );
}

String _normalizeEpisodeLabel(String value) {
  return _normalizeEpisodeDigits(value.trim().toLowerCase())
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// True when [value] is only a generic episode placeholder such as
/// "الحلقة 12", "حلقة 12 والأخيرة", or "Episode 3".
bool isGenericEpisodeTitle(String? value) {
  final title = _normalizeEpisodeLabel(value ?? '');
  if (title.isEmpty) return true;
  return RegExp(
        r'^(?:ال)?حلق[ةه]\s*\d+(?:\s+(?:والأخيرة|والاخيرة))?$',
      ).hasMatch(title) ||
      RegExp(
        r'^(?:episode|ep\.?)\s*\d+(?:\s+(?:final|last))?$',
        caseSensitive: false,
      ).hasMatch(title) ||
      RegExp(r'^\d+$').hasMatch(title);
}

/// True when [value] ends with a final-episode suffix such as "والأخيرة".
bool hasFinalEpisodeSuffix(String? value) {
  final title = _normalizeEpisodeLabel(value ?? '');
  if (title.isEmpty) return false;
  return RegExp(r'(?:والأخيرة|والاخيرة)\s*$').hasMatch(title) ||
      RegExp(
        r'(?:\(\s*)?(?:final|last)(?:\s*\))?\s*$',
        caseSensitive: false,
      ).hasMatch(title);
}

/// Real creative title only; empty when missing or generic.
String realEpisodeTitle(String? title) {
  final value = (title ?? '').trim();
  if (value.isEmpty || isGenericEpisodeTitle(value)) return '';
  return value;
}

/// Primary episode name line: "حلقة 12" or "حلقة 12 والأخيرة".
String formatEpisodeNumberLabel({
  required int episode,
  required bool isArabic,
  bool isFinal = false,
  String? rawName,
}) {
  final finalEpisode =
      isFinal || hasFinalEpisodeSuffix(rawName);
  if (isArabic) {
    return finalEpisode ? 'حلقة $episode والأخيرة' : 'حلقة $episode';
  }
  return finalEpisode ? 'Episode $episode (Final)' : 'Episode $episode';
}

String formatEpisodeLabel({
  required int episode,
  required bool isArabic,
  String? title,
  bool isFinal = false,
}) {
  final serverTitle = realEpisodeTitle(title);
  if (episode <= 0) return serverTitle;
  final prefix = formatEpisodeNumberLabel(
    episode: episode,
    isArabic: isArabic,
    isFinal: isFinal,
    rawName: title,
  );
  return serverTitle.isEmpty ? prefix : '$prefix: $serverTitle';
}

String formatEpisodeFileName({
  required int episode,
  String? title,
  String? quality,
  bool isFinal = false,
}) {
  final serverTitle = realEpisodeTitle(title);
  final base = episode > 0
      ? formatEpisodeLabel(
          episode: episode,
          isArabic: true,
          title: serverTitle,
          isFinal: isFinal,
        )
      : serverTitle;
  final normalizedQuality = quality?.trim() ?? '';
  return normalizedQuality.isEmpty ? base : '$base ($normalizedQuality)';
}

/// Title persisted in watch history / sync. Keeps a final-episode marker when
/// there is no creative title so "والأخيرة" survives round-trips.
String episodeTitleForStorage({
  required int episode,
  String? title,
  bool isFinal = false,
}) {
  final real = realEpisodeTitle(title);
  if (real.isNotEmpty) return real;
  if ((isFinal || hasFinalEpisodeSuffix(title)) && episode > 0) {
    return formatEpisodeNumberLabel(
      episode: episode,
      isArabic: true,
      isFinal: true,
    );
  }
  return '';
}
