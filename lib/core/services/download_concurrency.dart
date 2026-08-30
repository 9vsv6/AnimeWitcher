import 'package:background_downloader/background_downloader.dart';

/// Hive settings key used by official SkyStream and this fork.
const String kDownloadConcurrencyStorageKey = 'download_concurrency';

/// Persisted on download metadata so overflow episodes wait in-app without
/// being OS-enqueued (which would start an iOS Live Activity overlay).
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
/// Extra episode downloads wait FIFO until a running slot frees (finish,
/// fail, or cancel). Used by [DownloadService.applyQueueSettings] so a
/// Settings change applies without restarting the app.
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

/// Occupied slots are native transfers only. User-paused and in-app waiting
/// rows must not count, or overflow episodes would still get a Live Activity.
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

/// Waiting rows are stored paused so FileDownloader never starts them, but the
/// Downloads tab must keep the existing **في الانتظار...** (`enqueued`) label.
TaskStatus displayDownloadStatus({
  required TaskStatus persisted,
  required bool queueWaiting,
}) {
  if (queueWaiting) return TaskStatus.enqueued;
  return persisted;
}

/// Live Activity / continued-processing UI is only for tasks we actually hand
/// to the OS. Waiting overflow must not call `start`.
bool shouldStartDownloadLiveActivity({required bool willEnqueueWithOs}) =>
    willEnqueueWithOs;

enum DownloadAdmission { enqueueNow, parkAsWaiting }

DownloadAdmission admitDownload({
  required int occupiedSlots,
  required int maxConcurrent,
}) {
  final n = clampDownloadConcurrency(maxConcurrent);
  if (occupiedSlots < n) return DownloadAdmission.enqueueNow;
  return DownloadAdmission.parkAsWaiting;
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

/// FIFO waiting promotion and newest-first park when the user lowers N.
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

  occupying.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final overflow = occupying.length > n ? occupying.length - n : 0;
  final idsToPark = occupying.take(overflow).map((e) => e.taskId).toList();

  final occupiedAfterPark = occupying.length - idsToPark.length;
  final freeSlots = (n - occupiedAfterPark).clamp(0, n);
  final waitingFifoIds = waiting.map((e) => e.taskId).toList();
  final parkSet = idsToPark.toSet();
  final idsToPromote = waitingFifoIds
      .where((id) => !parkSet.contains(id))
      .take(freeSlots)
      .toList();

  return DownloadQueuePlan(
    maxConcurrent: n,
    occupiedCount: occupying.length,
    waitingFifoIds: waitingFifoIds,
    idsToPark: idsToPark,
    idsToPromote: idsToPromote,
  );
}
