from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))


def replace_at_least_once(path: str, old: str, new: str, limit: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count < 1:
        raise SystemExit(f'{path}: expected a match: {old[:100]!r}')
    p.write_text(text.replace(old, new, limit))


# 1) A throughput value is not credible until it covers the minimum sampling
# window. Falling back to the very first sub-750ms pair recreated the exact
# callback-burst spikes the estimator was introduced to remove.
replace_once(
    'lib/core/services/download_telemetry.dart',
    '''  double _byteWindowSpeed(_TelemetryState state) {
    if (state.byteSamples.length < 2) return 0;
    final latest = state.byteSamples.last;
    _BytePoint? oldest;
    for (final sample in state.byteSamples) {
      final elapsed = latest.at.difference(sample.at);
      if (elapsed >= minimumWindow) {
        oldest = sample;
        break;
      }
    }
    oldest ??= state.byteSamples.first;
    final elapsedMicros = latest.at.difference(oldest.at).inMicroseconds;
    final deltaBytes = latest.bytes - oldest.bytes;
    if (elapsedMicros <= 0 || deltaBytes <= 0) return 0;
    return deltaBytes / (elapsedMicros / Duration.microsecondsPerSecond);
  }
''',
    '''  double _byteWindowSpeed(_TelemetryState state) {
    if (state.byteSamples.length < 2) return 0;
    final oldest = state.byteSamples.first;
    final latest = state.byteSamples.last;
    final elapsed = latest.at.difference(oldest.at);
    // URLSession/progress callbacks arrive in bursts. A 50-300ms delta is not
    // a user-visible download speed; wait for a real observation window rather
    // than magnifying that burst into an implausible MB/s value.
    if (elapsed < minimumWindow) return 0;
    final elapsedMicros = elapsed.inMicroseconds;
    final deltaBytes = latest.bytes - oldest.bytes;
    if (elapsedMicros <= 0 || deltaBytes <= 0) return 0;
    return deltaBytes / (elapsedMicros / Duration.microsecondsPerSecond);
  }
''',
)

# 2) Keep the system continued-processing task alive through short bookkeeping
# gaps. A momentary empty transferring/waiter list used to finish the BG task,
# then the next byte callback submitted a brand-new one (visible as the task
# disappearing/reappearing in the user's recording).
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    var sessionIsIdle: Bool {
      transferringTaskIds.isEmpty && waiters.isEmpty
    }
''',
    '''    var sessionIsIdle: Bool {
      guard transferringTaskIds.isEmpty && waiters.isEmpty else { return false }
      if sessionBatchTotal <= 0 && sessionTaskIds.isEmpty { return true }

      let terminalIds = Set(completedTaskIds).union(pausedTaskIds)
      let hasKnownOutstandingEpisode = sessionTaskIds.contains {
        !terminalIds.contains($0)
      }
      let terminalCount = min(terminalIds.count, max(sessionBatchTotal, 0))
      let batchStillOutstanding = sessionBatchTotal > 0
        && terminalCount < sessionBatchTotal
      return !hasKnownOutstandingEpisode && !batchStillOutstanding
    }
''',
)

# Replace the native one-callback speed state with the same four-second rolling
# window used by Flutter. Zero is a real value, not "keep the previous speed".
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''  private struct WriteSample {
    var taskId: String
    var bytes: Int64
    var time: CFAbsoluteTime
  }
''',
    '''  private struct ThroughputPoint {
    var bytes: Int64
    var time: CFAbsoluteTime
  }
''',
)
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''  private static var lastWrites: [String: WriteSample] = [:]
  private static var lastChunkWrites: [String: WriteSample] = [:]
  private static var lastTaskBridgeTimes: [String: CFAbsoluteTime] = [:]
  private static let chunkBridgeInterval: CFTimeInterval = 0.25
  private static let taskBridgeInterval: CFTimeInterval = 0.25
  private static let speedSampleInterval: CFTimeInterval = 1.0
