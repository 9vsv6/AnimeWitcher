from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Dart bridge: expose exact native URLSession bytes for ordinary N=1 downloads.
# ---------------------------------------------------------------------------
path = "lib/core/services/download_continued_processing_service.dart"
text = read(path)
text = replace_once(
    text,
    "typedef SystemDownloadChunkUpdate = void Function({\n",
    "typedef SystemDownloadTaskUpdate = void Function({\n"
    "  required String taskId,\n"
    "  required String trackingUrl,\n"
    "  required int writtenBytes,\n"
    "  required int expectedBytes,\n"
    "  double? speedBytesPerSecond,\n"
    "});\n\n"
    "typedef SystemDownloadChunkUpdate = void Function({\n",
    "task update typedef",
)
text = replace_once(
    text,
    "  final SystemDownloadCancellation onSystemCancel;\n  final SystemDownloadChunkUpdate? onChunkUpdate;\n",
    "  final SystemDownloadCancellation onSystemCancel;\n"
    "  final SystemDownloadTaskUpdate? onTaskUpdate;\n"
    "  final SystemDownloadChunkUpdate? onChunkUpdate;\n",
    "task update field",
)
text = replace_once(
    text,
    "  DownloadContinuedProcessingService({\n    required this.onSystemCancel,\n    this.onChunkUpdate,\n  }) {\n",
    "  DownloadContinuedProcessingService({\n"
    "    required this.onSystemCancel,\n"
    "    this.onTaskUpdate,\n"
    "    this.onChunkUpdate,\n"
    "  }) {\n",
    "task update constructor",
)
text = replace_once(
    text,
    "    if (call.method == 'chunkUpdate') {\n",
    "    if (call.method == 'taskUpdate') {\n"
    "      final taskId = arguments['taskId'];\n"
    "      final trackingUrl = arguments['trackingUrl'];\n"
    "      final rawWritten = arguments['writtenBytes'];\n"
    "      final rawExpected = arguments['expectedBytes'];\n"
    "      final rawSpeed = arguments['speedBytesPerSecond'];\n"
    "      if (taskId is! String ||\n"
    "          taskId.isEmpty ||\n"
    "          trackingUrl is! String ||\n"
    "          trackingUrl.isEmpty ||\n"
    "          rawWritten is! num) {\n"
    "        return false;\n"
    "      }\n"
    "      onTaskUpdate?.call(\n"
    "        taskId: taskId,\n"
    "        trackingUrl: trackingUrl,\n"
    "        writtenBytes: rawWritten.toInt(),\n"
    "        expectedBytes: rawExpected is num ? rawExpected.toInt() : -1,\n"
    "        speedBytesPerSecond: rawSpeed is num ? rawSpeed.toDouble() : null,\n"
    "      );\n"
    "      return true;\n"
    "    }\n\n"
    "    if (call.method == 'chunkUpdate') {\n",
    "task update method bridge",
)
write(path, text)

# ---------------------------------------------------------------------------
# UI formatter: use the same decimal KB/MB convention as iOS byte formatter.
# ---------------------------------------------------------------------------
for path in [
    "lib/core/services/download_service.dart",
    "lib/core/utils/download_time_remaining.dart",
]:
    text = read(path)
    text = text.replace("networkSpeed * 1024", "networkSpeed * 1000")
    text = text.replace("data.networkSpeed * 1024", "data.networkSpeed * 1000")
    write(path, text)

# ---------------------------------------------------------------------------
# DownloadService: telemetry estimator, native byte bridge, expected-size
# reconciliation, stale-safe speed/ETA, and Range metadata reliability.
# ---------------------------------------------------------------------------
path = "lib/core/services/download_service.dart"
text = read(path)
text = replace_once(
    text,
    "import 'download_transport.dart';\nimport 'download_continued_processing_service.dart';\n",
    "import 'download_transport.dart';\n"
    "import 'download_continued_processing_service.dart';\n"
    "import 'download_telemetry.dart';\n",
    "telemetry import",
)

