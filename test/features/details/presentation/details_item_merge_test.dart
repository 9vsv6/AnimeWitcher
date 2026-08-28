import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/details_item_merge.dart';

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

    test(
      'keeps the card large poster when details only repeat the catalog artwork',
      () {
        final card = MultimediaItem(
          title: 'Title',
          url: 'anime://title',
          posterUrl: 'https://images.example/medium.jpg',
          fullPosterUrl: 'https://images.example/large.jpg',
        );
        final details = MultimediaItem(
          title: 'Title',
          url: card.url,
          posterUrl: 'https://images.example/medium.jpg',
          fullPosterUrl: 'https://images.example/medium.jpg',
        );

        final result = mergeDetailsItem(fallback: card, incoming: details);

        expect(result.posterUrl, card.posterUrl);
        expect(result.fullPosterUrl, card.fullPosterUrl);
        expect(result.posterViewerUrl, card.fullPosterUrl);
      },
    );

    test('prefers a larger details poster over the opening card', () {
      final card = MultimediaItem(
        title: 'Title',
        url: 'anime://title',
        posterUrl: 'https://images.example/medium.jpg',
        fullPosterUrl: 'https://images.example/large.jpg',
      );
      final details = MultimediaItem(
        title: 'Title',
        url: card.url,
        posterUrl: 'https://images.example/medium.jpg',
        fullPosterUrl: 'https://images.example/original.jpg',
      );

      final result = mergeDetailsItem(fallback: card, incoming: details);

      expect(result.posterUrl, details.posterUrl);
      expect(result.fullPosterUrl, details.fullPosterUrl);
      expect(result.posterViewerUrl, details.fullPosterUrl);
    });

    test(
      'keeps a high-quality details poster when it matches fullPosterUrl',
      () {
        final card = MultimediaItem(
          title: 'Title',
          url: 'anime://title',
          posterUrl: 'https://images.example/medium.jpg',
        );
        final details = MultimediaItem(
          title: 'Title',
          url: card.url,
          posterUrl: 'https://images.example/large.jpg',
          fullPosterUrl: 'https://images.example/large.jpg',
        );

        final result = mergeDetailsItem(fallback: card, incoming: details);

        expect(result.posterUrl, details.posterUrl);
        expect(result.fullPosterUrl, details.fullPosterUrl);
        expect(result.posterViewerUrl, details.fullPosterUrl);
      },
    );
  });
}
