import 'dart:convert';

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

/// Persists [maxConcurrent] then reconfigures FileDownloader's holding queue
/// (Android / in-app cap). iOS overflow waiters are parked as **في الانتظار**
/// and started by Dart whenever the isolate is alive (complete / fail /
/// cancel / foreground / init). Native URLSession start remains a background
/// backup; it must not be the only promoter (PR #116 device regression).
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
/// is actually transferring. Waiting **في الانتظار** rows must not call `start`.
bool shouldStartDownloadLiveActivity(TaskStatus status) =>
    status == TaskStatus.running;

/// Plugin `HoldingQueue` did not advance waiters on the home screen. Overflow
/// is parked (no overlay) and persisted for Swift as a background backup.
bool shouldEnqueueOverflowToNativeHoldingQueue() => false;

/// When the Flutter isolate is alive, Dart must start the next waiter if a
/// slot is free. PR #116 left waiters stranded in-app because native start
/// never fired and this flag was false.
bool shouldPromoteWaitingWhenIsolateAlive() => true;

/// Opening the app must unstick a waiter if a slot is free (same path as
/// in-app complete). Native start is still desired outside the app.
bool shouldPromoteWaitingOnAppForeground() => true;

/// Full payload Swift needs to create the next `URLSessionDownloadTask`
/// without Dart reconstructing the `DownloadTask`.
Map<String, Object> nativeWaitingPayload(DownloadTask task) {
  return <String, Object>{
    'taskId': task.taskId,
    'taskJson': jsonEncode(task.toJson()),
    'displayName': task.displayName,
    'url': task.url,
    'headers': Map<String, String>.from(task.headers),
    'filename': task.filename,
    'directory': task.directory,
    'httpRequestMethod': task.httpRequestMethod,
    'group': task.group,
    'metaData': task.metaData,
  };
}

bool nativeWaiterPayloadIsComplete(Map<String, Object?> payload) {
  final taskJson = payload['taskJson'] as String?;
  final url = payload['url'] as String?;
  final filename = payload['filename'] as String?;
  final taskId = payload['taskId'] as String?;
  return taskJson != null &&
      taskJson.isNotEmpty &&
      url != null &&
      url.isNotEmpty &&
      filename != null &&
      filename.isNotEmpty &&
      taskId != null &&
      taskId.isNotEmpty;
}

/// After a process kill, iOS `HoldingQueue` memory is gone. URLSession tasks
/// already submitted can continue; waiters that never reached URLSession must
/// be restored into the Swift waiting store. Never auto-resume a user-paused
/// row.
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

/// iOS concurrency=1, two episodes: waiting rows stay **في الانتظار** with
/// no Live Activity. When a slot frees, Dart (if awake) or Swift starts it.
bool waitingEpisodeMayStartLiveActivityWhileQueued() => false;

enum DownloadAdmission { enqueueNow, persistNativeWaitingQueue }

/// Occupied slots get a live FileDownloader/URLSession task. Overflow is
/// parked as **في الانتظار** until Dart (isolate alive) or Swift (background)
/// starts it with the unpause/resume path.
DownloadAdmission admitDownload({
  required int occupiedSlots,
  required int maxConcurrent,
}) {
  final n = clampDownloadConcurrency(maxConcurrent);
  if (occupiedSlots < n) return DownloadAdmission.enqueueNow;
  return DownloadAdmission.persistNativeWaitingQueue;
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
  final occupiedCount = occupying.length;
  final freeSlots = (n - occupiedCount).clamp(0, n);
  // Only start as many waiters as there are free slots. Listing every waiter
  // here was why iOS skipped Dart promotion entirely (#116).
  final idsToPromote = waitingFifoIds.take(freeSlots).toList();

  return DownloadQueuePlan(
    maxConcurrent: n,
    occupiedCount: occupiedCount,
    waitingFifoIds: waitingFifoIds,
    idsToPark: const [],
    idsToPromote: idsToPromote,
  );
}
