import 'package:background_downloader/background_downloader.dart';

/// Hive settings key used by official SkyStream and this fork.
const String kDownloadConcurrencyStorageKey = 'download_concurrency';

/// Persisted on download metadata for leftover Dart-parked rows (PR #114)
/// and for kill-recovery of native holding-queue waiters that never reached
/// URLSession. In-app UI still maps this to **في الانتظار...**.
const String kDownloadQueueWaitingMetadataKey = 'queueWaiting';

const int kDownloadConcurrencyMin = 1;
const int kDownloadConcurrencyMax = 5;
const int kDownloadConcurrencyDefault = 1;

int clampDownloadConcurrency(int value) =>
    value.clamp(kDownloadConcurrencyMin, kDownloadConcurrencyMax);

/// Missing or non-numeric storage values fall back to sequential downloads.
int parseDownloadConcurrency(Object? raw) {
  if (raw is int) return clampDownloadConcurrency(raw);
  if (raw is num) return clampDownloadConcurrency(raw.round());
  return kDownloadConcurrencyDefault;
}

/// [Config.holdingQueue] triple: `(maxConcurrent, maxConcurrentByHost, maxConcurrentByGroup)`.
///
/// Host and group are left unconstrained (`null`) so the user's N is the only
/// cap. Official SkyStream copied the docs example `(N, 2, 1)`. AnimeWitcher
/// notifications use group `'downloads'` and episode tasks share the default
/// task group, so a group cap of 1 would force global sequential downloads and
/// ignore the 1–5 setting.
(int, int?, int?) downloadHoldingQueueValue(int maxConcurrent) =>
    (clampDownloadConcurrency(maxConcurrent), null, null);

List<(String, dynamic)> downloadHoldingQueueGlobalConfig(int maxConcurrent) =>
    <(String, dynamic)>[
      (Config.holdingQueue, downloadHoldingQueueValue(maxConcurrent)),
    ];

/// Persists [maxConcurrent] then reconfigures FileDownloader's holding queue.
///
/// Extra episode downloads wait FIFO in the **native** holding queue until a
/// URLSession / WorkManager slot frees. Native `HoldingQueue.advanceQueue`
/// runs from the iOS URLSession delegate even while the Flutter isolate is
/// suspended — unlike a Dart `onComplete` listener.
Future<int> applyDownloadQueueSettings({
  required int maxConcurrent,
  required Future<void> Function(int value) persist,
  required Future<void> Function(List<(String, dynamic)> globalConfig)
  configure,
}) async {
  final n = clampDownloadConcurrency(maxConcurrent);
  await persist(n);
  await configure(downloadHoldingQueueGlobalConfig(n));
  return n;
}

/// True when Hive metadata marks this row as holding-queue waiting.
bool isQueueWaitingMetadata(Map<String, dynamic>? metadata) =>
    metadata?[kDownloadQueueWaitingMetadataKey] == true;

/// Occupied slots are native transfers and native holding-queue waiters.
/// Leftover Dart-parked (`queueWaiting`) and user-paused rows must not count.
bool occupiesDownloadSlot({
  required TaskStatus status,
  bool queueWaiting = false,
}) {
  if (queueWaiting) return false;
  switch (status) {
    case TaskStatus.running:
    case TaskStatus.enqueued:
    case TaskStatus.waitingToRetry:
      return true;
    case TaskStatus.paused:
    case TaskStatus.complete:
    case TaskStatus.canceled:
    case TaskStatus.failed:
    case TaskStatus.notFound:
      return false;
  }
}

/// Waiting rows may be stored paused (legacy Dart park) so the Downloads tab
/// must keep the existing **في الانتظار...** (`enqueued`) label. Native
/// holding-queue waiters are already [TaskStatus.enqueued].
TaskStatus displayDownloadStatus({
  required TaskStatus persisted,
  required bool queueWaiting,
}) {
  if (queueWaiting) return TaskStatus.enqueued;
  return persisted;
}

