import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/utils/resume_episode.dart';
import 'package:flutter_test/flutter_test.dart';

Episode _episode({required String url, required int number, int season = 1}) {
  return Episode(
    name: 'Episode $number',
    url: url,
    episode: number,
    season: season,
  );
}

void main() {
  group('matchResumeEpisode', () {
    final episodes = <Episode>[
      _episode(url: 'anime|ep8', number: 8),
      _episode(url: 'anime|ep9', number: 9),
      _episode(url: 'anime|ep9s2', number: 9, season: 2),
    ];

    test('prefers the stored episode data URL over the number', () {
      expect(
        matchResumeEpisode(
          episodes,
          resumeEpisodeUrl: 'anime|ep8',
          resumeEpisodeNumber: 9,
        )?.url,
        'anime|ep8',
      );
    });

    test('matches episode number when the stored URL is missing', () {
      expect(
        matchResumeEpisode(episodes, resumeEpisodeNumber: 9)?.url,
        'anime|ep9',
      );
    });

    test('uses season when several rows share the same number', () {
      expect(
        matchResumeEpisode(
          episodes,
          resumeEpisodeNumber: 9,
          resumeSeason: 2,
        )?.url,
        'anime|ep9s2',
      );
    });

    test('returns null when nothing in the catalog matches', () {
      expect(matchResumeEpisode(episodes, resumeEpisodeNumber: 12), isNull);
    });
  });
}
