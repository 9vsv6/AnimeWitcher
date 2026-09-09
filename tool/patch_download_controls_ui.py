from pathlib import Path

service_path = Path('lib/core/services/download_service.dart')
provider_path = Path('lib/features/library/presentation/downloads_provider.dart')
service = service_path.read_text()
provider = provider_path.read_text()

old_notifier = '''@Riverpod(keepAlive: true)
class DownloadProgressNotifier extends _$DownloadProgressNotifier {
  @override
  Map<String, DownloadProgressData> build() => {};

  void update(String url, DownloadProgressData data) {
    state = {...state, url: data};
  }

  void remove(String url) {
    state = {...state}..remove(url);
  }
}
'''
new_notifier = '''@Riverpod(keepAlive: true)
class DownloadProgressNotifier extends _$DownloadProgressNotifier {
  static const Duration _uiSampleInterval = Duration(seconds: 1);
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, DownloadProgressData> _pending =
      <String, DownloadProgressData>{};
  final Map<String, DateTime> _lastPublished = <String, DateTime>{};

  @override
  Map<String, DownloadProgressData> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _pending.clear();
      _lastPublished.clear();
    });
    return {};
  }

  void update(String url, DownloadProgressData data) {
    final previous = state[url];
    final statusChanged = previous == null || previous.status != data.status;

    // Commands and lifecycle changes must feel instantaneous. Only repeated
    // running metrics are sampled: downloaded MB, percentage, speed and ETA
    // then move together once per second instead of repainting dozens of times.
    if (statusChanged ||
        data.status != TaskStatus.running ||
        data.progress >= 1.0) {
      _publishNow(url, data);
      return;
    }

    _pending[url] = data;
    final last = _lastPublished[url];
    if (last == null) {
      _publishNow(url, data);
      return;
    }

    final elapsed = DateTime.now().difference(last);
    if (elapsed >= _uiSampleInterval) {
      _publishPending(url);
      return;
    }

    _timers[url] ??= Timer(_uiSampleInterval - elapsed, () {
      _timers.remove(url);
      _publishPending(url);
    });
  }

  void _publishNow(String url, DownloadProgressData data) {
    _timers.remove(url)?.cancel();
    _pending.remove(url);
    _lastPublished[url] = DateTime.now();
    state = {...state, url: data};
  }

  void _publishPending(String url) {
    final data = _pending.remove(url);
    if (data == null) return;
    _lastPublished[url] = DateTime.now();
    state = {...state, url: data};
  }

  void remove(String url) {
    _timers.remove(url)?.cancel();
    _pending.remove(url);
    _lastPublished.remove(url);
    state = {...state}..remove(url);
  }
}
'''
if old_notifier not in service:
    raise SystemExit('DownloadProgressNotifier block not found')
service = service.replace(old_notifier, new_notifier, 1)

old_cancel_start = '''  Future<void> cancelDownload(
    String taskId,
    String trackingUrl, {
    bool notifyContinuedProcessing = true,
  }) async {
    _cancellingUrls.add(trackingUrl);
    await _rangeTransfers.stop(taskId);
    try {
'''
new_cancel_start = '''  Future<void> cancelDownload(
    String taskId,
    String trackingUrl, {
    bool notifyContinuedProcessing = true,
  }) async {
    // Tombstone the logical download before waiting on native IO. This makes a
    // user delete immediate in every UI and prevents late URLSession callbacks
    // from resurrecting the row while the OS finishes canceling its worker.
    _cancellingUrls.add(trackingUrl);
    _queueWaitingIds.remove(taskId);
    _waitingPayloads.remove(taskId);
    _forgetSessionTask(taskId);
    _userPausedIds.remove(taskId);
    _dequeuingPausedIds.remove(taskId);
    _ref.read(activeDownloadsProvider.notifier).remove(trackingUrl);
    _ref.read(downloadProgressProvider.notifier).remove(trackingUrl);
    _ref.read(downloadChunkProgressProvider.notifier).remove(taskId);

    await _rangeTransfers.stop(taskId);
    try {
'''
if old_cancel_start not in service:
    raise SystemExit('cancelDownload start not found')
