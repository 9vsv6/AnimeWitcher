import 'package:html_unescape/html_unescape.dart';

/// Shared AnimeWitcher page-decoding helpers.
///
/// These are the same steps `_extractAnimeWitcherGenericServer` used inline:
/// HTML unescape, JS unicode/`\xNN`/`\/` decoding, then marker cuts. Keeping
/// them here means the provider and the tests cannot drift apart.
final HtmlUnescape _pageUnescape = HtmlUnescape();

/// Removes the escaped-HTML/JavaScript wrappers pages serialize markers
/// through. Matches production, plus leftover `\uXXXX` / `\xNN` sequences
/// that the older hardcoded list missed.
String normalizePageEscapes(String input) {
  if (input.isEmpty) return input;
  var text = _pageUnescape.convert(input);
  text = text
      .replaceAll(r'\u003a', ':')
      .replaceAll(r'\u003A', ':')
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u003d', '=')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\x3a', ':')
      .replaceAll(r'\x3A', ':')
      .replaceAll(r'\x26', '&')
      .replaceAll(r'\x3d', '=')
      .replaceAll(r'\x3D', '=')
      .replaceAll(r'\x2f', '/')
      .replaceAll(r'\x2F', '/')
      .replaceAll(r'\/', '/')
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'");
  text = text.replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  text = text.replaceAllMapped(
    RegExp(r'\\x([0-9a-fA-F]{2})'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  return text;
}

/// Post-cut cleanup: decode leftovers and drop broken `amp;` fragments.
String cleanServerExtract(String value) {
  return normalizePageEscapes(
    value,
  ).replaceAll('amp;', '').replaceAll('&amp;', '&').trim();
}

/// Classic `indexOf(start) + start.length` … `indexOf(end)` slice.
String extractBetweenWords(String input, String start, String end) {
  if (input.isEmpty || start.isEmpty || end.isEmpty) return '';
  final startIndex = input.indexOf(start);
  if (startIndex < 0) return '';
  final valueStart = startIndex + start.length;
  final endIndex = input.indexOf(end, valueStart);
  if (endIndex < 0 || endIndex < valueStart) return '';
  return input.substring(valueStart, endIndex).trim();
}

/// AnimeWitcher's generic `loadServer` cut: keep the first [start] in the
/// slice, cut at the next [end], then strip the marker text itself.
String extractBetweenMarkers(String input, String start, String end) {
  if (input.isEmpty || start.isEmpty || end.isEmpty) return '';
  final startIndex = input.indexOf(start);
  if (startIndex < 0) return '';
  final fromStart = input.substring(startIndex);
  final endIndex = fromStart.indexOf(end);
  if (endIndex < 0) return '';
  final beforeEnd = fromStart.substring(0, endIndex);
  return cleanServerExtract(
    beforeEnd.replaceAll(start, '').replaceAll(end, ''),
  );
}

/// Marker extraction with one normalized retry. Body *and* markers are
/// decoded on the second pass, matching the provider short-circuit when
/// unescape would not change anything.
String extractGenericServer(String input, String start, String end) {
  final direct = extractBetweenMarkers(input, start, end);
  if (direct.isNotEmpty) return direct;

  final normalizedInput = normalizePageEscapes(input);
  final normalizedStart = normalizePageEscapes(start);
  final normalizedEnd = normalizePageEscapes(end);
  if (normalizedInput == input &&
      normalizedStart == start &&
      normalizedEnd == end) {
    return '';
  }
  return extractBetweenMarkers(normalizedInput, normalizedStart, normalizedEnd);
}

/// Backward-compatible name used by the original audit tests.
String extractServerUrlWithRetry({
  required String body,
  required String start,
  required String end,
}) => extractGenericServer(body, start, end);

/// Prefix `//host/...` and strip wrapping quotes after a marker cut.
String prepareExtractedMediaUrl(String raw) {
  var value = cleanServerExtract(
    raw,
  ).replaceAll(RegExp(r'''^[\s"'`]+|[\s"'`]+$'''), '');
  if (value.startsWith('//')) value = 'https:$value';
  return value.trim();
}

/// Cheap sanity check that an extracted value is a playable http(s) URL.
bool looksLikeStreamUrl(String value) {
  final v = value.trim();
  if (v.length < 8) return false;
  final uri = Uri.tryParse(v);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}
