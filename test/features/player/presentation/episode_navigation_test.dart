import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/player/presentation/episode_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

Episode _episode(int number, {DubStatus dubStatus = DubStatus.none}) {
  return Episode(
    name: 'Episode $number',
    url: 'https://example.test/episode-$number-$dubStatus',
    episode: number,
    dubStatus: dubStatus,
  );
}

void main() {
  test('returns no previous episode at the beginning of the sequence', () {
    final first = _episode(1);

    expect(
      adjacentEpisode(
        episodes: [first, _episode(2)],
        currentEpisode: first,
        currentEpisodeUrl: first.url,
        offset: -1,
      ),
      isNull,
    );
  });

  test('returns no next episode at the end of the sequence', () {
    final last = _episode(2);

    expect(
      adjacentEpisode(
        episodes: [_episode(1), last],
        currentEpisode: last,
        currentEpisodeUrl: last.url,
        offset: 1,
      ),
      isNull,
    );
  });

  test('returns both neighbors from a middle episode', () {
    final first = _episode(1);
    final middle = _episode(2);
    final last = _episode(3);
    final episodes = [first, middle, last];

    expect(
      adjacentEpisode(
        episodes: episodes,
        currentEpisode: middle,
        currentEpisodeUrl: middle.url,
        offset: -1,
      ),
      same(first),
    );
    expect(
      adjacentEpisode(
        episodes: episodes,
        currentEpisode: middle,
        currentEpisodeUrl: middle.url,
        offset: 1,
      ),
      same(last),
    );
  });

  test('returns no neighbor for a single-episode sequence', () {
    final only = _episode(1);

    expect(
      adjacentEpisode(
        episodes: [only],
        currentEpisode: only,
        currentEpisodeUrl: only.url,
        offset: -1,
      ),
      isNull,
    );
    expect(
      adjacentEpisode(
        episodes: [only],
        currentEpisode: only,
        currentEpisodeUrl: only.url,
        offset: 1,
      ),
      isNull,
    );
  });

  test('resolves the current row from its url when the episode is missing', () {
    final first = _episode(1);
    final second = _episode(2);

    expect(
      adjacentEpisode(
        episodes: [first, second],
        currentEpisode: null,
        currentEpisodeUrl: first.url,
        offset: 1,
      ),
      same(second),
    );
  });

  test('moves only within the active subtitle or dub variant', () {
    final subbedFirst = _episode(1, dubStatus: DubStatus.subbed);
    final dubbedFirst = _episode(1, dubStatus: DubStatus.dubbed);
    final subbedSecond = _episode(2, dubStatus: DubStatus.subbed);
    final dubbedSecond = _episode(2, dubStatus: DubStatus.dubbed);
    final episodes = [subbedFirst, dubbedFirst, subbedSecond, dubbedSecond];

    expect(
      adjacentEpisode(
        episodes: episodes,
        currentEpisode: subbedFirst,
        currentEpisodeUrl: subbedFirst.url,
        offset: 1,
      ),
      same(subbedSecond),
    );
    expect(
      adjacentEpisode(
        episodes: episodes,
        currentEpisode: dubbedSecond,
        currentEpisodeUrl: dubbedSecond.url,
        offset: -1,
      ),
      same(dubbedFirst),
    );
  });
}
