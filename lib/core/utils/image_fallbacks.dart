/// Utility for normalizing image URLs.
///
/// Returns `null` when an image is missing so callers can use their local
/// placeholder widgets instead of fetching a network placeholder.
class AppImageFallbacks {
  static String? poster(String? imageUrl, {String? label}) =>
      _normalize(imageUrl);

  static String? optional(String? imageUrl) => _normalize(imageUrl);

  /// Resolves the artwork used for wide backdrops.
  ///
  /// Providers are allowed to omit a banner, in which case the poster is the
  /// canonical fallback used throughout the app.
  static String? banner({
    String? bannerUrl,
    String? posterUrl,
    String? label,
  }) =>
      optional(bannerUrl) ?? poster(posterUrl, label: label);

  /// Resolves episode artwork using the shared fallback order:
  /// episode image -> anime banner -> anime poster.
  static String? episode({
    String? episodeUrl,
    String? bannerUrl,
    String? posterUrl,
    String? label,
  }) =>
      optional(episodeUrl) ??
      banner(bannerUrl: bannerUrl, posterUrl: posterUrl, label: label);

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    // Some provider documents contain serialized empty values. Treating one
    // as a URL makes image widgets enter their error placeholder instead of
    // continuing through the normal banner/poster fallback chain.
    final normalized = trimmed.toLowerCase();
    if (normalized == 'null' ||
        normalized == 'undefined' ||
        normalized == 'none' ||
        normalized == 'n/a' ||
        normalized == 'about:blank') {
      return null;
    }

    return trimmed;
  }
}
