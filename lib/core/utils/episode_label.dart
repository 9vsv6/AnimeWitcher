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

/// Movie/OVA catalog labels that AnimeWitcher shows instead of "حلقة N".
bool isStandaloneEpisodeLabel(String? value) {
  final title = _normalizeEpisodeLabel(value ?? '');
  if (title.isEmpty || isGenericEpisodeTitle(title)) return false;
  return RegExp(
    r'^(مترجم|مدبلج|مترجمة|مدبلجة|sub(?:bed)?|dub(?:bed)?)$',
    caseSensitive: false,
  ).hasMatch(title);
}

/// True when an episode row is a مترجم/مدبلج-style catalog entry.
bool isStandaloneEpisodeEntry({String? serverName, String? name}) {
  return isStandaloneEpisodeLabel(serverName) ||
      isStandaloneEpisodeLabel(name);
}

/// True when every episode is a مترجم/مدبلج-style row (hide sub/dub filter).
bool isStandaloneEpisodeCatalog(
  Iterable<({String? serverName, String? name})> episodes,
) {
  final list = episodes.toList(growable: false);
  if (list.isEmpty) return false;
  return list.every(
    (episode) => isStandaloneEpisodeEntry(
      serverName: episode.serverName,
      name: episode.name,
    ),
  );
}

/// Real creative title only; empty when missing or generic/standalone labels.
String realEpisodeTitle(String? title) {
  final value = (title ?? '').trim();
  if (value.isEmpty ||
      isGenericEpisodeTitle(value) ||
      isStandaloneEpisodeLabel(value)) {
    return '';
  }
  return value;
}

/// Catalog / “latest episodes” poster badge.
///
/// Prefer AnimeWitcher’s server episode `name` (e.g. `الحلقة 10 والأخيرة`) so
/// the final-episode suffix is preserved the same way as in the official app.
String formatCatalogEpisodeBadge({
  required int episode,
  String? serverName,
  bool isFinal = false,
  bool isArabic = true,
}) {
  return formatEpisodePrimaryLabel(
    episode: episode,
    isArabic: isArabic,
    isFinal: isFinal,
    serverName: serverName,
  );
}

/// Primary episode name line: "حلقة 12" or "حلقة 12 والأخيرة".
String formatEpisodeNumberLabel({
  required int episode,
  required bool isArabic,
  bool isFinal = false,
  String? rawName,
}) {
  final finalEpisode = isFinal || hasFinalEpisodeSuffix(rawName);
  if (isArabic) {
    return finalEpisode ? 'حلقة $episode والأخيرة' : 'حلقة $episode';
  }
  return finalEpisode ? 'Episode $episode (Final)' : 'Episode $episode';
}

/// Primary label matching AnimeWitcher: prefer the server `name` as-is for
/// standalone labels (مترجم/مدبلج), otherwise build "حلقة X" / "حلقة X والأخيرة".
///
/// [serverName] must stay the original AnimeWitcher `name` field and must not
/// be overwritten by optional AniZip artwork enrichment.
String formatEpisodePrimaryLabel({
  required int episode,
  required bool isArabic,
  bool isFinal = false,
  String? serverName,
}) {
  final raw = (serverName ?? '').trim();
  if (raw.isNotEmpty && !isGenericEpisodeTitle(raw)) {
    return raw;
  }

  var number = episode;
  if (number <= 0 && raw.isNotEmpty) {
    final match = RegExp(r'(\d+)').firstMatch(_normalizeEpisodeDigits(raw));
    number = match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0);
  }

  if (number > 0) {
    return formatEpisodeNumberLabel(
      episode: number,
      isArabic: isArabic,
      isFinal: isFinal,
      rawName: raw,
    );
  }
  return raw;
}

String formatEpisodeLabel({
  required int episode,
  required bool isArabic,
  String? title,
  bool isFinal = false,
  String? serverName,
}) {
  final serverTitle = realEpisodeTitle(title);
  // Prefer AnimeWitcher serverName; if missing, a generic title like
  // "الحلقة 12 والأخيرة" still carries the final-episode marker for downloads.
  final resolvedServerName = () {
    final server = (serverName ?? '').trim();
    if (server.isNotEmpty) return server;
    final rawTitle = (title ?? '').trim();
    if (rawTitle.isNotEmpty && isGenericEpisodeTitle(rawTitle)) {
      return rawTitle;
    }
    return null;
  }();
  final prefix = formatEpisodePrimaryLabel(
    episode: episode,
    isArabic: isArabic,
    isFinal: isFinal ||
        hasFinalEpisodeSuffix(resolvedServerName) ||
        hasFinalEpisodeSuffix(title),
    serverName: resolvedServerName,
  );
  if (episode <= 0 && prefix.isEmpty) return serverTitle;
  if (prefix.isEmpty) return serverTitle;
  return serverTitle.isEmpty ? prefix : '$prefix: $serverTitle';
}

