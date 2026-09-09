import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

bool isNativeSingleDownloadTask(Task task) =>
    task is DownloadTask && task is! ParallelDownloadTask;

/// Anime episodes are explicit user downloads and frequently exceed Android's
/// short background-worker window. These hints let background_downloader 9.6
/// choose UIDT/high priority where available and preserve pause resilience.
Set<TransferHint> animeDownloadTransferHints({required int expectedBytes}) =>
    <TransferHint>{TransferHint.userInitiated, TransferHint.largeFile};

/// Execution boundary used by DownloadService.
///
/// Logical job state, queue order, resource validation and multipart assembly
/// live above this interface. A transport only owns one concrete transfer and
/// reports what the underlying executor is doing.
abstract interface class DownloadTransport {
  bool owns(String taskId);

  Future<bool> start(DownloadTask task);

  Future<bool> pause(DownloadTask task);

  Future<bool> resume(DownloadTask task);

  Future<bool> cancel(DownloadTask task);

  Stream<TaskUpdate> updatesFor(String taskId);

  Future<void> dispose();
}

/// background_downloader 9.6 Transfer-backed executor for normal one-file
/// downloads.
///
/// Multipart parents deliberately do not pass through this transport: their
/// immutable range children and manifests remain owned by
/// PersistentParallelDownload. Keeping that boundary avoids accidentally
/// turning a restored multipart episode into one raw URLSession request.
class NativeSingleDownloadTransport implements DownloadTransport {
  NativeSingleDownloadTransport({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;
  final Map<String, Transfer> _handles = <String, Transfer>{};
  final Map<String, StreamController<TaskUpdate>> _controllers =
      <String, StreamController<TaskUpdate>>{};
  final Map<String, StreamSubscription<TaskUpdate>> _subscriptions =
      <String, StreamSubscription<TaskUpdate>>{};

  /// Recreate handles for persisted normal downloads without enqueueing a
  /// duplicate task. Failed records are not restarted automatically; the
  /// higher-level resume policy first verifies durable bytes/fingerprint.
  Future<List<DownloadTask>> rehydrate({String? group}) async {
    final transfers = await _downloader.transfers.rehydrateFromDatabase(
      group: group,
    );
    final tasks = <DownloadTask>[];
    for (final transfer in transfers) {
      final task = transfer.task;
      if (!isNativeSingleDownloadTask(task)) continue;
      _attach(transfer);
      tasks.add(task as DownloadTask);
    }
    return tasks;
  }

  @override
  bool owns(String taskId) =>
      _handles.containsKey(taskId) || _downloader.transfers.forId(taskId) != null;

  Transfer? handleFor(String taskId) =>
      _handles[taskId] ?? _downloader.transfers.forId(taskId);

  @override
  Future<bool> start(DownloadTask task) async {
    if (!isNativeSingleDownloadTask(task)) return false;
    final existing = handleFor(task.taskId);
    if (existing != null) {
      _attach(existing);
      return existing.status != TaskStatus.canceled &&
          existing.status != TaskStatus.notFound;
    }

    try {
      final transfer = await _downloader.transfers.getOrStart(
        task,
        matchBy: (existingTask) => existingTask.taskId == task.taskId,
        // Never let getOrStart turn a failed record into an implicit fresh GET.
        // AnimeWitcher decides native resume -> verified partial -> fresh start.
        reEnqueueIfFailed: false,
      );
      _attach(transfer);
      return transfer.status != TaskStatus.failed &&
          transfer.status != TaskStatus.canceled &&
          transfer.status != TaskStatus.notFound;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> pause(DownloadTask task) async {
    if (!isNativeSingleDownloadTask(task)) return false;
    final transfer = handleFor(task.taskId);
    if (transfer == null) return _downloader.pause(task);
    _attach(transfer);
    try {
      return await transfer.pause();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> resume(DownloadTask task) async {
    if (!isNativeSingleDownloadTask(task)) return false;
    try {
      // FileDownloader.resume preserves the old strict contract: false means
      // native resume was unavailable. Transfer.resume in 9.6 may intentionally
      // fall back to re-enqueueing, which AnimeWitcher must never permit while
      // verified partial bytes exist.
      final resumed = await _downloader.resume(task);
      if (!resumed) return false;
      final transfer = await _downloader.transfers.getOrStart(
        task,
        matchBy: (existingTask) => existingTask.taskId == task.taskId,
        reEnqueueIfFailed: false,
      );
      _attach(transfer);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> cancel(DownloadTask task) async {
    if (!isNativeSingleDownloadTask(task)) return false;
    final transfer = handleFor(task.taskId);
    try {
      final canceled = transfer != null
          ? await transfer.cancel()
          : await _downloader.cancelTaskWithId(task.taskId);
      _detach(task.taskId);
      return canceled;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<TaskUpdate> updatesFor(String taskId) {
    final controller = _controllers.putIfAbsent(
      taskId,
      () => StreamController<TaskUpdate>.broadcast(),
    );
    final transfer = handleFor(taskId);
    if (transfer != null) _attach(transfer);
    return controller.stream;
  }

  void _attach(Transfer transfer) {
    final id = transfer.taskId;
    if (_handles[id] == transfer && _subscriptions.containsKey(id)) return;
    unawaited(_subscriptions.remove(id)?.cancel());
    _handles[id] = transfer;
    final controller = _controllers.putIfAbsent(
      id,
      () => StreamController<TaskUpdate>.broadcast(),
    );
    _subscriptions[id] = transfer.updates.listen(
      (update) {
        if (!controller.isClosed) controller.add(update);
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      },
    );
  }

  void _detach(String taskId) {
    unawaited(_subscriptions.remove(taskId)?.cancel());
    _handles.remove(taskId);
    _downloader.transfers.remove(taskId, dispose: true);
  }

  @override
  Future<void> dispose() async {
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final controllers = _controllers.values.toList(growable: false);
    _controllers.clear();
    for (final controller in controllers) {
      await controller.close();
    }
    // Dispose handles only; this does not cancel the native tasks.
    for (final id in _handles.keys.toList(growable: false)) {
      _downloader.transfers.remove(id, dispose: true);
    }
    _handles.clear();
  }
}