progress_notifier_pattern = re.compile(
    r"@Riverpod\(keepAlive: true\)\nclass DownloadProgressNotifier extends _\$DownloadProgressNotifier \{.*?\n\}\n\n@Riverpod\(keepAlive: true\)\nclass DownloadChunkProgress",
    re.S,
)
progress_notifier_replacement = '''@Riverpod(keepAlive: true)
class DownloadProgressNotifier extends _$DownloadProgressNotifier {
  static const Duration _uiSampleInterval = Duration(seconds: 1);
  static const Duration _staleMetricInterval = kDownloadTelemetryStaleAfter;
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, Timer> _staleTimers = <String, Timer>{};
  final Map<String, DownloadProgressData> _pending =
      <String, DownloadProgressData>{};
  final Map<String, DateTime> _lastPublished = <String, DateTime>{};

  @override
  Map<String, DownloadProgressData> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      for (final timer in _staleTimers.values) {
        timer.cancel();
      }
      _timers.clear();
      _staleTimers.clear();
      _pending.clear();
      _lastPublished.clear();
    });
    return {};
  }

  void update(String url, DownloadProgressData data) {
    final previous = state[url];
    final statusChanged = previous == null || previous.status != data.status;

    if (data.status == TaskStatus.running && data.progress < 1.0) {
      _armStaleMetricTimer(url, data.taskId);
    } else {
      _staleTimers.remove(url)?.cancel();
    }

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

  void _armStaleMetricTimer(String url, String taskId) {
    _staleTimers.remove(url)?.cancel();
    _staleTimers[url] = Timer(_staleMetricInterval, () {
      _staleTimers.remove(url);
      final current = state[url];
      if (current == null ||
          current.taskId != taskId ||
          current.status != TaskStatus.running ||
          current.progress >= 1.0) {
        return;
      }
      _timers.remove(url)?.cancel();
      _pending.remove(url);
      _lastPublished[url] = DateTime.now();
      state = {
        ...state,
        url: DownloadProgressData(
          taskId: current.taskId,
          progress: current.progress,
          networkSpeed: 0,
          timeRemaining: Duration.zero,
          totalSize: current.totalSize,
          status: current.status,
        ),
      };
    });
  }

  void _publishNow(String url, DownloadProgressData data) {
    _timers.remove(url)?.cancel();
    _pending.remove(url);
    _lastPublished[url] = DateTime.now();
    state = {...state, url: data};
  }

  void _publishPending(String url) {
    _timers.remove(url)?.cancel();
    final data = _pending.remove(url);
    if (data == null) return;
    _lastPublished[url] = DateTime.now();
    state = {...state, url: data};
  }

  void remove(String url) {
    _timers.remove(url)?.cancel();
    _staleTimers.remove(url)?.cancel();
    _pending.remove(url);
    _lastPublished.remove(url);
    state = {...state}..remove(url);
  }
}

@Riverpod(keepAlive: true)
class DownloadChunkProgress'''
text, count = progress_notifier_pattern.subn(progress_notifier_replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"progress notifier replacement: expected 1, got {count}")

text = replace_once(
    text,
    "  late final DownloadHostProfileStore _hostProfiles;\n  late final DownloadJobStore _jobStore;\n",
    "  late final DownloadHostProfileStore _hostProfiles;\n"
    "  late final DownloadJobStore _jobStore;\n"
    "  final DownloadTelemetryEstimator _telemetry = DownloadTelemetryEstimator();\n"
    "  final Set<String> _expectedSizePersistedIds = <String>{};\n",
    "telemetry fields",
)
text = replace_once(
    text,
    "    _continuedProcessing = DownloadContinuedProcessingService(\n      onSystemCancel: _cancelFromSystemUI,\n      onChunkUpdate: _handleNativeChunkUpdate,\n    );\n",
    "    _continuedProcessing = DownloadContinuedProcessingService(\n"
    "      onSystemCancel: _cancelFromSystemUI,\n"
    "      onTaskUpdate: _handleNativeTaskUpdate,\n"
    "      onChunkUpdate: _handleNativeChunkUpdate,\n"
    "    );\n",
    "continued processing constructor",
)