service = service.replace(old_cancel_start, new_cancel_start, 1)

old_pause_start = '''  Future<void> pauseDownload(String taskId) async {
    await _rangeTransfers.stop(taskId);
    await _serializeQueue(() async {
      _userPausedIds.add(taskId);
'''
new_pause_start = '''  Future<void> pauseDownload(String taskId) async {
    // Fence callbacks immediately on tap. Native pause/resume-data settlement
    // can take a moment on iOS, but progress events must not visually undo the
    // user's pause while that acknowledgement is in flight.
    _userPausedIds.add(taskId);
    await _rangeTransfers.stop(taskId);
    await _serializeQueue(() async {
      _userPausedIds.add(taskId);
'''
if old_pause_start not in service:
    raise SystemExit('pauseDownload start not found')
service = service.replace(old_pause_start, new_pause_start, 1)

old_class = '''@Riverpod(keepAlive: true)
class DownloadsNotifier extends _$DownloadsNotifier {
  @override
'''
new_class = '''@Riverpod(keepAlive: true)
class DownloadsNotifier extends _$DownloadsNotifier {
  static const Duration _listProgressUiInterval = Duration(seconds: 1);
  final Set<String> _deletingIds = <String>{};
  final Map<String, DateTime> _lastProgressUiUpdate = <String, DateTime>{};

  @override
'''
if old_class not in provider:
    raise SystemExit('DownloadsNotifier declaration not found')
provider = provider.replace(old_class, new_class, 1)

old_refresh_sort = '''    // FIFO: oldest first.
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
'''
new_refresh_sort = '''    // A user-deleted task is a session tombstone until its native cleanup has
    // fully settled. Never let an unrelated refresh briefly resurrect it.
    items.removeWhere((item) => _deletingIds.contains(item.id));

    // FIFO: oldest first.
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
'''
if old_refresh_sort not in provider:
    raise SystemExit('refresh sort marker not found')
provider = provider.replace(old_refresh_sort, new_refresh_sort, 1)

old_handle_start = '''  Future<void> _handleUpdate(TaskUpdate update) async {
    if (state.value == null) return;

    final List<DownloadItem> currentList = state.value!;
'''
new_handle_start = '''  Future<void> _handleUpdate(TaskUpdate update) async {
    if (state.value == null || _deletingIds.contains(update.task.taskId)) return;

    // DownloadService already exposes sampled live metrics. Keep the durable
    // list snapshot to the same one-second cadence so the whole downloads page
    // does not rebuild for every native didWriteData packet.
    if (update is TaskProgressUpdate &&
        update.progress >= 0 &&
        update.progress < 1) {
      final now = DateTime.now();
      final last = _lastProgressUiUpdate[update.task.taskId];
      if (last != null && now.difference(last) < _listProgressUiInterval) {
        return;
      }
      _lastProgressUiUpdate[update.task.taskId] = now;
    }

    final List<DownloadItem> currentList = state.value!;
'''
if old_handle_start not in provider:
    raise SystemExit('_handleUpdate start not found')
provider = provider.replace(old_handle_start, new_handle_start, 1)

old_status_branch = '''      } else if (update is TaskStatusUpdate) {
        newStatus = update.status;
      }
'''
new_status_branch = '''      } else if (update is TaskStatusUpdate) {
        newStatus = update.status;
        if (update.status == TaskStatus.complete) newProgress = 1.0;
      }
'''
if old_status_branch not in provider:
    raise SystemExit('status branch not found')
provider = provider.replace(old_status_branch, new_status_branch, 1)

