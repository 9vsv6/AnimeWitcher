import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/utils/safe_uri.dart';

void main() {
  group('safe URI helpers', () {
    test('preserves raw Unicode and literal percent signs', () {
      expect(safeDecodeUriComponent('Ω'), 'Ω');
      expect(safeDecodeUriComponent('100%'), '100%');
      expect(safeDecodeUriComponent('broken%zzname'), 'broken%zzname');
      expect(safeEncodeUriComponent('literal%20name'), 'literal%2520name');
    });

    test('decodes valid percent encoding exactly once', () {
      expect(safeDecodeUriComponent('%CE%A9'), 'Ω');
      expect(safeDecodeUriComponent('%25'), '%');
    });

    test('repairs malformed percent encoding before parsing', () {
      final uri = safeTryParseUri('https://animewitcher.com/watch/100%zzbad');
      expect(uri, isNotNull);
      expect(uri!.pathSegments.last, '100%zzbad');
    });

    test('encodes arbitrary provider IDs into one safe path segment', () {
      const value = 'أنمي Ω 100% %zz / ? # | 😀';
      final encoded = safeEncodeUriComponent(value);
      expect(() => Uri.parse('https://example.com/$encoded'), returnsNormally);
      expect(safeDecodeUriComponent(encoded), value);
    });
  });
}