''',
    '''  private static var taskSpeedWindows: [String: [ThroughputPoint]] = [:]
  private static var chunkSpeedWindows: [String: [ThroughputPoint]] = [:]
  private static var lastChunkBridgeTimes: [String: CFAbsoluteTime] = [:]
  private static var lastTaskBridgeTimes: [String: CFAbsoluteTime] = [:]
  private static let chunkBridgeInterval: CFTimeInterval = 0.25
  private static let taskBridgeInterval: CFTimeInterval = 0.25
  private static let speedWindowInterval: CFTimeInterval = 4.0
  private static let speedMinimumWindow: CFTimeInterval = 0.75
  private static let speedStaleInterval: CFTimeInterval = 3.0
  private static let speedWindowMaxPoints = 32
''',
)
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    lastWrites.removeAll()
    lastChunkWrites.removeAll()
    lastTaskBridgeTimes.removeAll()
''',
    '''    taskSpeedWindows.removeAll()
    chunkSpeedWindows.removeAll()
    lastChunkBridgeTimes.removeAll()
    lastTaskBridgeTimes.removeAll()
''',
)
# completion/failure cleanup occurs in two sibling methods
text_path = Path('ios/Runner/DownloadNativeWaitingQueue.swift')
text = text_path.read_text()
text = text.replace(
    '''      lastWrites[failedId] = nil
      lastTaskBridgeTimes[failedId] = nil
''',
    '''      taskSpeedWindows[failedId] = nil
      lastTaskBridgeTimes[failedId] = nil
''',
)
text = text.replace(
    '''      lastWrites[completedId] = nil
      lastTaskBridgeTimes[completedId] = nil
''',
    '''      taskSpeedWindows[completedId] = nil
      lastTaskBridgeTimes[completedId] = nil
''',
)
text_path.write_text(text)

# Insert reusable rolling estimator and a stale-speed reset before multipart
# forwarding. The stale reset only edits presentation telemetry; it never
# cancels, pauses, resumes, or replaces a URLSession task.
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''  /// Forward native URLSession byte counts for multipart children while the
  /// body still lives in Apple's temporary file. Dart cannot stat that file,
''',
    '''  private static func rollingSpeedLocked(
    windows: inout [String: [ThroughputPoint]],
    taskId: String,
    totalWritten: Int64,
    now: CFAbsoluteTime,
    completed: Bool = false
  ) -> Double {
    var points = windows[taskId] ?? []
    if let last = points.last, totalWritten < last.bytes {
      // Resume-data handoff can restart URLSession's counter. Treat it as a new
      // observation window instead of creating a negative/huge delta.
      points.removeAll()
    }
    if points.last?.bytes != totalWritten || points.isEmpty {
      points.append(ThroughputPoint(bytes: max(totalWritten, 0), time: now))
    }
    let cutoff = now - speedWindowInterval
    points.removeAll { $0.time < cutoff }
    if points.count > speedWindowMaxPoints {
      points.removeFirst(points.count - speedWindowMaxPoints)
    }

    if completed {
      windows[taskId] = nil
    } else {
      windows[taskId] = points
    }
    guard points.count >= 2,
          let first = points.first,
          let last = points.last
    else { return 0 }
    let elapsed = last.time - first.time
    let delta = last.bytes - first.bytes
    guard elapsed >= speedMinimumWindow, delta > 0 else { return 0 }
    return Double(delta) / elapsed
  }

  private static func scheduleNativeSpeedStaleReset(
    taskId: String,
    observedAt: CFAbsoluteTime
  ) {
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + speedStaleInterval
    ) {
      lock.lock()
      guard let last = taskSpeedWindows[taskId]?.last,
            last.time <= observedAt + 0.000_001,
            CFAbsoluteTimeGetCurrent() - last.time >= speedStaleInterval
      else {
        lock.unlock()
        return
      }
      var state = loadLocked()
      guard state.transferringTaskIds.contains(taskId),
            var sample = state.runningSamples[taskId]
      else {
        lock.unlock()
        return
      }
      sample.speed = 0
      state.runningSamples[taskId] = sample
      let presentation = overlayPresentation(
        from: state,
        fallbackId: taskId,
        fallbackName: sample.displayName
      )
      saveLocked(state)
      lock.unlock()

      upsertSessionOverlay(
        currentTaskId: presentation.currentTaskId,
        displayName: presentation.displayName,
        progress: presentation.progress,
        totalBytes: presentation.totalBytes,
        transferredBytes: presentation.transferredBytes,
        speedBytesPerSecond: presentation.speedBytesPerSecond
      )
    }
  }

  /// Forward native URLSession byte counts for multipart children while the
  /// body still lives in Apple's temporary file. Dart cannot stat that file,