native_task_handler = '''
  void _handleNativeTaskUpdate({
    required String taskId,
    required String trackingUrl,
    required int writtenBytes,
    required int expectedBytes,
    double? speedBytesPerSecond,
  }) {
    if (_disposed || taskId.isEmpty || trackingUrl.isEmpty || writtenBytes < 0) {
      return;
    }
    if (_userPausedIds.contains(taskId) ||
        _cancellingUrls.contains(trackingUrl)) {
      return;
    }

    final current = _ref.read(downloadProgressProvider)[trackingUrl];
    final total = knownDownloadSize(<int?>[
      expectedBytes,
      _telemetry.expectedBytesFor(taskId),
      current?.totalSize,
    ]);
    final reading = _telemetry.observe(
      taskId: taskId,
      transferredBytes: writtenBytes,
      expectedBytes: total,
      fallbackSpeedBytesPerSecond: speedBytesPerSecond ?? 0,
    );
    final knownTotal = reading.expectedBytes > 0
        ? reading.expectedBytes
        : total;
    final measuredProgress = knownTotal > 0
        ? (reading.transferredBytes / knownTotal).clamp(0.0, 1.0).toDouble()
        : (current?.progress ?? 0.0);
    final progress = keepLastKnownDownloadProgress(
      incoming: measuredProgress,
      lastKnown: current?.progress,
    );
    final recentBytes = _telemetry.hasRecentBytes(taskId);
    final speedMb = reading.speedBytesPerSecond > 0
        ? reading.speedBytesPerSecond / 1000000
        : (recentBytes ? -1.0 : 0.0);

    _queueWaitingIds.remove(taskId);
    _waitingPayloads.remove(taskId);
    _ref.read(activeDownloadsProvider.notifier).add(trackingUrl);
    _ref
        .read(downloadProgressProvider.notifier)
        .update(
          trackingUrl,
          DownloadProgressData(
            taskId: taskId,
            progress: progress,
            networkSpeed: speedMb,
            timeRemaining: reading.timeRemaining,
            totalSize: knownTotal,
            status: TaskStatus.running,
          ),
        );
    unawaited(
      _ref
          .read(storageServiceProvider)
          .patchDownloadMetadata(taskId, queueWaiting: false),
    );
    if (knownTotal > 0) {
      unawaited(
        _rememberExpectedBytes(
          taskId: taskId,
          expectedBytes: knownTotal,
          progress: progress,
        ),
      );
    }
  }

  Future<void> _rememberExpectedBytes({
    required String taskId,
    required int expectedBytes,
    double? progress,
  }) async {
    if (expectedBytes <= 0 || !_expectedSizePersistedIds.add(taskId)) return;
    try {
      final record = await FileDownloader().database.recordForId(taskId);
      if (record != null && record.expectedFileSize <= 0) {
        final keptProgress = progress != null && progress >= 0 && progress <= 1
            ? progress
            : record.progress;
        await FileDownloader().database.updateRecord(
          TaskRecord(record.task, record.status, keptProgress, expectedBytes),
        );
      }
    } catch (_) {}
    try {
      await _ref
          .read(storageServiceProvider)
          .patchDownloadMetadata(
            taskId,
            lastExpectedBytes: expectedBytes,
            lastProgress: progress != null && progress > 0 && progress <= 1
                ? progress
                : null,
          );
    } catch (_) {}
    try {
      final job = await _jobStore.get(taskId);
      if (job != null && job.expectedBytes <= 0) {
        final derived = progress != null && progress > 0 && progress <= 1
            ? (progress * expectedBytes).floor()
            : 0;
        final durable = derived > job.durableBytes ? derived : job.durableBytes;
        await _jobStore.put(
          job.copyWith(
            expectedBytes: expectedBytes,
            durableBytes: durable,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (_) {}
  }
'''
text = replace_once(
    text,
    "  void _handleNativeChunkUpdate({\n",
    native_task_handler + "\n  void _handleNativeChunkUpdate({\n",
    "native single handler",
)
text = replace_once(
    text,
    "    _rangeTransfers.dispose();\n    unawaited(_nativeTransport.dispose());\n",
    "    _rangeTransfers.dispose();\n"
    "    _telemetry.clear();\n"
    "    _expectedSizePersistedIds.clear();\n"
    "    unawaited(_nativeTransport.dispose());\n",
    "telemetry dispose",
)

