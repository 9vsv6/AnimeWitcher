import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_repository.dart';

class AnimeDataSourceSettings {
  final bool episodeImagesFromAniZip;

  const AnimeDataSourceSettings({
    this.episodeImagesFromAniZip = true,
  });

  AnimeDataSourceSettings copyWith({
    bool? episodeImagesFromAniZip,
  }) {
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          episodeImagesFromAniZip ?? this.episodeImagesFromAniZip,
    );
  }
}

final animeDataSourceSettingsProvider = NotifierProvider<
    AnimeDataSourceSettingsNotifier,
    AnimeDataSourceSettings>(AnimeDataSourceSettingsNotifier.new);

class AnimeDataSourceSettingsNotifier
    extends Notifier<AnimeDataSourceSettings> {
  late final SettingsRepository _repository;

  @override
  AnimeDataSourceSettings build() {
    _repository = ref.watch(settingsRepositoryProvider);
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          _repository.isEpisodeImagesFromAniZipEnabled(),
    );
  }

  Future<void> setEpisodeImagesFromAniZip(bool enabled) async {
    state = state.copyWith(episodeImagesFromAniZip: enabled);
    await _repository.setEpisodeImagesFromAniZipEnabled(enabled);
  }
}
