import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/player/presentation/episode_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

Episode _episode(int number, {bool filler = false}) => Episode(
  name: 'الحلقة $number',
  url: 'https://example.test/ep/$number',
  season: 1,
  episode: number,
  serverName: 'الحلقة $number',
  isFiller: filler,
);

void main() {
  group('skipping filler', () {
    final episodes = <Episode>[
      _episode(1),
      _episode(2, filler: true),
      _episode(3, filler: true),
      _episode(4),
      _episode(5, filler: true),
    ];

    Episode? nextStory(int from) => nextStoryEpisode(
      episodes: episodes,
      currentEpisode: episodes[from - 1],
      currentEpisodeUrl: episodes[from - 1].url,
    );

    test('walks past a run of filler', () {
      expect(nextStory(1)?.episode, 4);
    });

    test('takes the next episode when it already carries story', () {
      expect(nextStory(3)?.episode, 4);
    });

    test('is null when only filler remains', () {
      // The caller falls back to the plain next episode rather than
      // refusing to continue.
      expect(nextStory(4), isNull);
    });

    test('is null at the end of the list', () {
      expect(nextStory(5), isNull);
    });
  });
}