old_progress_metrics = '''          final speed = keepLastKnownDownloadSpeed(
            status: TaskStatus.running,
            incomingSpeed: update.networkSpeed,
            lastKnownSpeed: previous?.networkSpeed,
          );
          final remaining = update.timeRemaining > Duration.zero
              ? update.timeRemaining
              : (previous?.timeRemaining ?? Duration.zero);
          final progressData = DownloadProgressData(
            taskId: update.task.taskId,
            progress: progress,
            networkSpeed: speed,
            timeRemaining: remaining,
            totalSize: update.expectedFileSize > 0
                ? update.expectedFileSize
                : (previous?.totalSize ?? -1),
            status: TaskStatus.running,
          );'''
new_progress_metrics = '''          final knownTotal = knownDownloadSize(<int?>[
            update.expectedFileSize,
            _telemetry.expectedBytesFor(update.task.taskId),
            previous?.totalSize,
          ]);
          final fallbackSpeedBytes =
              update.networkSpeed.isFinite && update.networkSpeed > 0
              ? update.networkSpeed * 1000000
              : 0.0;
          final telemetry = _telemetry.observeProgress(
            taskId: update.task.taskId,
            progress: progress,
            expectedBytes: knownTotal,
            fallbackSpeedBytesPerSecond: fallbackSpeedBytes,
          );
          final measuredSpeed = telemetry.speedBytesPerSecond;
          final speed = measuredSpeed > 0
              ? measuredSpeed / 1000000
              : (_telemetry.hasRecentBytes(update.task.taskId) ? -1.0 : 0.0);
          final remaining = telemetry.timeRemaining > Duration.zero
              ? telemetry.timeRemaining
              : (update.timeRemaining > Duration.zero
                    ? update.timeRemaining
                    : (previous?.timeRemaining ?? Duration.zero));
          final progressData = DownloadProgressData(
            taskId: update.task.taskId,
            progress: progress,
            networkSpeed: speed,
            timeRemaining: remaining,
            totalSize: telemetry.expectedBytes > 0
                ? telemetry.expectedBytes
                : knownTotal,
            status: TaskStatus.running,
          );
          if (progressData.totalSize > 0) {
            unawaited(
              _rememberExpectedBytes(
                taskId: update.task.taskId,
                expectedBytes: progressData.totalSize,
                progress: progress,
              ),
            );
          }'''
text = replace_once(text, old_progress_metrics, new_progress_metrics, "progress telemetry")

text = replace_once(
    text,
    "          final uiStatus = displayDownloadStatus(\n            persisted: update.status,\n            queueWaiting: _queueWaitingIds.contains(update.task.taskId),\n          );\n",
    "          final uiStatus = displayDownloadStatus(\n"
    "            persisted: update.status,\n"
    "            queueWaiting: _queueWaitingIds.contains(update.task.taskId),\n"
    "          );\n"
    "          if (uiStatus != TaskStatus.running) {\n"
    "            _telemetry.resetSpeed(update.task.taskId);\n"
    "          }\n",
    "status speed reset",
)

# Startup recovery already computes a stronger expectedBytes value: publish it.
text = replace_once(
    text,
    "        totalSize: record.expectedFileSize,\n        status: showAsWaiting\n",
    "        totalSize: expectedBytes,\n        status: showAsWaiting\n",
    "recovery expected size",
)

# Seed recovered expected bytes/durable bytes before recovery state is published.
text = replace_once(
    text,
    "      if (oldJob != null && oldJob.durableBytes > durableBytes) {\n        durableBytes = oldJob.durableBytes;\n      }\n      final migratedJob = DownloadJobRecord(\n",
    "      if (oldJob != null && oldJob.durableBytes > durableBytes) {\n"
    "        durableBytes = oldJob.durableBytes;\n"
    "      }\n"
    "      _telemetry.seed(\n"
    "        task.taskId,\n"
    "        transferredBytes: durableBytes,\n"
    "        expectedBytes: expectedBytes,\n"
    "      );\n"
    "      final migratedJob = DownloadJobRecord(\n",
    "recovery telemetry seed",
)

