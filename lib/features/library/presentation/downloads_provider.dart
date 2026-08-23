import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:skystream/core/storage/storage_service.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/services/download_service.dart';

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
      if (status == TaskStatus.failed) {
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
          status: status,
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
    return items;
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
        // Remove from list if canceled
        final newList = List<DownloadItem>.from(currentList)..removeAt(index);
        state = AsyncData(newList);
      } else {
        // Failures are treated like a user pause so the download stays resumable.
        if (newStatus == TaskStatus.failed) {
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
    await ref
        .read(downloadServiceProvider)
        .cancelDownload(item.task.taskId, item.task.url);
    await FileDownloader().database.deleteRecordWithId(item.task.taskId);
    await ref
        .read(storageServiceProvider)
        .removeDownloadMetadata(item.task.taskId);

    // Also delete file if complete
    if (item.status == TaskStatus.complete) {
      final downloadService = ref.read(downloadServiceProvider);
      final file = await downloadService.getDownloadedFile(
        item.item,
        episode: item.episode,
      );
      if (file != null && await file.exists()) {
        await downloadService.deleteDownloadedFile(file);
      }
    }

    if (state.value != null) {
      state = AsyncData(state.value!.where((i) => i.id != item.id).toList());
    }
  }

  Future<void> removeDownloads(List<DownloadItem> items) async {
    for (final item in items) {
      await ref
          .read(downloadServiceProvider)
          .cancelDownload(item.task.taskId, item.task.url);
      await FileDownloader().database.deleteRecordWithId(item.task.taskId);
      await ref
          .read(storageServiceProvider)
          .removeDownloadMetadata(item.task.taskId);

      // Also delete file if complete
      if (item.status == TaskStatus.complete) {
        final downloadService = ref.read(downloadServiceProvider);
        final file = await downloadService.getDownloadedFile(
          item.item,
          episode: item.episode,
        );
        if (file != null && await file.exists()) {
          await downloadService.deleteDownloadedFile(file);
        }
      }
    }

    if (state.value != null) {
      final idsToRemove = items.map((i) => i.id).toSet();
      state = AsyncData(
        state.value!.where((i) => !idsToRemove.contains(i.id)).toList(),
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