start = provider.index('  Future<void> removeDownload(DownloadItem item) async {')
end = provider.index('\n}', start)
old_tail = provider[start:end]
new_tail = '''  Future<void> removeDownload(DownloadItem item) async {
    await removeDownloads([item]);
  }

  Future<void> removeDownloads(List<DownloadItem> items) async {
    if (items.isEmpty) return;
    final downloadService = ref.read(downloadServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final current = List<DownloadItem>.from(state.value ?? items);

    // Resolve the logical rows synchronously first and hide them before any
    // filesystem/native await. The old order deleted the file first and, when
    // an active worker still owned it, `stillExists` caused us to skip cancel
    // entirely — leaving a stuck row that could never disappear.
    final toRemove = <String, DownloadItem>{};
    for (final requested in items) {
      toRemove[requested.id] = requested;
      for (final candidate in current) {
        if (downloadsPointAtSameTarget(requested, candidate)) {
          toRemove[candidate.id] = candidate;
        }
      }
    }

    final droppedIds = toRemove.keys.toSet();
    _deletingIds.addAll(droppedIds);
    for (final id in droppedIds) {
      _lastProgressUiUpdate.remove(id);
    }

    if (state.value != null) {
      state = AsyncData(
        state.value!.where((item) => !droppedIds.contains(item.id)).toList(),
      );
    }

    for (final item in toRemove.values) {
      final trackingUrl = downloadTrackingUrl(item.task);
      ref.read(activeDownloadsProvider.notifier).remove(trackingUrl);
      ref.read(downloadProgressProvider.notifier).remove(trackingUrl);
      ref.read(downloadChunkProgressProvider.notifier).remove(item.id);
    }

    // Capture possible final/partial paths before cancel removes metadata. This
    // is cleanup-only work: the card is already gone and controls are free.
    final filesToDelete = <String, File>{};
    for (final item in toRemove.values) {
      try {
        final taskPath = await item.task.filePath();
        if (taskPath.isNotEmpty) filesToDelete[taskPath] = File(taskPath);
      } catch (_) {}
      try {
        final resolved = await downloadService
            .resolveDownloadedFile(
              item.task,
              item.item,
              episode: item.episode,
            )
            .timeout(const Duration(milliseconds: 750));
        if (resolved != null) filesToDelete[resolved.path] = resolved;
      } catch (_) {}
    }

    // Stop ownership and tombstone DB/Hive first. Every step is best-effort so
    // one stale URLSession worker can never prevent the logical delete.
    for (final item in toRemove.values) {
      final trackingUrl = downloadTrackingUrl(item.task);
      if (shouldCancelDownload(item.status)) {
        try {
          await downloadService
              .cancelDownload(item.task.taskId, trackingUrl)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          // Timeout only releases the UI cleanup path; cancelDownload continues
          // settling its native Future in the background.
        }
      }
      try {
        await FileDownloader().database.deleteRecordWithId(item.task.taskId);
      } catch (_) {}
      try {
        await storage.removeDownloadMetadata(item.task.taskId);
      } catch (_) {}
      try {
        await deleteDownloadedEpisodeArtwork(item.id);
      } catch (_) {}
    }

    final deletedPaths = <String>{};
    for (final file in filesToDelete.values) {
      if (!deletedPaths.add(file.path)) continue;
      try {
        await downloadService
            .deleteDownloadedFile(file)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        try {
          if (await file.exists()) await file.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  void _setOptimisticStatus(String taskId, TaskStatus status) {
    final current = state.value;
    if (current == null) return;
    final index = current.indexWhere((item) => item.id == taskId);
    if (index < 0) return;

    final existing = current[index];
    final trackingUrl = downloadTrackingUrl(existing.task);
    final live = ref.read(downloadProgressProvider)[trackingUrl];
    final progress = live?.progress ?? existing.progress;
    final updated = DownloadItem(
      task: existing.task,
      status: status,
      progress: progress,
      item: existing.item,
      episode: existing.episode,
      timestamp: existing.timestamp,
    );
    final next = List<DownloadItem>.from(current)..[index] = updated;
    state = AsyncData(next);

    ref
        .read(downloadProgressProvider.notifier)
        .update(
          trackingUrl,
          DownloadProgressData(
            taskId: taskId,
            progress: progress,
            networkSpeed: status == TaskStatus.running
                ? (live?.networkSpeed ?? 0)
                : 0,
            timeRemaining: status == TaskStatus.running
                ? (live?.timeRemaining ?? Duration.zero)
                : Duration.zero,
            totalSize: live?.totalSize ?? -1,
            status: status,
          ),
        );
  }

  Future<void> pauseDownload(String taskId) async {
    _setOptimisticStatus(taskId, TaskStatus.paused);
    try {
      await ref.read(downloadServiceProvider).pauseDownload(taskId);
    } catch (_) {
      state = AsyncData(await _refreshList());
    }
  }

  Future<void> resumeDownload(String taskId) async {
    // Queue state is the only universally correct immediate state: if a slot is
    // free DownloadService will replace it with running almost immediately;
    // otherwise the user sees في الانتظار instead of a dead play button.
    _setOptimisticStatus(taskId, TaskStatus.enqueued);
    try {
      await ref.read(downloadServiceProvider).resumeDownload(taskId);
    } catch (_) {
      state = AsyncData(await _refreshList());
    }
  }
'''
provider = provider[:start] + new_tail + provider[end:]