''',
)

# Multipart speed: keep 250ms event bridge, but speed itself is a 4-second
# byte window and is not the delta between two bursty callbacks.
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    let now = CFAbsoluteTimeGetCurrent()
    var speed = 0.0
    lock.lock()
    if let last = lastChunkWrites[childId], now > last.time {
      let elapsed = now - last.time
      if !completed && elapsed < chunkBridgeInterval {
        lock.unlock()
        return
      }
      let delta = Double(max(totalWritten - last.bytes, 0))
      if elapsed > 0 && delta > 0 {
        speed = delta / elapsed
      }
    }
    if completed {
      lastChunkWrites[childId] = nil
    } else {
      lastChunkWrites[childId] = WriteSample(
        taskId: childId,
        bytes: max(totalWritten, 0),
        time: now
      )
    }
    lock.unlock()
''',
    '''    let now = CFAbsoluteTimeGetCurrent()
    lock.lock()
    if !completed,
       let lastBridge = lastChunkBridgeTimes[childId],
       now - lastBridge < chunkBridgeInterval {
      lock.unlock()
      return
    }
    if completed {
      lastChunkBridgeTimes[childId] = nil
    } else {
      lastChunkBridgeTimes[childId] = now
    }
    let speed = rollingSpeedLocked(
      windows: &chunkSpeedWindows,
      taskId: childId,
      totalWritten: totalWritten,
      now: now,
      completed: completed
    )
    lock.unlock()
''',
)

# Normal task speed: use exactly the same rolling model; always write zero when
# the sample is not yet credible so a stale number cannot survive indefinitely.
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    var speed: Double = 0
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
    var state = loadLocked()
''',
    '''    let speed = rollingSpeedLocked(
      windows: &taskSpeedWindows,
      taskId: id,
      totalWritten: totalWritten,
      now: now
    )
    var state = loadLocked()
