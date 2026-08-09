class AnimeWitcherSyncIds {
  const AnimeWitcherSyncIds._();

  static String? animeIdFromUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 'animewitcher.com' && host != 'www.animewitcher.com') {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first.toLowerCase() != 'watch') {
      return null;
    }
    final encoded = segments[1].trim();
    if (encoded.isEmpty) return null;
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return encoded;
    }
  }

  static String? episodeIdFromUrl(String rawUrl) {
    final parts = rawUrl.trim().split('|');
    if (parts.length < 2) return null;
    final encoded = parts.sublist(1).join('|').trim();
    if (encoded.isEmpty) return null;
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return encoded;
    }
  }

  static String mainUrl(String animeId) =>
      'https://animewitcher.com/watch/${Uri.encodeComponent(animeId)}';

  static String episodeUrl(String animeId, String episodeId) =>
      '${Uri.encodeComponent(animeId)}|${Uri.encodeComponent(episodeId)}';
}
