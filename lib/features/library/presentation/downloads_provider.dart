import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/services/download_concurrency.dart';
import '../../../core/services/download_service.dart';
import '../../../core/utils/download_cleanup.dart';

part 'downloads_provider.g.dart';

class DownloadItem {
  final Task task;
  final TaskStatus status;
  final double progress;
  final MultimediaItem item;
  final Episode? episode;
  final int timestamp;

  DownloadItem({
    required this.task,
    required this.status,
    required this.progress,
    required this.item,
    this.episode,
    required this.timestamp,
  });

  String get id => task.taskId;
}

bool downloadsPointAtSameTarget(DownloadItem a, DownloadItem b) {
  if (identical(a, b) || a.id == b.id) return true;
  final trackA = downloadTrackingUrl(a.task);
  final trackB = downloadTrackingUrl(b.task);
  if (trackA.isNotEmpty && trackA == trackB) return true;
  final episodeA = a.episode?.url.trim() ?? '';
  final episodeB = b.episode?.url.trim() ?? '';
  if (episodeA.isNotEmpty && episodeA == episodeB) return true;
  if (trackA.isNotEmpty && trackA == episodeB) return true;
  if (trackB.isNotEmpty && trackB == episodeA) return true;
  final fileA = downloadTaskFileKey(a.task);
  final fileB = downloadTaskFileKey(b.task);
  return fileA.isNotEmpty && fileA == fileB;
}

int _statusRank(TaskStatus status) {
  switch (status) {
    case TaskStatus.running:
      return 0;
    case TaskStatus.enqueued:
      return 1;
    case TaskStatus.waitingToRetry:
      return 2;
    case TaskStatus.paused:
      return 3;
    case TaskStatus.complete:
      return 4;
    default:
      return 5;
  }
}

int _keepScore(DownloadItem a, DownloadItem b) {
  final rank = _statusRank(a.status).compareTo(_statusRank(b.status));
  if (rank != 0) return rank;
  return b.timestamp.compareTo(a.timestamp);
}

List<List<DownloadItem>> groupDownloadsByEpisodeOrFile(
  List<DownloadItem> items,
) {
  if (items.isEmpty) return const [];
  final parent = List<int>.generate(items.length, (i) => i);
  int find(int i) {
    var current = i;
    while (parent[current] != current) {
      parent[current] = parent[parent[current]];
      current = parent[current];
    }
    return current;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootA] = rootB;
  }

  final byTracking = <String, int>{};
  final byFile = <String, int>{};
  void unionKey(Map<String, int> map, String key, int i) {
    if (key.isEmpty) return;
    final previous = map[key];
    if (previous != null) {
      union(i, previous);
    } else {
      map[key] = i;
    }
  }

  for (var i = 0; i < items.length; i++) {
    unionKey(byTracking, downloadTrackingUrl(items[i].task), i);
    unionKey(byTracking, items[i].episode?.url.trim() ?? '', i);
    unionKey(byFile, downloadTaskFileKey(items[i].task), i);
  }

  final groups = <int, List<DownloadItem>>{};
  for (var i = 0; i < items.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(items[i]);
  }
  return groups.values.toList();
}

class CollapsedDownloads {
  const CollapsedDownloads({
    required this.visible,
    required this.extraCompleteRecords,
  });

  /// One row per episode / file, newest active preferred over complete.
  final List<DownloadItem> visible;

  /// Extra complete FileDownloader records to drop from DB+metadata only.
  final List<DownloadItem> extraCompleteRecords;
}

