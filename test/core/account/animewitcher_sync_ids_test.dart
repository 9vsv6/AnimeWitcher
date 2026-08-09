import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/account/animewitcher_sync_ids.dart';

void main() {
  group('AnimeWitcherSyncIds', () {
    test('round-trips anime document IDs through provider URLs', () {
      const animeId = 'black clover/season-2';
      final url = AnimeWitcherSyncIds.mainUrl(animeId);

      expect(
        AnimeWitcherSyncIds.animeIdFromUrl(url),
        animeId,
      );
    });

    test('accepts the www AnimeWitcher host and ignores query values', () {
      expect(
        AnimeWitcherSyncIds.animeIdFromUrl(
          'https://www.animewitcher.com/watch/one_piece?from=home',
        ),
        'one_piece',
      );
    });

    test('rejects non-AnimeWitcher media URLs', () {
      expect(
        AnimeWitcherSyncIds.animeIdFromUrl(
          'https://example.com/watch/one_piece',
        ),
        isNull,
      );
    });

    test('round-trips encoded episode document IDs', () {
      const animeId = 'one_piece';
      const episodeId = 'episode/1159 عربي';
      final url = AnimeWitcherSyncIds.episodeUrl(animeId, episodeId);

      expect(AnimeWitcherSyncIds.episodeIdFromUrl(url), episodeId);
    });

    test('returns null for a non-provider episode URL', () {
      expect(
        AnimeWitcherSyncIds.episodeIdFromUrl('https://cdn.test/video.mp4'),
        isNull,
      );
    });
  });
}
