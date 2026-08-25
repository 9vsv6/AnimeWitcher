import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_repository.dart';

class AnimeDataSourceSettings {
  final bool episodeImagesFromAniZip;

  /// Posters are requested and decoded at their largest available size.
  /// Turning this off keeps the lighter standard artwork.
  final bool highQualityPosters;

  const AnimeDataSourceSettings({
    this.episodeImagesFromAniZip = true,
    this.highQualityPosters = true,
  });

  AnimeDataSourceSettings copyWith({
    bool? episodeImagesFromAniZip,
    bool? highQualityPosters,
  }) {
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          episodeImagesFromAniZip ?? this.episodeImagesFromAniZip,
      highQualityPosters: highQualityPosters ?? this.highQualityPosters,
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
    final highQualityPosters = _repository.isHighQualityPostersEnabled();
    _applyImageCacheBudget(highQualityPosters);
    return AnimeDataSourceSettings(
      episodeImagesFromAniZip:
          _repository.isEpisodeImagesFromAniZipEnabled(),
      highQualityPosters: highQualityPosters,
    );
  }

  Future<void> setEpisodeImagesFromAniZip(bool enabled) async {
    state = state.copyWith(episodeImagesFromAniZip: enabled);
    await _repository.setEpisodeImagesFromAniZipEnabled(enabled);
  }

  Future<void> setHighQualityPosters(bool enabled) async {
    state = state.copyWith(highQualityPosters: enabled);
    _applyImageCacheBudget(enabled);
    await _repository.setHighQualityPostersEnabled(enabled);
  }

  /// Full-size artwork needs room to stay cached; a small budget would only
  /// evict and re-decode the same posters while scrolling. Standard artwork is
  /// small enough for the lighter budget the app used before.
  void _applyImageCacheBudget(bool highQuality) {
    PaintingBinding.instance.imageCache
      ..maximumSize = highQuality ? 400 : 200
      ..maximumSizeBytes =
          (highQuality ? 256 : 50) * 1024 * 1024;
  }
}