/// iOS Live Activity / `BGContinuedProcessingTask` is only for a file that
/// is actually transferring. Native holding-queue `enqueued` waiters must
/// not call `start` — that overlay is what Rivera circled ("Downloading 0%").
bool shouldStartDownloadLiveActivity(TaskStatus status) =>
    status == TaskStatus.running;

/// Overflow episodes always go to the native holding queue (`FileDownloader`
/// enqueue). Dart must not park-without-enqueue: the Flutter isolate is
/// suspended in the iOS background, so a Dart `onComplete` promoter never
/// runs until the user opens the app.
bool shouldEnqueueOverflowToNativeHoldingQueue() => true;

/// After a process kill, iOS `HoldingQueue` memory is gone. URLSession tasks
/// already submitted can continue; waiters that never reached URLSession must
/// be re-enqueued. Never auto-resume a user-paused row.
bool shouldReenqueueWaitingAfterProcessKill({
  required TaskStatus persisted,
  required bool queueWaiting,
  required bool userPaused,
  required bool stillInNativeQueue,
}) {
  if (stillInNativeQueue || userPaused) return false;
  if (queueWaiting) return true;
  return persisted == TaskStatus.enqueued;
}

/// iOS concurrency=1, two episodes, app backgrounded (home/lock/switch, not
/// necessarily killed): ep1 is the only Live Activity; ep2 is native-enqueued
/// (في الانتظار) until URLSession finishes ep1 and `HoldingQueue` promotes it.
bool waitingEpisodeMayStartLiveActivityWhileQueued() => false;

enum DownloadAdmission { enqueueToNativeHoldingQueue }

/// Every user-started episode is OS-enqueued. Native holding queue owns the N
/// cap; Dart does not park overflow out of the OS queue.
DownloadAdmission admitDownload({
  required int occupiedSlots,
  required int maxConcurrent,
}) {
  // Native HoldingQueue enforces N. occupiedSlots is kept so callers can log
  // how many URLSession tasks are already in flight.
  assert(occupiedSlots >= 0);
  clampDownloadConcurrency(maxConcurrent);
  return DownloadAdmission.enqueueToNativeHoldingQueue;
}

class DownloadQueueEntry {
  const DownloadQueueEntry({
    required this.taskId,
    required this.status,
    required this.timestamp,
    this.queueWaiting = false,
  });

  final String taskId;
  final TaskStatus status;
  final bool queueWaiting;
  final int timestamp;
}

class DownloadQueuePlan {
  const DownloadQueuePlan({
    required this.maxConcurrent,
    required this.occupiedCount,
    required this.waitingFifoIds,
    required this.idsToPark,
    required this.idsToPromote,
  });

  final int maxConcurrent;
  final int occupiedCount;
  final List<String> waitingFifoIds;
  final List<String> idsToPark;
  final List<String> idsToPromote;

  int get freeSlots => (maxConcurrent - occupiedCount).clamp(0, maxConcurrent);
}

/// FIFO re-enqueue of leftover Dart-parked waiters. Occupying URLSession
/// tasks are never detached: pulling them off native re-breaks background
/// promotion when the Flutter isolate is suspended.
DownloadQueuePlan planDownloadQueue({
  required int maxConcurrent,
  required Iterable<DownloadQueueEntry> entries,
}) {
  final n = clampDownloadConcurrency(maxConcurrent);
  final occupying = entries
      .where(
        (entry) => occupiesDownloadSlot(
          status: entry.status,
          queueWaiting: entry.queueWaiting,
        ),
      )
      .toList();
  final waiting = entries.where((entry) => entry.queueWaiting).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final waitingFifoIds = waiting.map((e) => e.taskId).toList();
  // Enqueue every leftover parked waiter into the native holding queue.
  // Native `maxConcurrent` keeps only N transferring; extras stay enqueued.
  final idsToPromote = List<String>.from(waitingFifoIds);

  return DownloadQueuePlan(
    maxConcurrent: n,
    occupiedCount: occupying.length,
    waitingFifoIds: waitingFifoIds,
    idsToPark: const [],
    idsToPromote: idsToPromote,
  );
}