/// Keep one UI row per episode/file. Extra complete records are listed so
/// callers can delete them from the downloader DB without touching the file.
CollapsedDownloads collapseDuplicateDownloads(List<DownloadItem> items) {
  if (items.length <= 1) {
    return CollapsedDownloads(visible: items, extraCompleteRecords: const []);
  }

  final visible = <DownloadItem>[];
  final extraComplete = <DownloadItem>[];
  final keptIds = <String>{};

  for (final group in groupDownloadsByEpisodeOrFile(items)) {
    if (group.length == 1) {
      visible.add(group.first);
      keptIds.add(group.first.id);
      continue;
    }
    final ranked = List<DownloadItem>.from(group)..sort(_keepScore);
    final kept = ranked.first;
    visible.add(kept);
    keptIds.add(kept.id);
    for (final extra in ranked.skip(1)) {
      if (extra.status == TaskStatus.complete) {
        extraComplete.add(extra);
      }
    }
  }

  visible.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return CollapsedDownloads(
    visible: visible,
    extraCompleteRecords: extraComplete
        .where((item) => !keptIds.contains(item.id))
        .toList(),
  );
}

@Riverpod(keepAlive: true)
class DownloadsNotifier extends _$DownloadsNotifier {
  @override
  Future<List<DownloadItem>> build() async {
    // Listen to updates from DownloadService (broadcast) instead of FileDownloader (single)
    final subscription = ref.read(downloadServiceProvider).updates.listen((
      update,
    ) {
      _handleUpdate(update);
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    return _refreshList();
  }

  Future<List<DownloadItem>> _refreshList() async {
    final records = await FileDownloader().database.allRecords();
    final storage = ref.read(storageServiceProvider);

    final List<DownloadItem> items = [];

    for (final record in records) {
      // Skip non-download tasks and cancelled ones. Failed downloads are kept
      // and shown as paused so the user can resume instead of starting over.
      if (record.task is! DownloadTask) continue;
      if (record.status == TaskStatus.canceled) {
        continue;
      }

      var status = record.status;
      var progress = record.progress;
      if (status == TaskStatus.failed || status == TaskStatus.notFound) {
        status = TaskStatus.paused;
        if (progress < 0 || progress > 1) progress = 0.0;
        unawaited(
          FileDownloader().database.updateRecord(
            TaskRecord(
              record.task,
              TaskStatus.paused,
              progress,
              record.expectedFileSize,
            ),
          ),
        );
      } else if (progress < 0 || progress > 1) {
        // Sentinel progress values from the downloader (failed/paused markers)
        progress = status == TaskStatus.complete ? 1.0 : 0.0;
      }

      final metadata = await storage.getDownloadMetadata(record.task.taskId);
      if (metadata == null) continue;

      items.add(
        DownloadItem(
          task: record.task,
          status: displayDownloadStatus(
            persisted: status,
            queueWaiting: isQueueWaitingMetadata(metadata),
          ),
          progress: progress,
          item: MultimediaItem.fromJson(
            Map<String, dynamic>.from(metadata['item'] as Map),
          ),
          episode: metadata['episode'] != null
              ? Episode.fromJson(
                  Map<String, dynamic>.from(metadata['episode'] as Map),
                )
              : null,
          timestamp: (metadata['timestamp'] as int?) ?? 0,
        ),
      );
    }

    // Sort by timestamp descending
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final collapsed = collapseDuplicateDownloads(items);
    for (final extra in collapsed.extraCompleteRecords) {
      await FileDownloader().database.deleteRecordWithId(extra.task.taskId);
      await storage.removeDownloadMetadata(extra.task.taskId);
    }
    return collapsed.visible;
  }

  Future<void> _handleUpdate(TaskUpdate update) async {
    if (state.value == null) return;

    final List<DownloadItem> currentList = state.value!;
    final index = currentList.indexWhere(
      (item) => item.id == update.task.taskId,
    );

    if (index != -1) {
      final existing = currentList[index];
      double newProgress = existing.progress;
      TaskStatus newStatus = existing.status;

      if (update is TaskProgressUpdate) {
        if (update.progress >= 0 && update.progress <= 1) {
          newProgress = update.progress;
        }
      } else if (update is TaskStatusUpdate) {
        newStatus = update.status;
      }

      if (newStatus == TaskStatus.canceled) {
        // Remove from list only on explicit user cancel.
        final newList = List<DownloadItem>.from(currentList)..removeAt(index);
        state = AsyncData(newList);
      } else {
        // Failures are remapped to paused by DownloadService before broadcast,
        // but keep this guard so a raw failed event can never wipe the row.
        if (newStatus == TaskStatus.failed ||
            newStatus == TaskStatus.notFound) {
          newStatus = TaskStatus.paused;
        }
        final updatedItem = DownloadItem(
          task: existing.task,
          status: newStatus,
          progress: newProgress.clamp(0.0, 1.0),
          item: existing.item,
          episode: existing.episode,
          timestamp: existing.timestamp,
        );

        final newList = List<DownloadItem>.from(currentList);
        newList[index] = updatedItem;
        state = AsyncData(newList);
      }
    } else {
      // If not in state, it might be a new download. Refresh to get metadata.
      state = AsyncData(await _refreshList());
    }
  }

  Future<void> removeDownload(DownloadItem item) async {
    await removeDownloads([item]);
  }

  Future<void> removeDownloads(List<DownloadItem> items) async {
    if (items.isEmpty) return;
    final downloadService = ref.read(downloadServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final current = List<DownloadItem>.from(state.value ?? items);

    final resolvedById = <String, File>{};
    Future<File?> resolveFile(DownloadItem item) async {
      final cached = resolvedById[item.id];
      if (cached != null) return cached;
      final file = await downloadService.resolveDownloadedFile(
        item.task,
        item.item,
        episode: item.episode,
      );
      if (file != null) resolvedById[item.id] = file;
      return file;
    }

    for (final item in items) {
      await resolveFile(item);
    }

    final toRemove = <String, DownloadItem>{};
    for (final requested in items) {
      final requestedFile = await resolveFile(requested);
      String? requestedTaskPath;
      try {
        requestedTaskPath = await requested.task.filePath();
      } catch (_) {}
      for (final candidate in current) {
        if (toRemove.containsKey(candidate.id)) continue;
        if (downloadsPointAtSameTarget(requested, candidate)) {
          toRemove[candidate.id] = candidate;
          continue;
        }
        try {
          final candidatePath = await candidate.task.filePath();
          if (candidatePath.isNotEmpty &&
              (candidatePath == requestedFile?.path ||
                  candidatePath == requestedTaskPath)) {
            toRemove[candidate.id] = candidate;
          }
        } catch (_) {}
      }
    }

    for (final item in toRemove.values) {
      await resolveFile(item);
    }

    final deletedPaths = <String>{};
    for (final file in resolvedById.values) {
      if (!deletedPaths.add(file.path)) continue;
      await downloadService.deleteDownloadedFile(file);
    }

    final droppedIds = <String>{};
    for (final item in toRemove.values) {
      final file = resolvedById[item.id];
      var stillExists = false;
      if (file != null) {
        try {
          stillExists = await file.exists();
        } catch (_) {
          stillExists = true;
        }
      }
      if (stillExists) continue;

      if (shouldCancelDownload(item.status)) {
        final trackingUrl = downloadTrackingUrl(item.task);
        await downloadService.cancelDownload(item.task.taskId, trackingUrl);
      }
      await FileDownloader().database.deleteRecordWithId(item.task.taskId);
      await storage.removeDownloadMetadata(item.task.taskId);
      droppedIds.add(item.id);
    }

    if (state.value != null && droppedIds.isNotEmpty) {
      state = AsyncData(
        state.value!.where((i) => !droppedIds.contains(i.id)).toList(),
      );
    }
  }

  Future<void> pauseDownload(String taskId) async {
    await ref.read(downloadServiceProvider).pauseDownload(taskId);
  }

  Future<void> resumeDownload(String taskId) async {
    await ref.read(downloadServiceProvider).resumeDownload(taskId);
  }
}
