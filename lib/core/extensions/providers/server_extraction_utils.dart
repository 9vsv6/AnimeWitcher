// Pure helpers for AnimeWitcher-style server URL extraction.
//
// These mirror the production path in `animewitcher_native_provider.dart`
// (`_extractAnimeWitcherGenericServer` / `_normalizePageEscapes`) as
// dependency-free functions so the fragile part of stream-link acquisition —
// cutting a media URL out of a server page — can be unit-tested against
// fixtures instead of live pages. See
// docs/stream-links-and-player-audit.md finding A4.

/// Removes the escaped-HTML/JavaScript wrappers pages serialize markers
/// through: JS unicode and string escapes first, then HTML entities (named
/// plus numeric/hex) for the characters URLs actually contain (`/ : & " '`).
String normalizePageEscapes(String input) {
  if (input.isEmpty) return input;
  var out = input.replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  out = out
      .replaceAll(r'\/', '/')
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'");
  if (out.contains('&')) {
    out = out.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);|&#(\d+);'),
      (m) {
        final hex = m.group(1);
        final dec = m.group(2);
        final code = hex != null ? int.parse(hex, radix: 16) : int.parse(dec!);
        return String.fromCharCode(code);
      },
    );
    out = out
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
  return out;
}

/// AnimeWitcher's original generic `loadServer` extraction: keep the first
/// occurrence of [start], cut at the next [end], remove the marker text
/// itself, and trim surrounding whitespace. Returns '' when either marker is
/// missing or the inputs are empty.
String extractBetweenMarkers(String input, String start, String end) {
  if (input.isEmpty || start.isEmpty || end.isEmpty) return '';
  final startIndex = input.indexOf(start);
  if (startIndex < 0) return '';
  final fromStart = input.substring(startIndex);
  final endIndex = fromStart.indexOf(end);
  if (endIndex < 0) return '';
  return fromStart
      .substring(0, endIndex)
      .replaceAll(start, '')
      .replaceAll(end, '')
      .trim();
}

/// Marker extraction with one normalized retry: when the direct cut comes up
/// empty, the body and both markers are passed through [normalizePageEscapes]
/// and tried again. Returns '' when even the normalized pass fails, matching
/// the provider's "no wasted work when nothing changed" short-circuit.
String extractServerUrlWithRetry({
  required String body,
  required String start,
  required String end,
}) {
  final direct = extractBetweenMarkers(body, start, end);
  if (direct.isNotEmpty) return direct;

  final normalizedBody = normalizePageEscapes(body);
  final normalizedStart = normalizePageEscapes(start);
  final normalizedEnd = normalizePageEscapes(end);
  if (normalizedBody == body &&
      normalizedStart == start &&
      normalizedEnd == end) {
    return '';
  }
  return extractBetweenMarkers(normalizedBody, normalizedStart, normalizedEnd);
}

/// Cheap sanity check that an extracted value is actually a playable http(s)
/// URL before handing it to the player. Guards against markers drifting onto
/// non-URL payloads (HTML fragments, base64 blobs, relative paths).
bool looksLikeStreamUrl(String value) {
  final v = value.trim();
  if (v.length < 8) return false;
  final uri = Uri.tryParse(v);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}
