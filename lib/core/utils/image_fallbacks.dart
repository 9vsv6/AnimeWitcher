/// Utility for normalizing image URLs.
///
/// Returns `null` when an image is missing so callers can use their local
/// placeholder widgets instead of fetching a network placeholder.
class AppImageFallbacks {
  static String? poster(String? imageUrl, {String? label}) =>
      _normalize(imageUrl);

  static String? optional(String? imageUrl) => _normalize(imageUrl);

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
