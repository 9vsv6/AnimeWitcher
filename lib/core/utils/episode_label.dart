String formatEpisodeLabel({
  required int episode,
  required bool isArabic,
  String? title,
}) {
  final serverTitle = title ?? '';
  if (episode <= 0) return serverTitle;
  final prefix = isArabic ? 'حلقة $episode' : 'Episode $episode';
  return serverTitle.isEmpty ? prefix : '$prefix: $serverTitle';
}

String formatEpisodeFileName({
  required int episode,
  String? title,
  String? quality,
}) {
  final serverTitle = title ?? '';
  final base = episode > 0
      ? (serverTitle.isEmpty ? 'حلقة $episode' : 'حلقة $episode: $serverTitle')
      : serverTitle;
  final normalizedQuality = quality?.trim() ?? '';
  return normalizedQuality.isEmpty ? base : '$base ($normalizedQuality)';
}
