/// URI helpers for provider IDs and app-owned URLs.
///
/// External signed media URLs should not be decoded/re-encoded with these
/// helpers because changing their byte representation can invalidate signatures.
String repairInvalidPercentEncoding(String value) {
  if (!value.contains('%')) return value;
  return value.replaceAllMapped(
    RegExp(r'%(?![0-9A-Fa-f]{2})'),
    (_) => '%25',
  );
}

String safeDecodeUriComponent(String value) {
  if (value.isEmpty) return value;

  final repaired = repairInvalidPercentEncoding(value);
  try {
    return Uri.decodeComponent(repaired);
  } catch (_) {
    return value;
  }
}

String safeEncodeUriComponent(String value) {
  if (value.isEmpty) return value;
  return Uri.encodeComponent(value);
}

String canonicalEncodeUriComponent(String value) {
  if (value.isEmpty) return value;
  return Uri.encodeComponent(safeDecodeUriComponent(value));
}

Uri? safeTryParseUri(String value) {
  final source = value.trim();
  if (source.isEmpty) return null;

  final repaired = repairInvalidPercentEncoding(source);
  try {
    return Uri.tryParse(repaired);
  } catch (_) {
    return null;
  }
}