''',
)
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    if speed > 0 { sample.speed = speed }
''',
    '''    sample.speed = speed
''',
)
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''    saveLocked(state)
    lock.unlock()

    postSingleTaskUpdate(
''',
    '''    saveLocked(state)
    lock.unlock()
    scheduleNativeSpeedStaleReset(taskId: id, observedAt: now)

    postSingleTaskUpdate(
''',
)

# A speed value of zero is an explicit stale/idle reading. Only -1 means
# "preserve the last value". This keeps the system task and app speed aligned.
replace_once(
    'ios/Runner/DownloadNativeWaitingQueue.swift',
    '''      if speedBytesPerSecond > 0 {
        state.sessionSpeedBytesPerSecond = speedBytesPerSecond
      }
''',
    '''      if speedBytesPerSecond >= 0 {
        state.sessionSpeedBytesPerSecond = max(speedBytesPerSecond, 0)
      }
''',
)
replace_once(
    'ios/Runner/DownloadContinuedProcessingManager.swift',
    '''    let keepSpeed = switched
      ? max(speedBytesPerSecond, 0)
      : (speedBytesPerSecond > 0
        ? speedBytesPerSecond
        : max(snapshot?.speedBytesPerSecond ?? 0, 0))
''',
    '''    let keepSpeed = switched
      ? max(speedBytesPerSecond, 0)
      : (speedBytesPerSecond >= 0
        ? speedBytesPerSecond
        : max(snapshot?.speedBytesPerSecond ?? 0, 0))
''',
)
replace_once(
    'ios/Runner/DownloadContinuedProcessingManager.swift',
    '''    if switched {
      snapshot.speedBytesPerSecond = max(speedBytesPerSecond, 0)
    } else if speedBytesPerSecond > 0 {
      snapshot.speedBytesPerSecond = speedBytesPerSecond
    }
''',
    '''    if switched {
      snapshot.speedBytesPerSecond = max(speedBytesPerSecond, 0)
    } else if speedBytesPerSecond >= 0 {
      snapshot.speedBytesPerSecond = max(speedBytesPerSecond, 0)
    }
''',
)

# 3) A logical session must not finish its iOS system task merely because one
# database/native snapshot briefly has no rows. Active transfer engines are
# explicit remaining work.
replace_once(
    'lib/core/services/download_concurrency.dart',
    '''bool downloadSessionHasRemainingWork({
  required int runningCount,
  required int waitingCount,
  int pendingWaiterPayloads = 0,
}) => runningCount > 0 || waitingCount > 0 || pendingWaiterPayloads > 0;
''',
    '''bool downloadSessionHasRemainingWork({
  required int runningCount,
  required int waitingCount,
  int pendingWaiterPayloads = 0,
  int activeEngineCount = 0,
}) =>
    runningCount > 0 ||
    waitingCount > 0 ||
    pendingWaiterPayloads > 0 ||
    activeEngineCount > 0;
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''    final hasRemaining = downloadSessionHasRemainingWork(
      runningCount: session.runningCount,
      waitingCount: session.waitingCount,
      pendingWaiterPayloads: _waitingPayloads.length,
    );
''',
    '''    var activeEngineCount = _sessionOrder.where((taskId) {
      return _parallel.isActive(taskId) ||
          _rangeTransfers.isActive(taskId) ||
          _startingTaskIds.contains(taskId);
    }).length;
    // Only pay the native lookup cost in the rare bookkeeping gap where the
    // planner sees no running/waiting row. URLSession ownership is stronger
    // evidence than a transient DB status and prevents finish->recreate churn.
    if (session.runningCount == 0 &&
        session.waitingCount == 0 &&
        _waitingPayloads.isEmpty &&
        activeEngineCount == 0) {
      try {
        final liveIds = (await _liveTransferTasks()).map((task) => task.taskId).toSet();
        activeEngineCount = _sessionOrder.where(liveIds.contains).length;
      } catch (_) {}
    }
    final hasRemaining = downloadSessionHasRemainingWork(
      runningCount: session.runningCount,
      waitingCount: session.waitingCount,
      pendingWaiterPayloads: _waitingPayloads.length,
      activeEngineCount: activeEngineCount,
    );
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''    final keepAlive = _sessionOverlayActive && session.waitingCount > 0;
    if (session.runningCount == 0 && !keepAlive) {
''',
    '''    final keepAlive =
        _sessionOverlayActive &&
        (session.waitingCount > 0 || activeEngineCount > 0);
    if (session.runningCount == 0 && !keepAlive) {
''',
)

# 4) Persistent multipart parent speed now comes from credited byte deltas over
# the same telemetry window instead of summing bursty per-child callback speeds.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''import 'download_parallel.dart';
import '../utils/download_resume.dart';
''',
    '''import 'download_parallel.dart';
import 'download_telemetry.dart';
import '../utils/download_resume.dart';
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  final DownloadConnectionGovernor _connectionGovernor =
      DownloadConnectionGovernor();
''',
    '''  final DownloadConnectionGovernor _connectionGovernor =
      DownloadConnectionGovernor();
  final DownloadTelemetryEstimator _speedTelemetry = DownloadTelemetryEstimator();
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''    _disposed = true;
    for (final session in _sessions.values) {
      session.cancelAggregateProgress();
      session.cancelDiskProgressPoll();
      session.cancelPartRetries();
    }
''',
    '''    _disposed = true;
    _speedTelemetry.clear();
    for (final session in _sessions.values) {
      session.cancelAggregateProgress();
      session.cancelDiskProgressPoll();
      session.cancelCoordinatorRecovery();
      session.cancelPartRetries();
    }
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''    final session = _sessions[task.taskId]!;
    return session.serialize(() async {
''',
    '''    final session = _sessions[task.taskId]!;
    _speedTelemetry.seed(
      task.taskId,
      transferredBytes: session.creditedBytes,
      expectedBytes: session.size,
    );
    return session.serialize(() async {
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  Future<void> _emitAggregateProgress(_ParallelSession session) async {
    final progress = session.progress;
    final nativeSpeed = session.parts.fold<double>(
      0,
      (sum, child) => sum + (child.complete ? 0 : child.speed),
    );
    final speed = nativeSpeed > 0 ? nativeSpeed : session.diskObservedSpeed;
    final timeRemaining = _aggregateTimeRemaining(session, speed);
''',
    '''  Future<void> _emitAggregateProgress(_ParallelSession session) async {
    final progress = session.progress;
    final telemetry = _speedTelemetry.observe(
      taskId: session.task.taskId,
      transferredBytes: session.creditedBytes,
      expectedBytes: session.size,
    );
    final speed = telemetry.speedBytesPerSecond > 0
        ? telemetry.speedBytesPerSecond / 1000 / 1000
        : 0.0;
    final timeRemaining = telemetry.timeRemaining;
''',
)

# Coordinator/database/file races are not a user pause. Keep healthy native
# children running and retry coordinator bookkeeping instead of pausing every
# child and changing the logical parent to paused.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  void _schedulePumpAll() {
''',
    '''  void _scheduleCoordinatorRecovery(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return;
    if (session.coordinatorRecoveryTimer != null) return;
    final generation = session.generation;
    session.coordinatorRecoveryTimer = Timer(recoveryDelay, () {
      session.coordinatorRecoveryTimer = null;
      if (_disposed) return;
      unawaited(
        session.serialize(() async {
          if (_disposed ||
              !session.active ||
              session.deleted ||
              session.generation != generation) {
            return;
          }
          try {
            await _restoreNativeOwnership(session);
          } catch (_) {}
          _scheduleDiskProgressPoll(session);
          try {
            if (!session.parentRunningReported) {
              await _status(session, TaskStatus.running);
            }
          } catch (_) {}
          try {
            await _pumpSession(session);
          } catch (_) {}
          try {
            await _persist(session);
          } catch (_) {}
          _schedulePumpAll();
        }),
      );
    });
  }

  void _schedulePumpAll() {
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''                    if (!await _pumpSession(session)) {
                      await _pause(session);
                    } else {
                      await _persist(session);
                    }
                  } catch (_) {
                    // A thrown enqueue/read used to leave the parent active with a
                    // reserved connection that had no worker behind it.
                    await _pause(session);
                  }
''',
    '''                    if (!await _pumpSession(session)) {
                      _scheduleCoordinatorRecovery(session);
                    } else {
                      await _persist(session);
                    }
                  } catch (_) {
                    // Coordinator bookkeeping is not a user-visible pause.
                    // Keep native owners untouched and reconcile them shortly.
                    _scheduleCoordinatorRecovery(session);
                  }
''',
)
# handleUpdate has one catch-all pause; replace only the first matching callback
# catch near the TaskStatus handling (the exact block is unique in this file).
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''        } catch (_) {
          if (!_disposed && !session.deleted) await _pause(session);
        }
      }),
    );
    return true;
  }
''',
    '''        } catch (_) {
          if (!_disposed && session.active && !session.deleted) {
            _scheduleCoordinatorRecovery(session);
          }
        }
      }),
    );
    return true;
  }
''',
)
# If start setup fails after native children already own connections, do not
# pause them. Recover coordinator state and keep the parent running.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''      } catch (_) {
        await _pause(session);
        return false;
      }
