import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/logger/app_logger.dart';
import '../../../../core/storage/history_repository.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../domain/sync_progress_item.dart';
import 'anilist_service.dart';
import 'mal_service.dart';
import 'tracking_service.dart';
import '../../library/presentation/history_provider.dart';

part 'sync_manager.g.dart';

class SyncManager {
  final List<TrackingService> _services;

  SyncManager(this._services);

  // Cache resolved IDs for the duration of a playback session
  Map<String, String>? _cachedIds;
  String? _cachedItemUrl;

  /// Returns all tracking services that the user is currently logged into
  Future<List<TrackingService>> getActiveServices() async {
    final active = <TrackingService>[];
    for (final service in _services) {
      if (await service.isLoggedIn) {
        active.add(service);
      }
    }
    return active;
  }

  /// Resolve IDs for the given item across all services. Uses cache if available.
  Future<Map<String, String>> _resolveIds(MultimediaItem item) async {
    if (_cachedItemUrl == item.url && _cachedIds != null) {
      return _cachedIds!;
    }

    final ids = Map<String, String>.from(item.syncData ?? {});

    _cachedIds = ids;
    _cachedItemUrl = item.url;
    return _cachedIds!;
  }

  /// Clears the cached IDs, typically called when starting a new media item
  void clearCache() {
    _cachedIds = null;
    _cachedItemUrl = null;
  }

  bool _shouldSkipSync(MultimediaItem item) {
    if (item.contentType == MultimediaContentType.livestream) {
      return true;
    }
    final hasNoIds =
        item.imdbId == null &&
        item.tmdbId == null &&
        (item.syncData == null || item.syncData!.isEmpty);
    return hasNoIds;
  }

  /// Mark an episode or movie as watched across all active services
  Future<void> markWatched(MultimediaItem item, Episode? episode) async {
    if (_shouldSkipSync(item)) return;

    final active = await getActiveServices();
    if (active.isEmpty) return;

    final resolvedIds = await _resolveIds(item);

    for (final service in active) {
      try {
        await service.markWatched(item, episode, resolvedIds: resolvedIds);
      } catch (e) {
        // Ignore failure on a single service
      }
    }
  }

  /// Scrobble start event
  Future<void> scrobbleStart(
    MultimediaItem item,
    Episode? episode,
    double progress,
  ) async {
    if (_shouldSkipSync(item)) return;

    final active = await getActiveServices();
    if (active.isEmpty) return;

    final resolvedIds = await _resolveIds(item);

    for (final service in active) {
      try {
        await service.scrobbleStart(
          item,
          episode,
          progress,
          resolvedIds: resolvedIds,
        );
      } catch (e) {
        // Ignore failure
      }
    }
  }

  /// Scrobble pause event
  Future<void> scrobblePause(
    MultimediaItem item,
    Episode? episode,
    double progress,
  ) async {
    if (_shouldSkipSync(item)) return;

    final active = await getActiveServices();
    if (active.isEmpty) return;

    final resolvedIds = await _resolveIds(item);

    for (final service in active) {
      try {
        await service.scrobblePause(
          item,
          episode,
          progress,
          resolvedIds: resolvedIds,
        );
      } catch (e) {
        // Ignore failure
      }
    }
  }

  /// Scrobble stop event
  Future<void> scrobbleStop(
    MultimediaItem item,
    Episode? episode,
    double progress,
  ) async {
    if (_shouldSkipSync(item)) return;

    final active = await getActiveServices();
    if (active.isEmpty) return;

    final resolvedIds = await _resolveIds(item);

    for (final service in active) {
      try {
        await service.scrobbleStop(
          item,
          episode,
          progress,
          resolvedIds: resolvedIds,
        );
      } catch (e) {
        // Ignore failure
      }
    }
  }

