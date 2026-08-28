import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/utils/image_fallbacks.dart';

/// Combines a newly fetched details item with the card that opened the page.
///
/// AnimeWitcher occasionally returns a sparse details document for movies and
/// one-episode titles. In that case the search/home card can contain better
/// artwork than the details response. Never replace usable card artwork with
/// an empty value, and use the single episode thumbnail as a final fallback.
MultimediaItem mergeDetailsItem({
  required MultimediaItem fallback,
  required MultimediaItem incoming,
  List<Episode>? episodes,
}) {
  final resolvedEpisodes = episodes ?? incoming.episodes ?? fallback.episodes;
  String? episodeArtwork;
  for (final episode in resolvedEpisodes ?? const <Episode>[]) {
    episodeArtwork = AppImageFallbacks.optional(episode.posterUrl);
    if (episodeArtwork != null) break;
  }

  final incomingPoster = AppImageFallbacks.poster(incoming.posterUrl);
  final fallbackPoster = AppImageFallbacks.poster(fallback.posterUrl);
  final incomingBanner = AppImageFallbacks.optional(incoming.bannerUrl);
  final fallbackBanner = AppImageFallbacks.optional(fallback.bannerUrl);
  final incomingFullPoster = AppImageFallbacks.poster(incoming.fullPosterUrl);
  final fallbackFullPoster = AppImageFallbacks.poster(fallback.fullPosterUrl);

  final poster =
      incomingPoster ??
      fallbackPoster ??
      episodeArtwork ??
      incomingBanner ??
      fallbackBanner ??
      '';
  final banner = incomingBanner ?? fallbackBanner ?? poster;
  final fullPoster =
      _distinctFullPoster(incomingFullPoster, incomingPoster) ??
      _distinctFullPoster(fallbackFullPoster, fallbackPoster) ??
      incomingFullPoster ??
      fallbackFullPoster ??
      poster;

  final incomingTitle = incoming.title.trim();
  final incomingDescription = incoming.description?.trim();
  final fallbackDescription = fallback.description?.trim();

  return incoming.copyWith(
    title: incomingTitle.isNotEmpty ? incoming.title : fallback.title,
    posterUrl: poster,
    fullPosterUrl: fullPoster,
    bannerUrl: banner,
    logoUrl:
        AppImageFallbacks.optional(incoming.logoUrl) ??
        AppImageFallbacks.optional(fallback.logoUrl) ??
        '',
    description: incomingDescription?.isNotEmpty == true
        ? incoming.description
        : fallbackDescription?.isNotEmpty == true
        ? fallback.description
        : null,
    episodes: resolvedEpisodes,
  );
}

/// A full-size URL only counts when it is actually larger than the catalog
/// poster. Otherwise the opening card's stored large artwork is kept.
String? _distinctFullPoster(String? fullPoster, String? displayPoster) {
  if (fullPoster == null || fullPoster.isEmpty) return null;
  if (displayPoster != null && fullPoster == displayPoster) return null;
  return fullPoster;
}
