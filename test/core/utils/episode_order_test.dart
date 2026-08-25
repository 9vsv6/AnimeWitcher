import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/utils/episode_order.dart';

Episode _episode(int number) => Episode(
  name: '',
  url: 'anime|ep$number',
  season: 1,
  episode: number,
  serverName: 'الحلقة $number',
);

void main() {
  group('episodesInDisplayOrder', () {
    final serverOrder = [_episode(1), _episode(2), _episode(3)];

    test('keeps the server order when ascending', () {
      expect(
        episodesInDisplayOrder(serverOrder, ascending: true)
            .map((e) => e.episode),
        [1, 2, 3],
      );
    });

    test('only flips the server order when descending', () {
      expect(
        episodesInDisplayOrder(serverOrder, ascending: false)
            .map((e) => e.episode),
        [3, 2, 1],
      );
    });

    test('does not reorder unnumbered rows by number', () {
      final withSpecial = [
        _episode(1),
        Episode(
          name: '',
          url: 'anime|special',
          season: 1,
          episode: 0,
          serverName: 'الحلقة الخاصة',
        ),
        _episode(2),
      ];
      expect(
        episodesInDisplayOrder(withSpecial, ascending: true)
            .map((e) => e.serverName),
        ['الحلقة 1', 'الحلقة الخاصة', 'الحلقة 2'],
      );
    });

    test('never mutates the source list', () {
      final source = [_episode(1), _episode(2)];
      episodesInDisplayOrder(source, ascending: false);
      expect(source.map((e) => e.episode), [1, 2]);
    });
  });
}