  /// Add item to "Plan to Watch" across all active services
  Future<void> addToPlanToWatch(MultimediaItem item) async {
    if (_shouldSkipSync(item)) return;

    final active = await getActiveServices();
    if (active.isEmpty) return;

    final resolvedIds = await _resolveIds(item);

    for (final service in active) {
      try {
        await service.addToPlanToWatch(item, resolvedIds: resolvedIds);
      } catch (e) {
        // Ignore failure
      }
    }
  }

  /// Remove playback progress item from services that support it
  Future<bool> removePlaybackProgress(SyncProgressItem item) async {
    if (item.id == null) return false;
    final active = await getActiveServices();
    bool success = false;
    for (final service in active) {
      try {
        final removed = await service.removePlaybackProgress(
          item.id.toString(),
        );
        if (removed) success = true;
      } catch (e) {
        // Ignore failure
      }
    }
    return success;
  }
}

@riverpod
SyncManager syncManager(Ref ref) {
  return SyncManager([
    ref.watch(aniListServiceProvider),
    ref.watch(malServiceProvider),
  ]);
}

@riverpod
Future<List<SyncProgressItem>> syncedProgress(Ref ref) async {
  final manager = ref.watch(syncManagerProvider);
  final storage = ref.watch(historyRepositoryProvider);

  final activeServices = await manager.getActiveServices();
  if (activeServices.isEmpty) return [];

  final List<SyncProgressItem> syncedItems = [];

  for (final service in activeServices) {
    try {
      final items = await service.pullPlaybackProgress();
      syncedItems.addAll(items);
    } catch (e) {
      talker.error('Failed to pull progress from ${service.name}', e);
    }
  }

  if (syncedItems.isEmpty) return [];

  final localHistory = storage.getWatchHistory();

  final filteredItems = syncedItems.where((syncItem) {
    final localMatch = localHistory.firstWhere(
      (local) {
        final localTmdb = local.item.tmdbId?.toString();
        final localImdb = local.item.imdbId;

        if (syncItem.tmdbId != null && localTmdb == syncItem.tmdbId) {
          return true;
        }
        if (syncItem.imdbId != null && localImdb == syncItem.imdbId) {
          return true;
        }
        if (local.item.title.toLowerCase() == syncItem.title.toLowerCase()) {
          return true;
        }

        return false;
      },
      orElse: () => HistoryItem(
        item: MultimediaItem(title: '', url: '', posterUrl: ''),
        position: 0,
        duration: 0,
        timestamp: 0,
      ),
    );

    if (localMatch.item.url.isEmpty) return true;

    final localDate = DateTime.fromMillisecondsSinceEpoch(localMatch.timestamp);
    if (localDate.isBefore(syncItem.pausedAt)) {
      final newPos = localMatch.duration > 0
          ? (localMatch.duration * syncItem.progressPercentage / 100).round()
          : 0;
      // Defer the cross-provider write to the next event-loop turn so this
      // provider's build finishes before watchHistoryProvider is notified.
      // Using Future<void>.delayed(Duration.zero) keeps us off the microtask
      // queue — a microtask scheduled from inside a provider's build runs
      // before the build completes, which can re-enter the same provider.
      Future<void>.delayed(Duration.zero, () {
        ref
            .read(watchHistoryProvider.notifier)
            .updateHistoryItemTimestampAndPosition(
              localMatch,
              syncItem.pausedAt.millisecondsSinceEpoch,
              newPos,
            );
      });
    }

    return false;
  }).toList();

  final Map<String, SyncProgressItem> uniqueItems = {};
  for (final item in filteredItems) {
    final key = item.tmdbId ?? item.imdbId ?? item.title;
    if (!uniqueItems.containsKey(key) ||
        item.pausedAt.isAfter(uniqueItems[key]!.pausedAt)) {
      uniqueItems[key] = item;
    }
  }

  final result = uniqueItems.values.toList();
  result.sort((a, b) => b.pausedAt.compareTo(a.pausedAt));

  return result;

}
