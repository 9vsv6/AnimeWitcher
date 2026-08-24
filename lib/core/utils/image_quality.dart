/// Rewrites artwork URLs to the largest variant of the same picture.
///
/// AnimeWitcher stores several sizes per title and its documents point at image
/// CDNs that publish every size under the same file name (AniList covers,
/// MyAnimeList artwork, TMDB stills). Requesting the biggest variant keeps
/// posters sharp on every surface — search, home rows, details, library — and
/// [fallbackQualityImageUrl] steps back down for the rare asset whose large
/// variant is missing.
library;

const Set<String> _aniListCoverSizes = <String>{
  'small',
  'medium',
  'large',
  'extralarge',
};

const String _aniListLargestCover = 'extraLarge';

/// Largest known variant of [url], or [url] itself when its host is unknown.
String highestQualityImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.pathSegments.isEmpty) return trimmed;

  final host = uri.host.toLowerCase();
  if (host.endsWith('anilist.co')) {
    return _replaceAniListCoverSize(uri, _aniListLargestCover) ?? trimmed;
  }
  if (host.endsWith('myanimelist.net')) {
    return _replaceMyAnimeListSuffix(uri, 'l') ?? trimmed;
  }
  if (host.endsWith('tmdb.org')) {
    return _replaceTmdbSize(uri, 'original') ?? trimmed;
  }
  return trimmed;
}

/// Smaller variant to retry with when [url] fails to load, or null when there
/// is no known alternative.
String? fallbackQualityImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.pathSegments.isEmpty) return null;

  final host = uri.host.toLowerCase();
  String? fallback;
  if (host.endsWith('anilist.co')) {
    fallback = _replaceAniListCoverSize(uri, 'large');
  } else if (host.endsWith('myanimelist.net')) {
    fallback = _replaceMyAnimeListSuffix(uri, '');
  } else if (host.endsWith('tmdb.org')) {
    fallback = _replaceTmdbSize(uri, 'w780');
  }
  return fallback == trimmed ? null : fallback;
}

/// `…/media/anime/cover/{size}/bx1-abc.jpg` — every size shares the file name.
String? _replaceAniListCoverSize(Uri uri, String size) {
  final segments = List<String>.of(uri.pathSegments);
  final coverIndex = segments.indexOf('cover');
  if (coverIndex < 0 || coverIndex + 1 >= segments.length) return null;
  if (!_aniListCoverSizes.contains(segments[coverIndex + 1].toLowerCase())) {
    return null;
  }
  segments[coverIndex + 1] = size;
  return uri.replace(pathSegments: segments).toString();
}

/// `…/images/anime/13/17405.jpg`, where `17405t.jpg` is the thumbnail and
/// `17405l.jpg` the large version of the same artwork.
String? _replaceMyAnimeListSuffix(Uri uri, String suffix) {
  final segments = List<String>.of(uri.pathSegments);
  final fileName = segments.last;
  final match = RegExp(
    r'^(\d+)([a-z])?\.(jpg|jpeg|png|webp)$',
    caseSensitive: false,
  ).firstMatch(fileName);
  if (match == null) return null;
  segments[segments.length - 1] =
      '${match.group(1)}$suffix.${match.group(3)}';
  return uri.replace(pathSegments: segments).toString();
}

/// `…/t/p/{w500|h632|original}/abc.jpg`.
String? _replaceTmdbSize(Uri uri, String size) {
  final segments = List<String>.of(uri.pathSegments);
  final sizeIndex = segments.indexWhere(
    (segment) =>
        segment == 'original' ||
        RegExp(r'^[wh]\d+$', caseSensitive: false).hasMatch(segment),
  );
  if (sizeIndex < 0) return null;
  segments[sizeIndex] = size;
  return uri.replace(pathSegments: segments).toString();
}
