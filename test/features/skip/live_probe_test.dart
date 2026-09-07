@Tags(['live'])
library;

import 'package:animewitcher/core/network/stale_connection_retry.dart';
import 'package:animewitcher/features/skip/data/anime_id_mappings.dart';
import 'package:animewitcher/features/skip/data/aniskip_service.dart';
import 'package:animewitcher/features/skip/data/intro_db_service.dart';
import 'package:animewitcher/features/skip/data/mal_id_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits the real services, so it is not part of the normal suite.
/// Run with: flutter test test/features/skip/live_probe_test.dart --tags live
void main() {
  test(
    'resolve a title and fetch its skip times',
    () async {
      final dio = createAnimeWitcherDio();
      final resolver = MalIdResolver(dio);

      for (final title in <String>[
        'One Piece',
        'Futsutsuka na Akujo dewa Gozaimasu ga: Suuguu Chouso Torikae Den',
        'Mao',
      ]) {
        final malId = await resolver.resolve(title);
        // ignore: avoid_print
        print('TITLE "$title" -> mal $malId');
        if (malId == null) continue;

        final segments = await AniSkipService(
          dio,
        ).getSkipSegments(malId: malId, season: 1, episode: 1, duration: 1440);
        // ignore: avoid_print
        print(
          '  aniskip: ${segments.map((s) => '${s.type.name} '
              '${s.startTime.toStringAsFixed(0)}-${s.endTime.toStringAsFixed(0)}')}',
        );

        final ids = await AnimeIdMappings(dio).byMalId(malId);
        // ignore: avoid_print
        print('  ids: $ids');
        if (ids == null) continue;

        final introDb = await IntroDbService(dio).getSkipSegments(
          imdbId: ids.imdbId,
          tmdbId: ids.tmdbId,
          season: 1,
          episode: 1,
          duration: 1440,
        );
        // ignore: avoid_print
        print(
          '  introdb: ${introDb.map((s) => '${s.type.name} '
              '${s.startTime.toStringAsFixed(0)}-${s.endTime.toStringAsFixed(0)}')}',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
