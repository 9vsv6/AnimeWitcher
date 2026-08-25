import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';

void main() {
  group('Episode filler metadata', () {
    test('accepts provider filler field aliases', () {
      final payloads = <Map<String, dynamic>>[
        {'filler': true},
        {'isFiller': '1'},
        {'is_filler': 'filler'},
        {'filler': 'فلر'},
      ];

      for (final payload in payloads) {
        final episode = Episode.fromJson(<String, dynamic>{
          'name': 'Episode 1',
          'url': 'episode-1',
          ...payload,
        });

        expect(episode.isFiller, isTrue);
      }
    });

    test('defaults to false for missing or false filler values', () {
      expect(
        Episode.fromJson(<String, dynamic>{
          'name': 'Episode 1',
          'url': 'episode-1',
        }).isFiller,
        isFalse,
      );
      expect(
        Episode.fromJson(<String, dynamic>{
          'name': 'Episode 1',
          'url': 'episode-1',
          'filler': false,
        }).isFiller,
        isFalse,
      );
    });

    test('preserves filler through JSON round trip', () {
      final episode = Episode(
        name: 'Episode 1',
        url: 'episode-1',
        episode: 1,
        isFiller: true,
      );

      expect(Episode.fromJson(episode.toJson()).isFiller, isTrue);
    });
  });
}
