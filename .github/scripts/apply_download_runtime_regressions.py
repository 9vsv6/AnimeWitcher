from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, got {count}')
    p.write_text(text.replace(old, new, 1))


# 1) iOS continued-processing start must be acknowledged by native.
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    '''  Future<void> start({
    required String taskId,
    required String displayName,
    double progress = 0.0,
    int totalBytes = -1,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    int currentIndex = 0,
  }) async {
    _cancelPendingUpdate();
    _lastUpdateAt = DateTime.now();
    await _invoke('start', <String, Object>{
      'taskId': taskId,
      'displayName': displayName,
      'progress': progress.clamp(0.0, 1.0).toDouble(),
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'completedCount': completedCount,
      'batchTotal': batchTotal,
      'speedBytesPerSecond': speedBytesPerSecond,
      'currentIndex': currentIndex,
    });
  }
''',
    '''  Future<bool> start({
    required String taskId,
    required String displayName,
    double progress = 0.0,
    int totalBytes = -1,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    int currentIndex = 0,
  }) async {
    _cancelPendingUpdate();
    final result = await _invokeForResult<Object?>(
      'start',
      <String, Object>{
        'taskId': taskId,
        'displayName': displayName,
        'progress': progress.clamp(0.0, 1.0).toDouble(),
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        'completedCount': completedCount,
        'batchTotal': batchTotal,
        'speedBytesPerSecond': speedBytesPerSecond,
        'currentIndex': currentIndex,
      },
    );
    final accepted = switch (result) {
      final String identifier => identifier.trim().isNotEmpty,
      final bool value => value,
      _ => false,
    };
    if (accepted) _lastUpdateAt = DateTime.now();
    return accepted;
  }
''',
)

# 2) Parent speed must use byte-credible live progress, not only durable part files.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''    final task = session.task;
    final progress = session.progress;
    final creditedBytes = session.creditedBytes;
    final expectedBytes = session.size;
    final telemetry = _speedTelemetry.observe(
      taskId: task.taskId,
      transferredBytes: creditedBytes,
      expectedBytes: expectedBytes,
    );
''',
    '''    final task = session.task;
    final progress = session.progress;
    final expectedBytes = session.size;
    // Speed is presentation telemetry, not recovery authority. On iOS the
    // exact bytes currently arriving live in URLSession's temporary file and
    // therefore advance credibleProgress before they can advance durableBytes.
    // Feeding only durableBytes into the speed estimator made progress move
    // while the UI stayed at 0 MB/s until a whole Range finalized.
    final observedBytes = session.parts.fold<int>(0, (sum, part) {
      final credible = part.credibleProgress.clamp(0.0, 1.0).toDouble();
      final bytes = (part.size * credible).round().clamp(0, part.size);
      return sum + bytes;
    });
    final childSpeedBytesPerSecond = session.parts.fold<double>(0, (sum, part) {
      if (!part.launched || part.complete || part.speed <= 0) return sum;
      return sum + part.speed * 1000 * 1000;
    });
    final telemetry = _speedTelemetry.observe(
      taskId: task.taskId,
      transferredBytes: observedBytes,
      expectedBytes: expectedBytes,
      fallbackSpeedBytesPerSecond: childSpeedBytesPerSecond,
    );
''',
)

# 3) Restored URLSession ownership needs a liveness lease. A callback from the
# current process cancels this lease via _markConnectionReady; otherwise we
# periodically re-query ownership and recover the same immutable Range once the
# old worker has actually disappeared.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''          if (part.launched) {
            if (await _adoptExactSizePart(
              session,
              part,
              settleNativeOwner: true,
            )) {
              continue;
            }
            _armTailStallWatch(session, part);
            continue;
          }
''',
    '''          if (part.launched) {
            if (await _adoptExactSizePart(
              session,
              part,
              settleNativeOwner: true,
            )) {
              continue;
            }
            _armRestoredOwnershipLease(session, part);
            _armTailStallWatch(session, part);
            continue;
          }
''',
)

replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  void _armPendingStartLease(_ParallelSession session, _DownloadPart part) {
''',
    '''  void _armRestoredOwnershipLease(
    _ParallelSession session,
    _DownloadPart part,
  ) {
    if (_disposed ||
        !session.active ||
        session.pauseRequested ||
        session.deleted ||
        part.complete ||
        !part.launched) {
      _cancelPendingStartLease(part);
      return;
    }

    _cancelPendingStartLease(part);
    final parentGeneration = session.generation;
    final attemptGeneration = part.attemptGeneration;
    part.pendingStartLeaseTimer = Timer(pendingStartLeaseDelay, () {
      part.pendingStartLeaseTimer = null;
      unawaited(
        session.serialize(() async {
          if (_disposed ||
              !session.active ||
              session.pauseRequested ||
              session.deleted ||
              session.generation != parentGeneration ||
              part.complete ||
              !part.launched ||
              part.attemptGeneration != attemptGeneration) {
            return;
          }

          final lookup = livePartIds;
          if (lookup == null) {
            _armRestoredOwnershipLease(session, part);
            return;
          }

          Set<String> live;
          try {
            live = await lookup();
          } catch (_) {
            // Query failure is unknown ownership. Never create a second writer.
            _armRestoredOwnershipLease(session, part);
            return;
          }
          if (live.contains(part.task.taskId)) {
            // The OS still claims this exact worker. Keep its slot fenced, but
            // re-check later because a relaunch can lose its terminal callback.
            _armRestoredOwnershipLease(session, part);
            return;
          }

          diagnosticLog?.record('parallel.restoredOwnerReleased', {
            'taskId': session.task.taskId,
            'childTaskId': part.task.taskId,
            'attemptGeneration': attemptGeneration,
          });
          _schedulePartRecovery(session, part);
          await _persist(session);
          if (session.active) await _status(session, TaskStatus.running);
          _schedulePumpAll();
        }),
      );
    });
  }

  void _armPendingStartLease(_ParallelSession session, _DownloadPart part) {
''',
)

# 4) Runtime status policy required by the ownership tests. This stays a pure
# policy helper; persisted DB status is not used as negative ownership proof.
replace_once(
    'lib/core/services/download_transport.dart',
    '''bool isNativeSingleDownloadTask(Task task) =>
    task is DownloadTask && task is! ParallelDownloadTask;

''',
    '''bool isNativeSingleDownloadTask(Task task) =>
    task is DownloadTask && task is! ParallelDownloadTask;

/// Only non-final executor states can plausibly own a native writer. This is
/// useful when a runtime API returns a status together with the task identity;
/// persisted database status alone is never sufficient negative ownership
/// evidence.
bool runtimeTaskStatusCanOwnWriter(TaskStatus status) => switch (status) {
  TaskStatus.enqueued ||
  TaskStatus.running ||
  TaskStatus.waitingToRetry => true,
  TaskStatus.paused ||
  TaskStatus.complete ||
  TaskStatus.canceled ||
  TaskStatus.failed ||
  TaskStatus.notFound => false,
};

''',
)

# 5) Do not mark the iOS system overlay active when native rejected start.
service = Path('lib/core/services/download_service.dart')
text = service.read_text()
old = '''    if (_sessionOverlayActive) {
      await _continuedProcessing.update(
        taskId: session.currentTaskId,
        progress: session.progress,
        totalBytes: session.totalBytes,
        transferredBytes: session.transferredBytes,
        completedCount: session.completedCount,
        batchTotal: session.batchTotal < 1 ? 1 : session.batchTotal,
        speedBytesPerSecond: speed,
        displayName: session.displayName,
        currentIndex: session.currentIndex,
      );
    } else {
      await _continuedProcessing.start(
        taskId: session.currentTaskId,
        displayName: session.displayName,
        progress: session.progress,
        totalBytes: session.totalBytes,
        transferredBytes: session.transferredBytes,
        completedCount: session.completedCount,
        batchTotal: session.batchTotal < 1 ? 1 : session.batchTotal,
        speedBytesPerSecond: speed < 0 ? 0 : speed,
        currentIndex: session.currentIndex,
      );
    }
    _sessionOverlayActive = true;
    await _persistNativeWaitingSnapshot(overlay: session);
'''
new = '''    if (_sessionOverlayActive) {
      await _continuedProcessing.update(
        taskId: session.currentTaskId,
        progress: session.progress,
        totalBytes: session.totalBytes,
        transferredBytes: session.transferredBytes,
        completedCount: session.completedCount,
        batchTotal: session.batchTotal < 1 ? 1 : session.batchTotal,
        speedBytesPerSecond: speed,
        displayName: session.displayName,
        currentIndex: session.currentIndex,
      );
    } else {
      final started = await _continuedProcessing.start(
        taskId: session.currentTaskId,
        displayName: session.displayName,
        progress: session.progress,
        totalBytes: session.totalBytes,
        transferredBytes: session.transferredBytes,
        completedCount: session.completedCount,
        batchTotal: session.batchTotal < 1 ? 1 : session.batchTotal,
        speedBytesPerSecond: speed < 0 ? 0 : speed,
        currentIndex: session.currentIndex,
      );
      if (!started) {
        diagnosticLog.record('continued.startRejected', {
          'taskId': session.currentTaskId,
        });
      }
      _sessionOverlayActive = started;
    }
    await _persistNativeWaitingSnapshot(overlay: session);
'''
if text.count(old) != 1:
    raise SystemExit(f'download_service.dart: overlay start block match count={text.count(old)}')
service.write_text(text.replace(old, new, 1))