''',
    '''      } catch (_) {
        if (session.active && _activeConnectionsForSession(session) > 0) {
          _scheduleDiskProgressPoll(session);
          _scheduleCoordinatorRecovery(session);
          try {
            await _status(session, TaskStatus.running);
          } catch (_) {}
          return true;
        }
        await _pause(session);
        return false;
      }
''',
)
# User pause/cancel/completion explicitly clears speed/recovery timers.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  Future<bool> _pause(_ParallelSession session) async {
    session.active = false;
    session.generation++;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();
''',
    '''  Future<bool> _pause(_ParallelSession session) async {
    session.active = false;
    session.generation++;
    _speedTelemetry.resetSpeed(session.task.taskId);
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.cancelCoordinatorRecovery();
    session.resetRamp();
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();
    await session.serialize(() async {
''',
    '''    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.cancelCoordinatorRecovery();
    _speedTelemetry.remove(task.taskId);
    session.resetRamp();
    await session.serialize(() async {
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  Future<void> _finishCompleteSession(_ParallelSession session) async {
    session.active = false;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();
''',
    '''  Future<void> _finishCompleteSession(_ParallelSession session) async {
    session.active = false;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.cancelCoordinatorRecovery();
    _speedTelemetry.remove(session.task.taskId);
    session.resetRamp();
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  Timer? diskProgressTimer;
  int lastDiskObservedBytes = -1;
''',
    '''  Timer? diskProgressTimer;
  Timer? coordinatorRecoveryTimer;
  int lastDiskObservedBytes = -1;
''',
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  void cancelDiskProgressPoll() {
    diskProgressTimer?.cancel();
    diskProgressTimer = null;
    lastDiskObservedBytes = -1;
    lastDiskObservedAt = null;
    diskObservedSpeed = 0;
  }

  void resetRamp() {
''',
    '''  void cancelDiskProgressPoll() {
    diskProgressTimer?.cancel();
    diskProgressTimer = null;
    lastDiskObservedBytes = -1;
    lastDiskObservedAt = null;
    diskObservedSpeed = 0;
  }

  void cancelCoordinatorRecovery() {
    coordinatorRecoveryTimer?.cancel();
    coordinatorRecoveryTimer = null;
  }

  void resetRamp() {
''',
)

# 5) Regression coverage: behavior plus source-level guardrails for iOS runtime
# code that Flutter's Linux tests cannot execute.
Path('test/core/services/download_runtime_stability_review_test.dart').write_text(r'''import 'dart:io';

import 'package:anime_witcher/core/services/download_concurrency.dart';
import 'package:anime_witcher/core/services/download_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runtime download stability review', () {
    test('sub-second callback bursts are not reported as download speed', () {
      final estimator = DownloadTelemetryEstimator();
      final start = DateTime(2026, 9, 9, 12);
      estimator.observe(
        taskId: 'episode',
        transferredBytes: 0,
        expectedBytes: 20 * 1000 * 1000,
        now: start,
      );
      final burst = estimator.observe(
        taskId: 'episode',
        transferredBytes: 2 * 1000 * 1000,
        expectedBytes: 20 * 1000 * 1000,
        now: start.add(const Duration(milliseconds: 200)),
      );
      expect(burst.speedBytesPerSecond, 0);

      final stable = estimator.observe(
        taskId: 'episode',
        transferredBytes: 4 * 1000 * 1000,
        expectedBytes: 20 * 1000 * 1000,
        now: start.add(const Duration(seconds: 2)),
      );
      expect(stable.speedBytesPerSecond, closeTo(2 * 1000 * 1000, 1));
    });

    test('engine ownership keeps a session alive through a DB/UI gap', () {
      expect(
        downloadSessionHasRemainingWork(
          runningCount: 0,
          waitingCount: 0,
          activeEngineCount: 1,
        ),
        isTrue,
      );
      expect(
        downloadSessionHasRemainingWork(
          runningCount: 0,
          waitingCount: 0,
          activeEngineCount: 0,
        ),
        isFalse,
      );
    });

    test('iOS system task uses rolling speed and does not finish on a gap', () {
      final swift = File('ios/Runner/DownloadNativeWaitingQueue.swift')
          .readAsStringSync();
      expect(swift, contains('speedWindowInterval: CFTimeInterval = 4.0'));
      expect(swift, contains('elapsed >= speedMinimumWindow'));
      expect(swift, contains('speedStaleInterval: CFTimeInterval = 3.0'));
      expect(swift, contains('let hasKnownOutstandingEpisode'));
      expect(swift, contains('let batchStillOutstanding'));
      expect(swift, isNot(contains('lastWrites: [String: WriteSample]')));
    });

    test('multipart coordinator errors recover instead of pausing parent', () {
      final source = File(
        'lib/core/services/persistent_parallel_download.dart',
      ).readAsStringSync();
      expect(source, contains('void _scheduleCoordinatorRecovery'));
      expect(source, contains('Coordinator bookkeeping is not a user-visible pause.'));
      expect(source, contains('DownloadTelemetryEstimator _speedTelemetry'));
    });

    test('continued-processing speed zero explicitly clears stale speed', () {
      final swift = File('ios/Runner/DownloadContinuedProcessingManager.swift')
          .readAsStringSync();
      expect(swift, contains('speedBytesPerSecond >= 0'));
    });
  });
}
''')

print('download runtime stability patch applied')
