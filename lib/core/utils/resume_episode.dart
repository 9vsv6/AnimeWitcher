import '../domain/entity/multimedia_item.dart';

/// Picks the continue-watching / autoplay episode from a loaded catalog.
///
/// Prefers an exact [resumeEpisodeUrl] match (the stored episode data URL),
/// then falls back to episode number and optional season. This is the same
/// matching details used to use before opening the server list.
Episode? matchResumeEpisode(
  Iterable<Episode> episodes, {
  String? resumeEpisodeUrl,
  int? resumeEpisodeNumber,
  int? resumeSeason,
}) {
  final resumeUrl = resumeEpisodeUrl?.trim();
  if (resumeUrl != null && resumeUrl.isNotEmpty) {
    for (final episode in episodes) {
      if (episode.url.trim() == resumeUrl) return episode;
    }
  }

  if (resumeEpisodeNumber == null || resumeEpisodeNumber <= 0) return null;

  Episode? numberMatch;
  for (final episode in episodes) {
    if (episode.episode != resumeEpisodeNumber) continue;
    numberMatch ??= episode;
    if (resumeSeason != null &&
        resumeSeason > 0 &&
        episode.season == resumeSeason) {
      return episode;
    }
  }
  return numberMatch;
}