# Saved progress must reconcile every durable expected-size source, including the
# logical job store and exact native telemetry.
text = replace_once(
    text,
    "    final metadata = await _ref\n        .read(storageServiceProvider)\n        .getDownloadMetadata(task.taskId);\n    final parallelProgress = task is ParallelDownloadTask\n",
    "    final metadata = await _ref\n"
    "        .read(storageServiceProvider)\n"
    "        .getDownloadMetadata(task.taskId);\n"
    "    final job = await _jobStore.get(task.taskId);\n"
    "    final parallelProgress = task is ParallelDownloadTask\n",
    "saved progress job read",
)
text = replace_once(
    text,
    "    final totalSize = knownDownloadSize([\n      current?.totalSize,\n      record?.expectedFileSize,\n      downloadMetadataExpectedBytes(metadata),\n    ]);\n",
    "    final totalSize = knownDownloadSize([\n"
    "      current?.totalSize,\n"
    "      _telemetry.expectedBytesFor(task.taskId),\n"
    "      record?.expectedFileSize,\n"
    "      downloadMetadataExpectedBytes(metadata),\n"
    "      job?.expectedBytes,\n"
    "    ]);\n"
    "    if (job != null && job.expectedBytes > 0 && job.durableBytes > 0) {\n"
    "      progress = keepLastKnownDownloadProgress(\n"
    "        incoming: progress,\n"
    "        lastKnown: job.durableBytes / job.expectedBytes,\n"
    "      );\n"
    "    }\n",
    "saved progress total candidates",
)
text = replace_once(
    text,
    "    return (\n      progress: progress,\n      totalSize: totalSize,\n      partialBytes: partialBytes,\n    );\n",
    "    final credibleBytes = partialBytes > 0\n"
    "        ? partialBytes\n"
    "        : (totalSize > 0 && progress > 0\n"
    "              ? (totalSize * progress).floor()\n"
    "              : 0);\n"
    "    _telemetry.seed(\n"
    "      task.taskId,\n"
    "      transferredBytes: credibleBytes,\n"
    "      expectedBytes: totalSize,\n"
    "    );\n"
    "    return (\n"
    "      progress: progress,\n"
    "      totalSize: totalSize,\n"
    "      partialBytes: partialBytes,\n"
    "    );\n",
    "saved progress telemetry seed",
)

# Reattaching a native URLSession task must not throw away size/progress learned
# from metadata/job/native telemetry just because its plugin DB record is sparse.
old_attach = '''    final record = await FileDownloader().database.recordForId(attached.taskId);
    final trackingUrl = downloadTrackingUrl(attached);
    var progress = record?.progress ?? 0.0;
    if (progress < 0 || progress > 1) progress = 0.0;
    final totalSize = record?.expectedFileSize ?? -1;
    final transferring ='''
new_attach = '''    final record = await FileDownloader().database.recordForId(attached.taskId);
    final trackingUrl = downloadTrackingUrl(attached);
    final saved = await _savedProgressFor(attached);
    var progress = record?.progress ?? saved.progress;
    if (progress < 0 || progress > 1) progress = saved.progress;
    progress = keepLastKnownDownloadProgress(
      incoming: progress,
      lastKnown: saved.progress,
    );
    final totalSize = saved.totalSize;
    final transferring ='''
text = replace_once(text, old_attach, new_attach, "attach live expected size")

old_attach_all = '''      final record = byId[task.taskId];
      var progress = record?.progress ?? 0.0;
      if (progress < 0 || progress > 1) progress = 0.0;
      final totalSize = record?.expectedFileSize ?? -1;
      final transferring ='''
new_attach_all = '''      final record = byId[task.taskId];
      final saved = await _savedProgressFor(task as DownloadTask);
      var progress = record?.progress ?? saved.progress;
      if (progress < 0 || progress > 1) progress = saved.progress;
      progress = keepLastKnownDownloadProgress(
        incoming: progress,
        lastKnown: saved.progress,
      );
      final totalSize = saved.totalSize;
      final transferring ='''
text = replace_once(text, old_attach_all, new_attach_all, "attach all expected size")

