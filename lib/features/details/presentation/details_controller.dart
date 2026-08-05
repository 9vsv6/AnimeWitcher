import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:collection/collection.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../../core/storage/library_repository.dart';
import '../../../../core/storage/history_repository.dart';
import 'package:skystream/core/storage/episode_watch_repository.dart';
import 'package:skystream/core/storage/storage_service.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/history_provider.dart';
import 'playback_launcher.dart';
import '../../../core/services/download_service.dart';
import '../data/metadata_resolution_service.dart';
import 'downloaded_file_provider.dart';
import '../../tracking/data/simkl_service.dart';

part 'details_controller.g.dart';

String episodeSelectionKey(Episode episode) {
  return [
    episode.season,
    episode.episode,
    episode.dubStatus.name,
    episode.url,
  ].join('|');
}

class DetailsState {
  final AsyncValue<MultimediaItem?> details;
  final AsyncValue<List<Episode>> episodes;
  final AsyncValue<List<Actor>> cast;
  final AsyncValue<List<Trailer>> trailers;
  final AsyncValue<List<MultimediaItem>> related;
  final AsyncValue<List<MultimediaItem>> recommendations;
  final Map<int, List<Episode>> seasonMap;
  final int selectedSeason;
  final bool isMovie;
  final MultimediaItem? item;
  final bool isLaunching;
  final Episode? targetEpisode;
  final bool isAscending;
  final int selectedRangeIndex;
  final DubStatus selectedDubStatus;
  final Set<String> selectedEpisodeKeys;

  const DetailsState({
    this.details = const AsyncLoading(),
    this.episodes = const AsyncLoading(),
    this.cast = const AsyncLoading(),
    this.trailers = const AsyncLoading(),
    this.related = const AsyncLoading(),
    this.recommendations = const AsyncLoading(),
    this.seasonMap = const {},
    this.selectedSeason = 1,
    this.isMovie = false,
    this.item,
    this.isLaunching = false,
    this.targetEpisode,
    this.isAscending = true,
    this.selectedRangeIndex = 0,
    this.selectedDubStatus = DubStatus.none,
    this.selectedEpisodeKeys = const <String>{},
  });

  DetailsState copyWith({
    AsyncValue<MultimediaItem?>? details,
    AsyncValue<List<Episode>>? episodes,
    AsyncValue<List<Actor>>? cast,
    AsyncValue<List<Trailer>>? trailers,
    AsyncValue<List<MultimediaItem>>? related,
    AsyncValue<List<MultimediaItem>>? recommendations,
    Map<int, List<Episode>>? seasonMap,
    int? selectedSeason,
    bool? isMovie,
    MultimediaItem? item,
    bool? isLaunching,
    Episode? targetEpisode,
    bool? isAscending,
    int? selectedRangeIndex,
    DubStatus? selectedDubStatus,
    Set<String>? selectedEpisodeKeys,
  }) {
    return DetailsState(
      details: details ?? this.details,
      episodes: episodes ?? this.episodes,
      cast: cast ?? this.cast,
      trailers: trailers ?? this.trailers,
      related: related ?? this.related,
      recommendations: recommendations ?? this.recommendations,
      seasonMap: seasonMap ?? this.seasonMap,
      selectedSeason: selectedSeason ?? this.selectedSeason,
      isMovie: isMovie ?? this.isMovie,
      item: item ?? this.item,
      isLaunching: isLaunching ?? this.isLaunching,
      targetEpisode: targetEpisode ?? this.targetEpisode,
      isAscending: isAscending ?? this.isAscending,
      selectedRangeIndex: selectedRangeIndex ?? this.selectedRangeIndex,
      selectedDubStatus: selectedDubStatus ?? this.selectedDubStatus,
      selectedEpisodeKeys: selectedEpisodeKeys ?? this.selectedEpisodeKeys,
    );
  }
}

@riverpod
class DetailsController extends _$DetailsController {
  Future<void>? _episodesLoadFuture;
  SkyStreamProvider? _lastEpisodesProvider;
  String? _lastEpisodesUrl;
  bool _loadStarted = false;
  int _loadGeneration = 0;

