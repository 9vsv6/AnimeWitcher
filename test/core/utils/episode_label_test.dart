import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/utils/episode_label.dart';

void main() {
  test('formats Arabic episode with title', () {
    expect(formatEpisodeLabel(episode: 2, isArabic: true, title: 'بداية جديدة'), 'حلقة 2: بداية جديدة');
  });
  test('omits generic title', () {
    expect(formatEpisodeLabel(episode: 2, isArabic: true, title: 'الحلقة 2'), 'حلقة 2');
  });
  test('adds quality only when present', () {
    expect(formatEpisodeFileName(episode: 2, title: 'بداية جديدة', quality: '1080p'), 'حلقة 2: بداية جديدة (1080p)');
    expect(formatEpisodeFileName(episode: 2, title: 'بداية جديدة'), 'حلقة 2: بداية جديدة');
  });
}
