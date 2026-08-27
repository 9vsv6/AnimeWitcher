import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/source_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sourcePickerHeader', () {
    test('uses the server episode label instead of a generic source prompt', () {
      expect(sourcePickerHeader('الحلقة 10', isArabic: true), 'الحلقة 10');
      expect(sourcePickerHeader('الفيلم', isArabic: true), 'الفيلم');
      expect(sourcePickerHeader('مترجم', isArabic: true), 'مترجم');
    });

    test('keeps the localized generic prompt when no episode is available', () {
      expect(sourcePickerHeader(null, isArabic: true), 'اختر المصدر');
      expect(sourcePickerHeader('  ', isArabic: false), 'Choose source');
    });
  });

  group('episodePickerTitle', () {
    test('uses the primary server label, not the creative title', () {
      expect(
        episodePickerTitle(
          Episode(
            name: 'نهاية الرحلة',
            url: 'https://example.com/ep10',
            episode: 10,
            serverName: 'الحلقة 10',
          ),
        ),
        'الحلقة 10',
      );
      expect(
        episodePickerTitle(
          Episode(
            name: 'مدبلج',
            url: 'https://example.com/movie-dub',
            episode: 0,
            serverName: 'مدبلج',
          ),
        ),
        'مدبلج',
      );
    });

    test('returns null when there is no episode identity', () {
      expect(episodePickerTitle(null), isNull);
      expect(
        episodePickerTitle(
          Episode(name: '', url: 'https://example.com/unknown', episode: 0),
        ),
        isNull,
      );
    });
  });
}