  @override
  DetailsState build(String itemUrl) {
    ref.listen(activeDownloadsProvider, (prev, next) {
      final details = state.details.asData?.value;
      if (details == null) return;

      // Detect URLs that were active but are no longer active (completed/failed/canceled)
      final previousSet = prev ?? <String>{};
      final finishingUrls = previousSet.difference(next);

      if (finishingUrls.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[DetailsController] Re-checking status immediately after download finished: $finishingUrls',
          );
        }

        // Re-check specific item if its URL finished
        if (finishingUrls.contains(details.url)) {
          ref.read(downloadedFilesProvider.notifier).checkFile(details);
        }

        // Re-check episodes
        final episodes =
            state.episodes.asData?.value ??
            details.episodes ??
            const <Episode>[];
        for (final ep in episodes) {
          if (finishingUrls.contains(ep.url)) {
            ref
                .read(downloadedFilesProvider.notifier)
                .checkFile(details, episode: ep);
          }
        }
      }
    });

    ref.listen(watchHistoryProvider, (prev, next) {
      final details = state.details.asData?.value;
      if (details != null) {
        _processEpisodes(
          state.episodes.asData?.value ?? details.episodes,
          details,
          isInitial: false,
        );
      }
    });

    ref.listen(episodeWatchRevisionProvider, (prev, next) {
      final details = state.details.asData?.value;
      if (details != null) {
        _processEpisodes(
          state.episodes.asData?.value ?? details.episodes,
          details,
          isInitial: false,
        );
      }
    });

    final savedAscending =
        ref
            .read(storageServiceProvider)
            .getPlayerSetting<bool>(
              'episode_sort_ascending',
              defaultValue: true,
            ) ??
        true;

    return DetailsState(isAscending: savedAscending);
  }

  void init(MultimediaItem initialItem) {
    if (state.item == null) {
      state = state.copyWith(item: initialItem);
    }
  }

  void setSeason(int season) {
    if (state.seasonMap.containsKey(season)) {
      state = state.copyWith(selectedSeason: season, selectedRangeIndex: 0);
    }
  }

  void toggleSort() {
    final nextAscending = !state.isAscending;
    state = state.copyWith(isAscending: nextAscending);

    unawaited(
      ref
          .read(storageServiceProvider)
          .setPlayerSetting('episode_sort_ascending', nextAscending),
    );
  }

  bool isEpisodeSelected(Episode episode) {
    return state.selectedEpisodeKeys.contains(episodeSelectionKey(episode));
  }

  void toggleEpisodeSelection(Episode episode) {
    final next = Set<String>.from(state.selectedEpisodeKeys);
    final key = episodeSelectionKey(episode);

    if (!next.add(key)) {
      next.remove(key);
    }

    state = state.copyWith(selectedEpisodeKeys: next);
  }

  void selectAllEpisodes() {
    final allEpisodeKeys = state.seasonMap.values
        .expand((episodes) => episodes)
        .map(episodeSelectionKey)
        .toSet();

    if (allEpisodeKeys.isEmpty) {
      return;
    }

    state = state.copyWith(selectedEpisodeKeys: allEpisodeKeys);
  }

  void clearEpisodeSelection() {
    if (state.selectedEpisodeKeys.isEmpty) {
      return;
    }

    state = state.copyWith(selectedEpisodeKeys: const <String>{});
  }

  Future<void> setSelectedEpisodesWatched(String mainUrl, bool watched) async {
    if (state.selectedEpisodeKeys.isEmpty) {
      return;
    }

    final selectedKeys = Set<String>.from(state.selectedEpisodeKeys);

    final selectedEpisodes = state.seasonMap.values
        .expand((episodes) => episodes)
        .where((episode) => selectedKeys.contains(episodeSelectionKey(episode)))
        .toList(growable: false);

    if (selectedEpisodes.isEmpty) {
      clearEpisodeSelection();
      return;
    }

    await ref
        .read(episodeWatchRepositoryProvider)
        .setManyWatched(mainUrl, selectedEpisodes, watched);

    if (!ref.mounted) {
      return;
    }

    state = state.copyWith(selectedEpisodeKeys: const <String>{});

    final currentDetails = state.details.asData?.value;
    if (currentDetails != null) {
      _processEpisodes(
        currentDetails.episodes,
        currentDetails,
        isInitial: false,
      );
    }
  }

  void setRangeIndex(int index) {
    state = state.copyWith(selectedRangeIndex: index);
  }

  void setDubStatus(DubStatus status) {
    state = state.copyWith(selectedDubStatus: status, selectedRangeIndex: 0);
  }

  void setLaunching(bool value) {
    if (state.isLaunching != value) {
      state = state.copyWith(isLaunching: value);
    }
  }

  Future<void> loadDetails(MultimediaItem item, {bool autoPlay = false}) async {
    if (_loadStarted) return;
    _loadStarted = true;
    final generation = ++_loadGeneration;

    state = state.copyWith(
      details: const AsyncLoading(),
      episodes: const AsyncLoading(),
      cast: const AsyncLoading(),
      trailers: const AsyncLoading(),
      related: const AsyncLoading(),
      recommendations: const AsyncLoading(),
      item: item,
      isMovie:
          item.contentType == MultimediaContentType.movie ||
          item.contentType == MultimediaContentType.livestream,
    );

    final active = ref.read(activeProviderProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    try {
      if (item.provider == 'Local' ||
          item.provider == 'Torrent' ||
          item.provider == 'Remote') {
        var itemToUse = item;
        if (itemToUse.episodes == null || itemToUse.episodes!.isEmpty) {
          itemToUse = itemToUse.copyWith(
            episodes: [
              Episode(
                name: itemToUse.title,
                url: itemToUse.url,
                posterUrl: itemToUse.posterUrl,
              ),
            ],
          );
        }

        final sorted =
            _processEpisodes(itemToUse.episodes, itemToUse, isInitial: true) ??
            const <Episode>[];
        final rendered = itemToUse.copyWith(episodes: sorted);
        state = state.copyWith(
          details: AsyncData(rendered),
          episodes: AsyncData(sorted),
          cast: AsyncData(rendered.cast ?? const <Actor>[]),
          trailers: AsyncData(rendered.trailers ?? const <Trailer>[]),
          related: AsyncData(rendered.related ?? const <MultimediaItem>[]),
          recommendations: AsyncData(
            rendered.recommendations ?? const <MultimediaItem>[],
          ),
          item: rendered,
        );
        return;
      }

      SkyStreamProvider? provider;
      if (item.provider != null) {
        try {
          provider = manager.getAllProviders().firstWhere(
            (candidate) =>
                candidate.packageName == item.provider ||
                candidate.name == item.provider,
          );
        } catch (error) {
          if (kDebugMode) {
            debugPrint('DetailsController.loadDetails: $error');
          }
        }
      }

      provider ??= active;
      if (provider == null) {
        throw Exception("No provider selected or found for this item");
      }

      _lastEpisodesProvider = provider;
      _lastEpisodesUrl = item.url;

      // Every part starts immediately. No request waits for another request.
      unawaited(_loadBasicDetails(provider, item, generation));
      _episodesLoadFuture = _loadEpisodesInBackground(
        provider,
        item.url,
        item,
        generation,
      );
      unawaited(_episodesLoadFuture!);

      if (provider.supportsIndependentDetailSections) {
        unawaited(_loadCastInBackground(provider, item.url, item, generation));
        unawaited(
          _loadTrailersInBackground(provider, item.url, item, generation),
        );
        unawaited(
          _loadRelatedInBackground(provider, item.url, item, generation),
        );
        unawaited(
          _loadRecommendationsInBackground(
            provider,
            item.url,
            item,
            generation,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      final asyncError = AsyncError<MultimediaItem?>(error, stackTrace);
      state = state.copyWith(
        details: asyncError,
        episodes: AsyncError<List<Episode>>(error, stackTrace),
        cast: AsyncError<List<Actor>>(error, stackTrace),
        trailers: AsyncError<List<Trailer>>(error, stackTrace),
        related: AsyncError<List<MultimediaItem>>(error, stackTrace),
        recommendations: AsyncError<List<MultimediaItem>>(error, stackTrace),
      );
    }
  }

  Future<void> _loadBasicDetails(
    SkyStreamProvider provider,
    MultimediaItem initialItem,
    int generation,
  ) async {
    try {
      final fetchedItem = await provider.getDetails(initialItem.url);
      if (!ref.mounted || generation != _loadGeneration) return;

      final withProvider = fetchedItem.copyWith(
        provider: provider.packageName,
        tmdbId: fetchedItem.tmdbId ?? initialItem.tmdbId,
        imdbId: fetchedItem.imdbId ?? initialItem.imdbId,
      );
      final current = state.item ?? initialItem;
      final currentEpisodes = state.episodes.asData?.value ?? current.episodes;
      final independent = provider.supportsIndependentDetailSections;
      final currentCast = state.cast.asData?.value ?? current.cast;
      final currentTrailers = state.trailers.asData?.value ?? current.trailers;
      final currentRelated = state.related.asData?.value ?? current.related;
      final currentRecommendations =
          state.recommendations.asData?.value ?? current.recommendations;

      final rendered = withProvider.copyWith(
        episodes: currentEpisodes,
        cast: independent ? currentCast : (withProvider.cast ?? currentCast),
        trailers: independent
            ? currentTrailers
            : (withProvider.trailers ?? currentTrailers),
        related: independent
            ? currentRelated
            : (withProvider.related ?? currentRelated),
        recommendations: independent
            ? currentRecommendations
            : (withProvider.recommendations ?? currentRecommendations),
      );

      if (currentEpisodes == null || currentEpisodes.isEmpty) {
        _processEpisodes(null, rendered, isInitial: true);
      }

      state = state.copyWith(
        details: AsyncData(rendered),
        item: rendered,
        cast: independent
            ? null
            : AsyncData(rendered.cast ?? const <Actor>[]),
        trailers: independent
            ? null
            : AsyncData(rendered.trailers ?? const <Trailer>[]),
        related: independent
            ? null
            : AsyncData(rendered.related ?? const <MultimediaItem>[]),
        recommendations: independent
            ? null
            : AsyncData(
                rendered.recommendations ?? const <MultimediaItem>[],
              ),
      );

      final inlineEpisodes = fetchedItem.episodes ?? const <Episode>[];
      if (inlineEpisodes.isNotEmpty && state.episodes is! AsyncData) {
        _applyEpisodes(
          provider,
          initialItem.url,
          rendered,
          inlineEpisodes,
          generation,
        );
      }

      unawaited(_resolveMetadataInBackground(rendered));
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        details: AsyncError<MultimediaItem?>(error, stackTrace),
        cast: provider.supportsIndependentDetailSections
            ? null
            : AsyncError<List<Actor>>(error, stackTrace),
        trailers: provider.supportsIndependentDetailSections
            ? null
            : AsyncError<List<Trailer>>(error, stackTrace),
        related: provider.supportsIndependentDetailSections
            ? null
            : AsyncError<List<MultimediaItem>>(error, stackTrace),
        recommendations: provider.supportsIndependentDetailSections
            ? null
            : AsyncError<List<MultimediaItem>>(error, stackTrace),
      );
    }
  }

  void _applyEpisodes(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    List<Episode> fetchedEpisodes,
    int generation,
  ) {
    if (!ref.mounted || generation != _loadGeneration) return;
    final current = state.item ?? contextItem;
    final sorted =
        _processEpisodes(fetchedEpisodes, current, isInitial: true) ??
        const <Episode>[];
    final merged = current.copyWith(episodes: sorted);
    state = state.copyWith(
      details: state.details.hasValue ? AsyncData(merged) : null,
      episodes: AsyncData(sorted),
      item: merged,
    );
    unawaited(
      _loadEpisodeMetadataInBackground(
        provider,
        url,
        merged,
        generation,
      ),
    );
  }

  Future<void> _loadEpisodesInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final fetchedEpisodes = await provider.getEpisodes(url);
      if (!ref.mounted || generation != _loadGeneration) return;
      _applyEpisodes(
        provider,
        url,
        contextItem,
        fetchedEpisodes,
        generation,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        episodes: AsyncError<List<Episode>>(error, stackTrace),
        seasonMap: const {},
        selectedEpisodeKeys: const <String>{},
      );
    } finally {
      if (generation == _loadGeneration) {
        _episodesLoadFuture = null;
      }
    }
  }

  Future<void> _loadCastInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final value = await provider.getCast(url);
      if (!ref.mounted || generation != _loadGeneration) return;
      final updated = (state.item ?? contextItem).copyWith(cast: value);
      state = state.copyWith(
        cast: AsyncData(value),
        details: state.details.hasValue ? AsyncData(updated) : null,
        item: updated,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(cast: AsyncError<List<Actor>>(error, stackTrace));
    }
  }

  Future<void> _loadTrailersInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final value = await provider.getTrailers(url);
      if (!ref.mounted || generation != _loadGeneration) return;
      final updated = (state.item ?? contextItem).copyWith(trailers: value);
      state = state.copyWith(
        trailers: AsyncData(value),
        details: state.details.hasValue ? AsyncData(updated) : null,
        item: updated,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        trailers: AsyncError<List<Trailer>>(error, stackTrace),
      );
    }
  }

  Future<void> _loadRelatedInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final value = await provider.getRelated(url);
      if (!ref.mounted || generation != _loadGeneration) return;
      final updated = (state.item ?? contextItem).copyWith(related: value);
      state = state.copyWith(
        related: AsyncData(value),
        details: state.details.hasValue ? AsyncData(updated) : null,
        item: updated,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        related: AsyncError<List<MultimediaItem>>(error, stackTrace),
      );
    }
  }

  Future<void> _loadRecommendationsInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final value = await provider.getRecommendations(url);
      if (!ref.mounted || generation != _loadGeneration) return;
      final updated = (state.item ?? contextItem).copyWith(
        recommendations: value,
      );
      state = state.copyWith(
        recommendations: AsyncData(value),
        details: state.details.hasValue ? AsyncData(updated) : null,
        item: updated,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        recommendations: AsyncError<List<MultimediaItem>>(error, stackTrace),
      );
    }
  }

  Episode _mergeEpisodeMetadata(Episode source, Episode metadata) {
    final metadataPoster = metadata.posterUrl?.trim();
    return Episode(
      name: source.name,
      url: source.url,
      season: metadata.season > 0 ? metadata.season : source.season,
      episode: metadata.episode > 0 ? metadata.episode : source.episode,
      description: source.description,
      posterUrl: metadataPoster != null && metadataPoster.isNotEmpty
          ? metadataPoster
          : source.posterUrl,
      headers: source.headers,
      rating: source.rating,
      runtime: source.runtime,
      airDate: source.airDate,
      dubStatus: source.dubStatus,
      playbackPolicy: source.playbackPolicy,
      streams: source.streams,
    );
  }

  Future<void> _loadEpisodeMetadataInBackground(
    SkyStreamProvider provider,
    String url,
    MultimediaItem contextItem,
    int generation,
  ) async {
    try {
      final metadata = await provider.getEpisodeMetadata(url);
      if (!ref.mounted || generation != _loadGeneration || metadata.isEmpty) {
        return;
      }

      final currentItem = state.item;
      if (currentItem == null || currentItem.url != contextItem.url) return;

      final currentEpisodes =
          state.episodes.asData?.value ??
          currentItem.episodes ??
          const <Episode>[];
      if (currentEpisodes.isEmpty) return;

      final byUrl = <String, Episode>{};
      final byNumber = <int, Episode>{};
      for (final item in metadata) {
        if (item.url.isNotEmpty) byUrl[item.url] = item;
        if (item.episode > 0) byNumber[item.episode] = item;
      }

      var changed = false;
      final enriched = currentEpisodes.map((episode) {
        final match = byUrl[episode.url] ?? byNumber[episode.episode];
        if (match == null) return episode;
        final merged = _mergeEpisodeMetadata(episode, match);
        if (merged.season != episode.season ||
            merged.episode != episode.episode ||
            merged.posterUrl != episode.posterUrl) {
          changed = true;
        }
        return merged;
      }).toList(growable: false);
      if (!changed || !ref.mounted) return;

      final canPreserveSelectedSeason = enriched.any(
        (episode) => episode.season == state.selectedSeason,
      );
      final processed =
          _processEpisodes(
            enriched,
            currentItem,
            isInitial: !canPreserveSelectedSeason,
          ) ??
          enriched;
      final updatedItem = currentItem.copyWith(episodes: processed);
      state = state.copyWith(
        details: state.details.hasValue ? AsyncData(updatedItem) : null,
        episodes: AsyncData(processed),
        item: updatedItem,
      );
    } catch (error) {
      // Optional enrichment must never replace successfully loaded episodes.
      if (kDebugMode) {
        debugPrint('Episode metadata enrichment failed: $error');
      }
    }
  }

  Future<void> retryEpisodes() async {
    final provider = _lastEpisodesProvider;
    final url = _lastEpisodesUrl;
    final currentItem = state.item;

    if (provider == null || url == null || currentItem == null) {
      return;
    }

    state = state.copyWith(episodes: const AsyncLoading());
    final generation = _loadGeneration;
    _episodesLoadFuture = _loadEpisodesInBackground(
      provider,
      url,
      currentItem,
      generation,
    );
    await _episodesLoadFuture;
  }

  Future<void> _resolveMetadataInBackground(MultimediaItem withProvider) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'DetailsController: Fetching missing IDs in background for ${withProvider.title}...',
        );
      }
      MultimediaItem enrichedItem = withProvider;

      final hasAnyWesternId =
          withProvider.tmdbId != null || withProvider.imdbId != null;

      try {
        if (!hasAnyWesternId) {
          enrichedItem = await ref
              .read(metadataResolutionServiceProvider)
              .enrichWithIds(withProvider);
          if (kDebugMode) {
            debugPrint(
              'DetailsController: Background resolution result -> tmdbId: ${enrichedItem.tmdbId}, imdbId: ${enrichedItem.imdbId}',
            );
          }
        } else {
          if (kDebugMode) {
            debugPrint(
              'DetailsController: Bypassed TMDB resolution (tmdbId or imdbId already provided by scraper)',
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'DetailsController: TMDB metadata resolution failed, but continuing: $e',
          );
        }
      }

      // Pre-fetch Simkl / AniList tracking IDs
      MultimediaItem finalItem = enrichedItem;
      try {
        final isAnime =
            enrichedItem.contentType == MultimediaContentType.anime ||
            enrichedItem.syncData?['anilistId'] != null ||
            enrichedItem.syncData?['anilist_id'] != null ||
            (enrichedItem.tags != null &&
                enrichedItem.tags!.any(
                  (t) =>
                      t.toLowerCase() == 'anime' ||
                      t.toLowerCase() == 'animation',
                ));

        if (isAnime) {
          final hasAnilistId =
              enrichedItem.syncData?['anilist'] != null ||
              enrichedItem.syncData?['anilistId'] != null ||
              enrichedItem.syncData?['anilist_id'] != null;

          if (!hasAnilistId) {
            final simkl = ref.read(simklServiceProvider);
            final resolved = await simkl.syncIds(enrichedItem);
            if (resolved.isNotEmpty) {
              final newSyncData = Map<String, String>.from(
                enrichedItem.syncData ?? {},
              );
              newSyncData.addAll(resolved);
              finalItem = enrichedItem.copyWith(syncData: newSyncData);
              if (kDebugMode) {
                debugPrint('DetailsController: Fetched Simkl IDs: $resolved');
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                'DetailsController: Bypassed Simkl fetch (AniList ID already provided by scraper)',
              );
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'DetailsController: Failed to fetch Simkl IDs in background: $e',
          );
        }
      }

      if (!ref.mounted) return;

      if (finalItem.tmdbId != withProvider.tmdbId ||
          finalItem.imdbId != withProvider.imdbId ||
          finalItem.syncData != withProvider.syncData) {
        // preserve the episodes from the current state just in case
        final currentDetails = state.details.asData?.value;
        if (currentDetails != null) {
          final updatedItem = currentDetails.copyWith(
            tmdbId: finalItem.tmdbId,
            imdbId: finalItem.imdbId,
            syncData: finalItem.syncData,
          );
          state = state.copyWith(
            details: AsyncData(updatedItem),
            item: updatedItem,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'DetailsController: Background metadata resolution failed: $e',
        );
      }
    }
  }

  List<Episode>? _processEpisodes(
    List<Episode>? episodes,
    MultimediaItem contextItem, {
    bool isInitial = false,
  }) {
    if (episodes == null || episodes.isEmpty) {
      state = state.copyWith(
        isMovie: contextItem.contentType == MultimediaContentType.movie,
        seasonMap: {},
      );
      return episodes;
    }

    bool isMovie =
        contextItem.contentType == MultimediaContentType.movie ||
        contextItem.contentType == MultimediaContentType.livestream;

    if (!isMovie && episodes.length == 1) {
      isMovie = true;
    }

    if (isMovie) {
      state = state.copyWith(
        isMovie: true,
        seasonMap: {1: episodes},
        selectedSeason: 1,
      );
      return episodes;
    }

    final Map<int, List<Episode>> seasonMap = {};
    for (final ep in episodes) {
      final season = ep.season > 0 ? ep.season : 1;
      seasonMap.putIfAbsent(season, () => []).add(ep);
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();
    int selectedSeason = sortedSeasons.isNotEmpty ? sortedSeasons.first : 1;
    Episode? targetEpisode;

    final historyRepo = ref.read(historyRepositoryProvider);
    final episodeWatchRepo = ref.read(episodeWatchRepositoryProvider);

    final allEpisodes = episodes;
    final lastEpisodeUrl = historyRepo.getLastEpisodeUrl(contextItem.url);

    if (lastEpisodeUrl != null) {
      int lastIndex = allEpisodes.indexWhere((e) => e.url == lastEpisodeUrl);

      if (lastIndex == -1) {
        final mainHistoryItem = ref
            .read(watchHistoryProvider)
            .firstWhereOrNull((h) => h.item.url == contextItem.url);
        if (mainHistoryItem != null &&
            mainHistoryItem.season != null &&
            mainHistoryItem.episode != null) {
          lastIndex = allEpisodes.indexWhere(
            (e) =>
                e.season == mainHistoryItem.season &&
                e.episode == mainHistoryItem.episode,
          );
        }
      }

      if (lastIndex != -1) {
        final matchedEp = allEpisodes[lastIndex];
        if (episodeWatchRepo.isWatched(contextItem.url, matchedEp)) {
          if (lastIndex + 1 < allEpisodes.length) {
            targetEpisode = allEpisodes[lastIndex + 1];
          } else {
            targetEpisode = allEpisodes[lastIndex];
          }
        } else {
          targetEpisode = allEpisodes[lastIndex];
        }
      }
    }

    targetEpisode ??= allEpisodes.firstWhereOrNull(
      (episode) => !episodeWatchRepo.isWatched(contextItem.url, episode),
    );

    targetEpisode ??= allEpisodes.last;

    if (isInitial && targetEpisode.season > 0) {
      selectedSeason = targetEpisode.season;
    } else {
      selectedSeason = state.selectedSeason;
    }

    DubStatus selectedDubStatus = state.selectedDubStatus;
    if (isInitial) {
      final hasSub = episodes.any((e) => e.dubStatus == DubStatus.subbed);
      final hasDub = episodes.any((e) => e.dubStatus == DubStatus.dubbed);
      if (hasSub && hasDub) {
        selectedDubStatus = DubStatus.subbed;
      }
    }

    state = state.copyWith(
      isMovie: false,
      seasonMap: seasonMap,
      selectedSeason: selectedSeason,
      targetEpisode: targetEpisode,
      selectedDubStatus: selectedDubStatus,
    );
    return episodes;
  }

  void toggleLibrary() {
    final item = state.details.value;
    if (item == null) return;

    final libraryRepo = ref.read(libraryRepositoryProvider);
    final wasInLibrary = libraryRepo.isInLibrary(item.url);

    if (wasInLibrary) {
      ref.read(libraryProvider.notifier).removeItem(item.url);
    } else {
      ref.read(libraryProvider.notifier).addItem(item);
    }
  }

  Future<void> handlePlayPress(
    BuildContext context,
    MultimediaItem details, {
    Episode? specificEpisode,
    String? overrideUrl,
  }) async {
    if (state.episodes.isLoading && _episodesLoadFuture != null) {
      await _episodesLoadFuture;
      if (!ref.mounted) return;
    }

    details = state.details.asData?.value ?? details;

    if (overrideUrl != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, overrideUrl, baseItem: details);
      return;
    }

    if (specificEpisode != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, specificEpisode.url, baseItem: details);
      return;
    }

    if (state.isMovie) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, details.episodes!.first.url, baseItem: details);
      return;
    }

    if (state.targetEpisode != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, state.targetEpisode!.url, baseItem: details);
      return;
    }

    final firstSeason = state.seasonMap.keys.toList()..sort();
    if (firstSeason.isNotEmpty) {
      final ep = state.seasonMap[firstSeason.first]?.first;
      if (ep != null) {
        await ref
            .read(playbackLauncherProvider)
            .play(context, ep.url, baseItem: details);
      }
    }
  }
}
