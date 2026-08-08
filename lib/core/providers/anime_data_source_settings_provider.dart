import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_repository.dart';

class AnimeDataSourceSettings {
  final bool episodeImagesFromAniZip;
  final bool seasonNumberFromAniZip;
  final bool castFromAniList;
  final bool recommendationsFromAniList;

  const AnimeDataSourceSettings({
    this.episodeImagesFromAniZip = true,
    this.seasonNumberFromAniZip = true,
    this.castFromAniList = true,
    this.recommendationsFromAniList = true,
  });

  AnimeDataSourceSettings copyWith({
    bool? episodeImagesFromAniZip,
    bool? seasonNumberFromAniZip,
    bool? castFromAniList,
    bool? recommendationsFromAniList,
  }) {
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          episodeImagesFromAniZip ?? this.episodeImagesFromAniZip,
      seasonNumberFromAniZip:
          seasonNumberFromAniZip ?? this.seasonNumberFromAniZip,
      castFromAniList: castFromAniList ?? this.castFromAniList,
      recommendationsFromAniList:
          recommendationsFromAniList ?? this.recommendationsFromAniList,
    );
  }
}

final animeDataSourceSettingsProvider = NotifierProvider<
    AnimeDataSourceSettingsNotifier,
    AnimeDataSourceSettings>(AnimeDataSourceSettingsNotifier.new);

class AnimeDataSourceSettingsNotifier
    extends Notifier<AnimeDataSourceSettings> {
  SettingsRepository get _repository =>
      ref.read(settingsRepositoryProvider);

  @override
  AnimeDataSourceSettings build() {
    final repository = _repository;
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          repository.isEpisodeImagesFromAniZipEnabled(),
      seasonNumberFromAniZip:
          repository.isSeasonNumberFromAniZipEnabled(),
      castFromAniList: repository.isCastFromAniListEnabled(),
      recommendationsFromAniList:
          repository.isRecommendationsFromAniListEnabled(),
    );
  }

  Future<void> setEpisodeImagesFromAniZip(bool enabled) async {
    state = state.copyWith(episodeImagesFromAniZip: enabled);
    await _repository.setEpisodeImagesFromAniZipEnabled(enabled);
  }

  Future<void> setSeasonNumberFromAniZip(bool enabled) async {
    state = state.copyWith(seasonNumberFromAniZip: enabled);
    await _repository.setSeasonNumberFromAniZipEnabled(enabled);
  }

  Future<void> setCastFromAniList(bool enabled) async {
    state = state.copyWith(castFromAniList: enabled);
    await _repository.setCastFromAniListEnabled(enabled);
  }

  Future<void> setRecommendationsFromAniList(bool enabled) async {
    state = state.copyWith(recommendationsFromAniList: enabled);
    await _repository.setRecommendationsFromAniListEnabled(enabled);
  }
}
