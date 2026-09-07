import '../../../core/domain/entity/multimedia_item.dart';

/// Returns the episode directly before or after the active episode.
///
/// The sequence preserves the provider order and, when the active episode has
/// a subtitle/dub variant, stays within that same variant. This matches the
/// existing next-episode behavior while making both list boundaries explicit.
Episode? adjacentEpisode({
  required List<Episode>? episodes,
  required Episode? currentEpisode,
  required String currentEpisodeUrl,
  required int offset,
}) {
  if (episodes == null || episodes.isEmpty || offset == 0) return null;

  final sequence =
      currentEpisode != null && currentEpisode.dubStatus != DubStatus.none
      ? episodes
            .where((episode) => episode.dubStatus == currentEpisode.dubStatus)
            .toList(growable: false)
      : episodes;
  final currentUrl = currentEpisode?.url ?? currentEpisodeUrl;
  if (currentUrl.isEmpty) return null;
  final currentIndex = sequence.indexWhere(
    (episode) => episode.url == currentUrl,
  );
  final adjacentIndex = currentIndex + offset;
  if (currentIndex < 0 ||
      adjacentIndex < 0 ||
      adjacentIndex >= sequence.length) {
    return null;
  }
  return sequence[adjacentIndex];
}

/// The next episode that carries story, skipping any the provider marked
/// filler.
///
/// Returns null when everything after the current episode is filler — there
/// is nothing to jump to, so the caller should fall back to the plain next
/// episode rather than refusing to continue.
Episode? nextStoryEpisode({
  required List<Episode>? episodes,
  required Episode? currentEpisode,
  required String currentEpisodeUrl,
}) {
  for (var offset = 1; ; offset++) {
    final candidate = adjacentEpisode(
      episodes: episodes,
      currentEpisode: currentEpisode,
      currentEpisodeUrl: currentEpisodeUrl,
      offset: offset,
    );
    if (candidate == null) return null;
    if (!candidate.isFiller) return candidate;
  }
}