# _publishProgress must also honor native/job-known total size.
text = replace_once(
    text,
    "    final previous = _ref.read(downloadProgressProvider)[trackingUrl];\n    final parallelProgress = _parallel.progressFor(taskId);\n",
    "    final previous = _ref.read(downloadProgressProvider)[trackingUrl];\n"
    "    final parallelProgress = _parallel.progressFor(taskId);\n"
    "    final knownTotal = knownDownloadSize(<int?>[\n"
    "      totalSize,\n"
    "      _telemetry.expectedBytesFor(taskId),\n"
    "      previous?.totalSize,\n"
    "    ]);\n"
    "    if (knownTotal > 0) {\n"
    "      _telemetry.seed(taskId, expectedBytes: knownTotal);\n"
    "    }\n",
    "publish known total",
)
text = replace_once(
    text,
    "            totalSize: totalSize > 0 ? totalSize : (previous?.totalSize ?? -1),\n",
    "            totalSize: knownTotal,\n",
    "publish total assignment",
)

# Explicit delete is also the telemetry reset boundary.
text = replace_once(
    text,
    "    _ref.read(downloadChunkProgressProvider.notifier).remove(taskId);\n\n    await _rangeTransfers.stop(taskId);\n",
    "    _ref.read(downloadChunkProgressProvider.notifier).remove(taskId);\n"
    "    _telemetry.remove(taskId);\n"
    "    _expectedSizePersistedIds.remove(taskId);\n\n"
    "    await _rangeTransfers.stop(taskId);\n",
    "cancel telemetry reset",
)

# Pause total-size reconciliation should not regress a native-known size.
text = text.replace(
    "          current?.totalSize,\n          record?.expectedFileSize,\n          downloadMetadataExpectedBytes(metadata),\n",
    "          current?.totalSize,\n"
    "          _telemetry.expectedBytesFor(taskId),\n"
    "          record?.expectedFileSize,\n"
    "          downloadMetadataExpectedBytes(metadata),\n",
)

# Fresh start: initialize the app telemetry immediately for BOTH ordinary and
# multipart tasks. Previously only waiting rows got a progress-map entry.
text = replace_once(
    text,
    "        _ref.read(activeDownloadsProvider.notifier).add(trackingUrl ?? url);\n\n        if (!startNow) {\n",
    "        _ref.read(activeDownloadsProvider.notifier).add(trackingUrl ?? url);\n"
    "        _telemetry.seed(\n"
    "          transferTask.taskId,\n"
    "          expectedBytes: expectedBytes,\n"
    "        );\n"
    "        _publishProgress(\n"
    "          trackingUrl: trackingUrl ?? url,\n"
    "          taskId: transferTask.taskId,\n"
    "          progress: 0,\n"
    "          totalSize: expectedBytes,\n"
    "          status: TaskStatus.enqueued,\n"
    "        );\n\n"
    "        if (!startNow) {\n",
    "fresh telemetry seed",
)
# Remove the now-redundant waiting-only publish block.
text = replace_once(
    text,
    "          _publishProgress(\n            trackingUrl: trackingUrl ?? url,\n            taskId: task.taskId,\n            progress: 0,\n            totalSize: expectedBytes,\n            status: TaskStatus.enqueued,\n          );\n",
    "",
    "duplicate waiter publish",
)

# Metadata: HEAD evidence survives a failed probe; an explicit HTTP 200 to a
# Range request is the only probe result that disproves ranges. Identity
# encoding keeps Content-Length/Content-Range byte-exact.
text = replace_once(
    text,
    "              options: Options(headers: headers, followRedirects: true),\n",
    "              options: Options(\n"
    "                headers: {...?headers, 'Accept-Encoding': 'identity'},\n"
    "                followRedirects: true,\n"
    "              ),\n",
    "metadata head identity encoding",
)
text = replace_once(
    text,
    "      {\n        supportsRanges = false;\n        try {\n",
    "      {\n        try {\n",
    "metadata range evidence preservation",
)
text = replace_once(
    text,
    "                  headers: {...?headers, 'Range': 'bytes=0-0'},\n",
    "                  headers: {\n"
    "                    ...?headers,\n"
    "                    'Range': 'bytes=0-0',\n"
    "                    'Accept-Encoding': 'identity',\n"
    "                  },\n",
    "metadata range identity encoding",
)
text = replace_once(
    text,
    "          } else {\n            final contentLength = int.tryParse(\n",
    "          } else {\n"
    "            // A successful 200 to an explicit Range request means the\n"
    "            // origin ignored the range. A thrown probe keeps HEAD's prior\n"
    "            // Accept-Ranges evidence instead of falsely disabling parts.\n"
    "            supportsRanges = false;\n"
    "            final contentLength = int.tryParse(\n",
    "metadata explicit range rejection",
)

