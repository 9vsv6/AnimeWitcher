/// Returns the exact MediaFire share-page URL that should be requested.
///
/// In particular, `/file_premium/` must not be rewritten to `/file/`: MF2 in
/// AnimeWitcher uses premium share links whose download token is exposed only
/// by the premium page.
///
/// MediaFire's public pages are HTTPS. Canonicalizing the ordinary MediaFire
/// host here avoids paying for an HTTP -> HTTPS and/or apex -> www redirect
/// before the resolver can read `downloadButton` / `data-scrambled-url`.
String mediaFirePageRequestUrl(String rawUrl) {
  var value = rawUrl.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('//')) {
    value = 'https:$value';
  } else if (value.startsWith('/')) {
    value = 'https://www.mediafire.com$value';
  } else if (!value.contains('://')) {
    value = 'https://$value';
  }

  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final host = uri.host.toLowerCase();
  if (host == 'mediafire.com' || host == 'www.mediafire.com') {
    return uri.replace(scheme: 'https', host: 'www.mediafire.com').toString();
  }
  return value;
}