service_path.write_text(service)
provider_path.write_text(provider)

# Structural regression tests keep the two user-visible invariants explicit.
test = Path('test/core/services/download_ui_responsiveness_test.dart')
test.write_text(r'''import 'dart:io';

import 'package:animewitcher/core/services/download_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadProgressData sample(double progress, double speed) =>
    DownloadProgressData(
      taskId: 'task',
      progress: progress,
      networkSpeed: speed,
      timeRemaining: const Duration(seconds: 20),
      totalSize: 1000,
      status: TaskStatus.running,
    );

void main() {
  test('running download metrics publish at most once per second', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(downloadProgressProvider.notifier);

    notifier.update('url', sample(0.10, 1));
    notifier.update('url', sample(0.20, 2));
    notifier.update('url', sample(0.30, 3));

    expect(container.read(downloadProgressProvider)['url']!.progress, 0.10);
    expect(container.read(downloadProgressProvider)['url']!.networkSpeed, 1);

    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(container.read(downloadProgressProvider)['url']!.progress, 0.30);
    expect(container.read(downloadProgressProvider)['url']!.networkSpeed, 3);
  });

  test('pause status bypasses the one-second running metric throttle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(downloadProgressProvider.notifier);

    notifier.update('url', sample(0.10, 1));
    notifier.update(
      'url',
      DownloadProgressData(
        taskId: 'task',
        progress: 0.10,
        networkSpeed: 0,
        timeRemaining: Duration.zero,
        totalSize: 1000,
        status: TaskStatus.paused,
      ),
    );

    expect(
      container.read(downloadProgressProvider)['url']!.status,
      TaskStatus.paused,
    );
  });

  test('delete hides rows before waiting for native or filesystem cleanup', () {
    final source = File(
      'lib/features/library/presentation/downloads_provider.dart',
    ).readAsStringSync();
    final method = source.substring(source.indexOf('Future<void> removeDownloads'));

    final optimisticState = method.indexOf('state = AsyncData(');
    final nativeCancel = method.indexOf('.cancelDownload(');
    final fileDelete = method.indexOf('.deleteDownloadedFile(file)');

    expect(optimisticState, greaterThanOrEqualTo(0));
    expect(nativeCancel, greaterThan(optimisticState));
    expect(fileDelete, greaterThan(nativeCancel));
    expect(method, contains('_deletingIds.addAll(droppedIds)'));
  });
}
''')

print('Patched download UI throttling and optimistic control handling.')
