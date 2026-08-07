import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import 'anilist_repository.dart';

part 'anilist_explore_provider.g.dart';

Future<List<MultimediaItem>> _section(Ref ref, String key) =>
    ref.watch(anilistRepositoryProvider).fetchSection(key, titleLang: 'english');

@riverpod
Future<List<MultimediaItem>> trendingAnime(Ref ref) => _section(ref, 'trending');

@riverpod
Future<List<MultimediaItem>> airedRecentlyAnime(Ref ref) =>
    _section(ref, 'airedRecently');

@riverpod
Future<List<MultimediaItem>> topSeasonAnime(Ref ref) =>
    _section(ref, 'topSeason');

@riverpod
Future<List<MultimediaItem>> bestLastSeasonAnime(Ref ref) =>
    _section(ref, 'bestLastSeason');

@riverpod
Future<List<MultimediaItem>> moviesAnime(Ref ref) => _section(ref, 'movies');

@riverpod
Future<List<MultimediaItem>> comingSoonAnime(Ref ref) =>
    _section(ref, 'comingSoon');

@riverpod
Future<List<MultimediaItem>> anilistHeroAnime(Ref ref) async {
  final repo = ref.watch(anilistRepositoryProvider);
  final trending = await repo.fetchSection('trending', titleLang: 'english');
  final top5 = trending.take(5).toList(growable: false);

  return Future.wait(
    top5.map((item) async {
      final rawId = item.syncData?['anilistId'] ?? item.syncData?['anilist_id'];
      final anilistId = int.tryParse(rawId ?? '');
      if (anilistId == null) return item;
      final images = await repo.getAnimeImages(anilistId);
      final logoUrl = images['logo'];
      final fanartUrl = images['fanart'];
      var updatedItem = item;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        updatedItem = updatedItem.copyWith(logoUrl: logoUrl);
      }
      if (fanartUrl != null && fanartUrl.isNotEmpty) {
        updatedItem = updatedItem.copyWith(bannerUrl: fanartUrl);
      }
      return updatedItem;
    }),
  );
}
