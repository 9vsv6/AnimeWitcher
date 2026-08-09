import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/features/details/presentation/details_item_merge.dart';

void main() {
  group('mergeDetailsItem', () {
    test('keeps card artwork when a sparse details response has none', () {
      final card = MultimediaItem(
        title: 'Movie',
        url: 'anime://movie',
        posterUrl: 'https://images.example/poster.jpg',
        bannerUrl: 'https://images.example/banner.jpg',
      );
      final details = MultimediaItem(
        title: 'Movie',
        url: card.url,
        posterUrl: '',
      );

      final result = mergeDetailsItem(fallback: card, incoming: details);

      expect(result.posterUrl, card.posterUrl);
      expect(result.bannerUrl, card.bannerUrl);
    });

    test('uses one episode thumbnail when all title artwork is missing', () {
      final item = MultimediaItem(
        title: 'One episode title',
        url: 'anime://one-episode',
        posterUrl: '',
      );
      final episode = Episode(
        name: 'Episode 1',
        url: 'episode://1',
        episode: 1,
        posterUrl: 'https://images.example/episode.jpg',
      );

      final result = mergeDetailsItem(
        fallback: item,
        incoming: item,
        episodes: <Episode>[episode],
      );

      expect(result.posterUrl, episode.posterUrl);
      expect(result.bannerUrl, episode.posterUrl);
    });

    test('prefers complete details artwork over the opening card', () {
      final card = MultimediaItem(
        title: 'Title',
        url: 'anime://title',
        posterUrl: 'https://images.example/card.jpg',
      );
      final details = MultimediaItem(
        title: 'Title',
        url: card.url,
        posterUrl: 'https://images.example/details.jpg',
        bannerUrl: 'https://images.example/details-banner.jpg',
      );

      final result = mergeDetailsItem(fallback: card, incoming: details);

      expect(result.posterUrl, details.posterUrl);
      expect(result.bannerUrl, details.bannerUrl);
    });

    test('ignores serialized null artwork values', () {
      final card = MultimediaItem(
        title: 'Title',
        url: 'anime://title',
        posterUrl: 'https://images.example/card.jpg',
      );
      final details = MultimediaItem(
        title: 'Title',
        url: card.url,
        posterUrl: 'null',
        bannerUrl: 'undefined',
      );

      final result = mergeDetailsItem(fallback: card, incoming: details);

      expect(result.posterUrl, card.posterUrl);
      expect(result.bannerUrl, card.posterUrl);
    });
  });
}
