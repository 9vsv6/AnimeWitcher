import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/utils/episode_label.dart';

void main() {
  group('isGenericEpisodeTitle', () {
    test('detects Arabic placeholders', () {
      expect(isGenericEpisodeTitle('الحلقة 16'), isTrue);
      expect(isGenericEpisodeTitle('حلقة 16'), isTrue);
      expect(isGenericEpisodeTitle('الحلقة 12 والأخيرة'), isTrue);
      expect(isGenericEpisodeTitle('حلقة 12 والاخيرة'), isTrue);
    });

    test('detects English placeholders', () {
      expect(isGenericEpisodeTitle('Episode 3'), isTrue);
      expect(isGenericEpisodeTitle('Ep. 3'), isTrue);
      expect(isGenericEpisodeTitle('Episode 3 Final'), isTrue);
    });

    test('keeps creative titles', () {
      expect(isGenericEpisodeTitle('رفقاء جدد'), isFalse);
      expect(isGenericEpisodeTitle('بداية جديدة'), isFalse);
    });
  });

  group('hasFinalEpisodeSuffix', () {
    test('detects Arabic and English final markers', () {
      expect(hasFinalEpisodeSuffix('الحلقة 12 والأخيرة'), isTrue);
      expect(hasFinalEpisodeSuffix('حلقة 12 والاخيرة'), isTrue);
      expect(hasFinalEpisodeSuffix('Episode 12 (Final)'), isTrue);
      expect(hasFinalEpisodeSuffix('الحلقة 11'), isFalse);
      expect(hasFinalEpisodeSuffix('رفقاء جدد'), isFalse);
    });
  });

  group('realEpisodeTitle', () {
    test('returns empty for missing or generic titles', () {
      expect(realEpisodeTitle(null), '');
      expect(realEpisodeTitle(''), '');
      expect(realEpisodeTitle('الحلقة 16'), '');
      expect(realEpisodeTitle('الحلقة 12 والأخيرة'), '');
    });

    test('keeps creative titles', () {
      expect(realEpisodeTitle('رفقاء جدد'), 'رفقاء جدد');
    });
  });

  group('formatEpisodeNumberLabel', () {
    test('formats Arabic number and final suffix', () {
      expect(
        formatEpisodeNumberLabel(episode: 12, isArabic: true),
        'حلقة 12',
      );
      expect(
        formatEpisodeNumberLabel(episode: 12, isArabic: true, isFinal: true),
        'حلقة 12 والأخيرة',
      );
      expect(
        formatEpisodeNumberLabel(
          episode: 12,
          isArabic: true,
          rawName: 'الحلقة 12 والأخيرة',
        ),
        'حلقة 12 والأخيرة',
      );
    });

    test('formats English number and final suffix', () {
      expect(
        formatEpisodeNumberLabel(episode: 12, isArabic: false),
        'Episode 12',
      );
      expect(
        formatEpisodeNumberLabel(episode: 12, isArabic: false, isFinal: true),
        'Episode 12 (Final)',
      );
    });
  });

  group('formatEpisodeLabel', () {
    test('formats Arabic episode with title', () {
      expect(
        formatEpisodeLabel(episode: 2, isArabic: true, title: 'بداية جديدة'),
        'حلقة 2: بداية جديدة',
      );
    });

    test('omits generic title', () {
      expect(
        formatEpisodeLabel(episode: 2, isArabic: true, title: 'الحلقة 2'),
        'حلقة 2',
      );
      expect(
        formatEpisodeLabel(
          episode: 12,
          isArabic: true,
          title: 'الحلقة 12 والأخيرة',
        ),
        'حلقة 12 والأخيرة',
      );
    });

    test('keeps final marker with creative title', () {
      expect(
        formatEpisodeLabel(
          episode: 12,
          isArabic: true,
          title: 'نهاية الرحلة',
          isFinal: true,
        ),
        'حلقة 12 والأخيرة: نهاية الرحلة',
      );
    });

    test('adds quality only when present', () {
      expect(
        formatEpisodeFileName(
          episode: 2,
          title: 'بداية جديدة',
          quality: '1080p',
        ),
        'حلقة 2: بداية جديدة (1080p)',
      );
      expect(
        formatEpisodeFileName(episode: 2, title: 'بداية جديدة'),
        'حلقة 2: بداية جديدة',
      );
    });
  });

  group('episodeTitleForStorage', () {
    test('stores creative titles as-is', () {
      expect(
        episodeTitleForStorage(episode: 13, title: 'رفقاء جدد'),
        'رفقاء جدد',
      );
    });

    test('stores final marker when title is generic', () {
      expect(
        episodeTitleForStorage(
          episode: 12,
          title: 'الحلقة 12 والأخيرة',
          isFinal: true,
        ),
        'حلقة 12 والأخيرة',
      );
      expect(
        episodeTitleForStorage(episode: 11, title: 'الحلقة 11'),
        '',
      );
    });
  });
}
