import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/core/utils/image_quality.dart';

void main() {
  group('highestQualityImageUrl', () {
    test('upgrades AniList covers to extraLarge', () {
      expect(
        highestQualityImageUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx21-abc.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
      );
      expect(
        highestQualityImageUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/small/bx21-abc.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
      );
      expect(
        highestQualityImageUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
      );
    });

    test('upgrades MyAnimeList artwork to the large variant', () {
      expect(
        highestQualityImageUrl(
          'https://cdn.myanimelist.net/images/anime/13/17405.jpg',
        ),
        'https://cdn.myanimelist.net/images/anime/13/17405l.jpg',
      );
      expect(
        highestQualityImageUrl(
          'https://cdn.myanimelist.net/images/anime/13/17405t.jpg',
        ),
        'https://cdn.myanimelist.net/images/anime/13/17405l.jpg',
      );
    });

    test('upgrades TMDB artwork to the original size', () {
      expect(
        highestQualityImageUrl('https://image.tmdb.org/t/p/w500/abc.jpg'),
        'https://image.tmdb.org/t/p/original/abc.jpg',
      );
      expect(
        highestQualityImageUrl('https://image.tmdb.org/t/p/h632/abc.jpg'),
        'https://image.tmdb.org/t/p/original/abc.jpg',
      );
    });

    test('leaves unknown hosts, non-size paths and junk untouched', () {
      const animeWitcher = 'https://animewitcher.com/posters/one_piece.jpg';
      expect(highestQualityImageUrl(animeWitcher), animeWitcher);
      const malIcon =
          'https://cdn.myanimelist.net/img/sp/icon/apple-touch-icon-256.png';
      expect(highestQualityImageUrl(malIcon), malIcon);
      const aniListBanner =
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21-abc.jpg';
      expect(highestQualityImageUrl(aniListBanner), aniListBanner);
      expect(highestQualityImageUrl('   '), '');
      expect(highestQualityImageUrl('not a url'), 'not a url');
    });

    test('keeps query strings', () {
      expect(
        highestQualityImageUrl(
          'https://image.tmdb.org/t/p/w300/abc.jpg?token=1',
        ),
        'https://image.tmdb.org/t/p/original/abc.jpg?token=1',
      );
    });
  });

  group('fallbackQualityImageUrl', () {
    test('steps back down one size', () {
      expect(
        fallbackQualityImageUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-abc.jpg',
      );
      expect(
        fallbackQualityImageUrl(
          'https://cdn.myanimelist.net/images/anime/13/17405l.jpg',
        ),
        'https://cdn.myanimelist.net/images/anime/13/17405.jpg',
      );
      expect(
        fallbackQualityImageUrl('https://image.tmdb.org/t/p/original/abc.jpg'),
        'https://image.tmdb.org/t/p/w780/abc.jpg',
      );
    });

    test('returns null when there is nothing to fall back to', () {
      expect(
        fallbackQualityImageUrl(
          'https://animewitcher.com/posters/one_piece.jpg',
        ),
        isNull,
      );
      expect(
        fallbackQualityImageUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-abc.jpg',
        ),
        isNull,
      );
      expect(fallbackQualityImageUrl(''), isNull);
    });
  });

  group('AppImageFallbacks', () {
    test('hands out the largest variant of stored artwork', () {
      expect(
        AppImageFallbacks.poster(
          'https://cdn.myanimelist.net/images/anime/13/17405t.jpg',
        ),
        'https://cdn.myanimelist.net/images/anime/13/17405l.jpg',
      );
      expect(
        AppImageFallbacks.banner(
          bannerUrl: null,
          posterUrl:
              'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx21-abc.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/extraLarge/bx21-abc.jpg',
      );
    });

    test('still rejects placeholder values', () {
      expect(AppImageFallbacks.poster('null'), isNull);
      expect(AppImageFallbacks.poster('  '), isNull);
    });
  });
}
