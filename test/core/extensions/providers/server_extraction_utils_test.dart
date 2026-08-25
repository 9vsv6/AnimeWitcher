import 'package:flutter_test/flutter_test.dart';

import 'package:animewitcher/core/extensions/providers/server_extraction_utils.dart';

void main() {
  group('normalizePageEscapes', () {
    test('leaves plain text untouched', () {
      expect(
        normalizePageEscapes('https://cdn.example.com/v/a.mp4'),
        'https://cdn.example.com/v/a.mp4',
      );
    });

    test('decodes JS string escapes', () {
      expect(
        normalizePageEscapes(r'https:\/\/cdn.example.com\/v\/a.m3u8'),
        'https://cdn.example.com/v/a.m3u8',
      );
    });

    test('decodes JS unicode escapes used on AnimeWitcher pages', () {
      expect(
        normalizePageEscapes(r'https\u003A\u002F\u002Fex.com/v.mp4'),
        'https://ex.com/v.mp4',
      );
    });

    test('decodes leftover generic unicode and hex escapes', () {
      expect(normalizePageEscapes(r'\u0041'), 'A');
      expect(normalizePageEscapes(r'\x3d'), '=');
    });

    test('decodes named HTML entities', () {
      expect(normalizePageEscapes('a&amp;b'), 'a&b');
      expect(normalizePageEscapes('&quot;q&quot;'), '"q"');
    });
  });

  group('cleanServerExtract', () {
    test('drops leftover amp; fragments after unescape', () {
      expect(
        cleanServerExtract('https://x/v.mp4?a=1&amp;b=2'),
        'https://x/v.mp4?a=1&b=2',
      );
    });
  });

  group('extractBetweenMarkers', () {
    const start = 'file":"';
    const end = '","q"';

    test('cuts between the first markers and removes the marker text', () {
      const body =
          '{"ok":true,"file":"https://cdn.x/hls/master.m3u8",'
          '"q":720,"t":9}';
      expect(
        extractBetweenMarkers(body, start, end),
        'https://cdn.x/hls/master.m3u8',
      );
    });

    test('returns empty when the end marker is missing', () {
      expect(
        extractBetweenMarkers('{"file":"https://x/v.mp4"}', start, end),
        '',
      );
    });

    test('returns empty when the start marker is missing', () {
      expect(extractBetweenMarkers('{"q":720}', start, end), '');
    });
  });

  group('extractBetweenWords', () {
    test('slices after the start marker', () {
      expect(
        extractBetweenWords('aaSTARThttps://x/v.mp4END', 'START', 'END'),
        'https://x/v.mp4',
      );
    });
  });

  group('extractGenericServer', () {
    const start = 'file":"';
    const end = '","q"';

    test('extracts directly when the page is not escaped', () {
      const body = '{"file":"https://x/v.mp4","q":720}';
      expect(extractGenericServer(body, start, end), 'https://x/v.mp4');
    });

    test('retries with normalization on escaped pages', () {
      const body = r'{"file"\u003A"https:\/\/x\/v.mp4","q":720}';
      expect(extractGenericServer(body, start, end), 'https://x/v.mp4');
      expect(
        extractServerUrlWithRetry(body: body, start: start, end: end),
        'https://x/v.mp4',
      );
    });

    test('short-circuits when nothing changed and no markers matched', () {
      expect(
        extractGenericServer('plain page without markers', start, end),
        '',
      );
    });
  });

  group('prepareExtractedMediaUrl', () {
    test('prefixes protocol-relative URLs', () {
      expect(prepareExtractedMediaUrl('//cdn.x/v.mp4'), 'https://cdn.x/v.mp4');
    });

    test('strips wrapping quotes', () {
      expect(
        prepareExtractedMediaUrl('"https://cdn.x/v.mp4"'),
        'https://cdn.x/v.mp4',
      );
    });
  });

  group('looksLikeStreamUrl', () {
    test('accepts http(s) URLs', () {
      expect(looksLikeStreamUrl('https://cdn.x/v/master.m3u8'), isTrue);
      expect(looksLikeStreamUrl('http://x.com/a.mp4'), isTrue);
      expect(looksLikeStreamUrl('  https://padded.x/v.mkv  '), isTrue);
    });

    test('rejects non-http schemes, relatives, and junk', () {
      expect(looksLikeStreamUrl('ftp://x.com/f'), isFalse);
      expect(looksLikeStreamUrl('/relative/path.mp4'), isFalse);
      expect(looksLikeStreamUrl('<div>oops</div>'), isFalse);
      expect(looksLikeStreamUrl(''), isFalse);
      expect(looksLikeStreamUrl('https://'), isFalse);
    });
  });
}