write(path, text)

# ---------------------------------------------------------------------------
# Swift URLSession hook: smooth speed over >=1 second and bridge exact bytes to
# Flutter for ordinary (non-multipart) downloads.
# ---------------------------------------------------------------------------
path = "ios/Runner/DownloadNativeWaitingQueue.swift"
text = read(path)
text = replace_once(
    text,
    "  private static var lastWrites: [String: WriteSample] = [:]\n  private static var lastChunkWrites: [String: WriteSample] = [:]\n  private static let chunkBridgeInterval: CFTimeInterval = 0.25\n",
    "  private static var lastWrites: [String: WriteSample] = [:]\n"
    "  private static var lastChunkWrites: [String: WriteSample] = [:]\n"
    "  private static var lastTaskBridgeTimes: [String: CFAbsoluteTime] = [:]\n"
    "  private static let chunkBridgeInterval: CFTimeInterval = 0.25\n"
    "  private static let taskBridgeInterval: CFTimeInterval = 0.25\n"
    "  private static let speedSampleInterval: CFTimeInterval = 1.0\n",
    "native telemetry fields",
)
text = replace_once(
    text,
    "    lastWrites.removeAll()\n    lastChunkWrites.removeAll()\n",
    "    lastWrites.removeAll()\n"
    "    lastChunkWrites.removeAll()\n"
    "    lastTaskBridgeTimes.removeAll()\n",
    "native reset telemetry",
)
text = text.replace(
    "      lastWrites[failedId] = nil\n",
    "      lastWrites[failedId] = nil\n      lastTaskBridgeTimes[failedId] = nil\n",
)
text = text.replace(
    "      lastWrites[completedId] = nil\n",
    "      lastWrites[completedId] = nil\n      lastTaskBridgeTimes[completedId] = nil\n",
)
old_speed = '''    var speed: Double = 0
    if let last = lastWrites[id], now > last.time {
      let deltaBytes = Double(max(totalWritten - last.bytes, 0))
      let deltaTime = now - last.time
      if deltaTime > 0 {
        speed = deltaBytes / deltaTime
      }
    }
    lastWrites[id] = WriteSample(taskId: id, bytes: totalWritten, time: now)
    var state = loadLocked()'''
new_speed = '''    var speed: Double = 0
    if let last = lastWrites[id], now > last.time {
      let deltaTime = now - last.time
      if deltaTime >= speedSampleInterval {
        let deltaBytes = Double(max(totalWritten - last.bytes, 0))
        if deltaBytes > 0 {
          speed = deltaBytes / deltaTime
        }
        lastWrites[id] = WriteSample(taskId: id, bytes: totalWritten, time: now)
      }
    } else {
      lastWrites[id] = WriteSample(taskId: id, bytes: totalWritten, time: now)
    }
    var state = loadLocked()'''