/// Characters that break or get rewritten on common mobile filesystems.
final RegExp _illegalDownloadFileChars = RegExp(r'[\\/:*?"<>|]');

/// Sanitize a display label into a stable on-disk filename stem.
String sanitizeDownloadFileName(String name) {
  return name
      .replaceAll(_illegalDownloadFileChars, '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String formatEpisodeFileName({
  required int episode,
  String? title,
  String? quality,
  bool isFinal = false,
  String? serverName,
}) {
  final base = formatEpisodeLabel(
    episode: episode,
    isArabic: true,
    title: title,
    isFinal: isFinal,
    serverName: serverName,
  );
  final normalizedQuality = quality?.trim() ?? '';
  return normalizedQuality.isEmpty ? base : '$base ($normalizedQuality)';
}

/// True when [fileName] is a downloaded episode file for [episode] number.
///
/// Accepts both `حلقة 12` and `حلقة 12 والأخيرة`, with optional creative
/// title and quality suffix, including filenames where `:` became `_`.
bool isDownloadedEpisodeFileName(String fileName, int episode) {
  if (episode <= 0) return false;
  final stem = sanitizeDownloadFileName(
    fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName,
  );
  final prefix = 'حلقة $episode';
  if (stem == prefix) return true;
  if (!stem.startsWith(prefix)) return false;
  final rest = stem.substring(prefix.length);
  return rest.startsWith(' ') ||
      rest.startsWith(':') ||
      rest.startsWith('_') ||
      rest.startsWith('(');
}

/// Title persisted in watch history / sync. Keeps a final-episode marker when
/// there is no creative title so "والأخيرة" survives round-trips.
String episodeTitleForStorage({
  required int episode,
  String? title,
  bool isFinal = false,
  String? serverName,
}) {
  final real = realEpisodeTitle(title);
  if (real.isNotEmpty) return real;
  final primary = formatEpisodePrimaryLabel(
    episode: episode,
    isArabic: true,
    isFinal: isFinal,
    serverName: serverName,
  );
  if (isStandaloneEpisodeLabel(primary) || hasFinalEpisodeSuffix(primary)) {
    return primary;
  }
  return '';
}

/// Primary label for continue-watching / history cards.
///
/// Prefer [episodeServerName] from AnimeWitcher. Fall back to markers that were
/// previously stored in [episodeTitle], otherwise build "حلقة N".
String continueWatchingPrimaryLabel({
  required int? episode,
  required bool isArabic,
  String? episodeTitle,
  String? episodeServerName,
}) {
  final number = episode ?? 0;
  final server = (episodeServerName ?? '').trim();
  if (server.isNotEmpty) {
    return formatEpisodePrimaryLabel(
      episode: number,
      isArabic: isArabic,
      serverName: server,
      isFinal: hasFinalEpisodeSuffix(server),
    );
  }

  final stored = (episodeTitle ?? '').trim();
  if (stored.isNotEmpty &&
      (isGenericEpisodeTitle(stored) ||
          isStandaloneEpisodeLabel(stored) ||
          hasFinalEpisodeSuffix(stored))) {
    return formatEpisodePrimaryLabel(
      episode: number,
      isArabic: isArabic,
      serverName: stored,
      isFinal: hasFinalEpisodeSuffix(stored),
    );
  }

  if (number > 0) {
    return formatEpisodeNumberLabel(episode: number, isArabic: isArabic);
  }
  return '';
}

/// Secondary creative title for continue-watching / history cards.
String continueWatchingSecondaryTitle({
  String? episodeTitle,
  String? episodeServerName,
}) {
  final stored = (episodeTitle ?? '').trim();
  if (stored.isEmpty) return '';
  if (isGenericEpisodeTitle(stored) || isStandaloneEpisodeLabel(stored)) {
    return '';
  }
  final server = (episodeServerName ?? '').trim();
  if (server.isNotEmpty && stored == server) return '';
  return realEpisodeTitle(stored);
}