text = replace_once(text, old_speed, new_speed, "native speed window")
text = replace_once(
    text,
    "    let presentation = overlayPresentation(from: state, fallbackId: id, fallbackName: name)\n    saveLocked(state)\n    lock.unlock()\n\n    upsertSessionOverlay(\n",
    "    let presentation = overlayPresentation(from: state, fallbackId: id, fallbackName: name)\n"
    "    let stableExpected = sample.expected > 0 ? sample.expected : totalExpected\n"
    "    let stableSpeed = sample.speed\n"
    "    saveLocked(state)\n"
    "    lock.unlock()\n\n"
    "    postSingleTaskUpdate(\n"
    "      taskId: id,\n"
    "      trackingUrl: metaData.isEmpty ? url : metaData,\n"
    "      totalWritten: totalWritten,\n"
    "      totalExpected: stableExpected,\n"
    "      speedBytesPerSecond: stableSpeed,\n"
    "      now: now\n"
    "    )\n\n"
    "    upsertSessionOverlay(\n",
    "native bridge invocation",
)
helper = '''
  /// Exact byte telemetry for ordinary URLSession downloads. The system
  /// notification already has these values; forwarding the same source of
  /// truth fixes Flutter's `-- / -- MB` when background_downloader reports an
  /// unknown expectedFileSize. Throttle transport events, while Dart owns the
  /// one-second UI cadence and the longer smoothing window.
  private static func postSingleTaskUpdate(
    taskId: String,
    trackingUrl: String,
    totalWritten: Int64,
    totalExpected: Int64,
    speedBytesPerSecond: Double,
    now: CFAbsoluteTime
  ) {
    guard !taskId.isEmpty, !trackingUrl.isEmpty, totalWritten >= 0 else { return }
    lock.lock()
    if let last = lastTaskBridgeTimes[taskId], now - last < taskBridgeInterval {
      lock.unlock()
      return
    }
    lastTaskBridgeTimes[taskId] = now
    lock.unlock()

    var values: [String: Any] = [
      "taskId": taskId,
      "trackingUrl": trackingUrl,
      "writtenBytes": totalWritten,
    ]
    if totalExpected > 0 {
      values["expectedBytes"] = totalExpected
    }
    if speedBytesPerSecond > 0, speedBytesPerSecond.isFinite {
      values["speedBytesPerSecond"] = speedBytesPerSecond
    }
    NotificationCenter.default.post(
      name: Notification.Name("AnimeWitcherBackgroundDownloaderTaskUpdate"),
      object: nil,
      userInfo: values
    )
  }

'''
text = replace_once(
    text,
    "  private static func startLiveActivity(\n",
    helper + "  private static func startLiveActivity(\n",
    "native bridge helper",
)
write(path, text)

# ---------------------------------------------------------------------------
# AppDelegate forwards the ordinary task notification to Dart.
# ---------------------------------------------------------------------------
path = "ios/Runner/AppDelegate.swift"
text = read(path)
text = replace_once(
    text,
    "  private var downloadChunkProgressObserver: NSObjectProtocol?\n",
    "  private var downloadChunkProgressObserver: NSObjectProtocol?\n"
    "  private var downloadTaskProgressObserver: NSObjectProtocol?\n",
    "appdelegate task observer field",
)
marker = '''#endif

#if os(iOS)
    if #available(iOS 26.0, *) {
      DownloadContinuedProcessingManager.shared.cancellationHandler = {'''
observer = '''#endif

#if os(iOS)
    if let previous = downloadTaskProgressObserver {
      NotificationCenter.default.removeObserver(previous)
    }
    downloadTaskProgressObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("AnimeWitcherBackgroundDownloaderTaskUpdate"),
      object: nil,
      queue: .main
    ) { [weak channel] notification in
      guard let values = notification.userInfo,
            let taskId = values["taskId"] as? String,
            let trackingUrl = values["trackingUrl"] as? String,
            !taskId.isEmpty,
            !trackingUrl.isEmpty,
            let written = values["writtenBytes"] as? NSNumber else { return }

      var arguments: [String: Any] = [
        "taskId": taskId,
        "trackingUrl": trackingUrl,
        "writtenBytes": written.int64Value,
      ]
      if let expected = values["expectedBytes"] as? NSNumber {
        arguments["expectedBytes"] = expected.int64Value
      }
      if let speed = values["speedBytesPerSecond"] as? NSNumber {
        arguments["speedBytesPerSecond"] = speed.doubleValue
      }
      channel?.invokeMethod("taskUpdate", arguments: arguments)
    }
#endif

#if os(iOS)
    if #available(iOS 26.0, *) {
      DownloadContinuedProcessingManager.shared.cancellationHandler = {'''
text = replace_once(text, marker, observer, "appdelegate task observer")
write(path, text)

print("download telemetry review patch applied")
