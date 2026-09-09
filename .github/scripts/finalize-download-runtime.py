from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"expected exactly one patch anchor in {path}, found {count}: {old[:120]!r}"
        )
    file.write_text(text.replace(old, new, 1))


parallel = "lib/core/services/persistent_parallel_download.dart"
replace_once(
    parallel,
    "  Future<void> _pending = Future<void>.value();\n",
    "  Future<void> _pending = Future<void>.value();\n"
    "  Future<void> parentRecordWrite = Future<void>.value();\n",
)

old_aggregate = '''  void _scheduleAggregateProgress(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return;
    session.aggregateProgressDirty = true;
    if (session.aggregateProgressTimer != null) return;

    session.aggregateProgressTimer = Timer(kParallelProgressCoalesceDelay, () {
      session.aggregateProgressTimer = null;
      if (_disposed) return;
      unawaited(
        session.serialize(() async {
          if (_disposed ||
              !session.active ||
              session.deleted ||
              !session.aggregateProgressDirty) {
            return;
          }
          session.aggregateProgressDirty = false;
          await _emitAggregateProgress(session);
        }),
      );
    });
  }

  Future<void> _emitAggregateProgress(_ParallelSession session) async {
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

    if (speed > 0) {
      final now = DateTime.now();
      final previousSample = session.lastHostProfileSampleAt;
      if (previousSample == null ||
          now.difference(previousSample) >=
              kParallelHostProfileSampleInterval) {
        session.lastHostProfileSampleAt = now;
        onHostSample?.call(
          session.task.url,
          _activeConnectionsForSession(session).clamp(1, 1 << 30),
          speed * 1000 * 1000,
        );
      }
    }

    await saveRecord(
      TaskRecord(session.task, TaskStatus.running, progress, session.size),
    );
    onUpdate(
      TaskProgressUpdate(
        session.task,
        progress,
        session.size,
        speed,
        timeRemaining,
      ),
    );
  }
'''

new_aggregate = '''  Future<void> _writeParentRecord(
    _ParallelSession session,
    TaskRecord record,
  ) {
    late final Future<void> operation;
    operation = session.parentRecordWrite.then((_) => saveRecord(record));
    session.parentRecordWrite = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        diagnosticLog?.record('parallel.parentRecordPersistFailed', {
          'taskId': session.task.taskId,
          'errorType': error.runtimeType.toString(),
        });
      },
    );
    return operation;
  }

  void _scheduleAggregateProgress(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return;
    session.aggregateProgressDirty = true;
    if (session.aggregateProgressTimer != null) return;

    // Presentation must not wait behind manifest fsync/recovery bookkeeping.
    // Snapshot on the one-second clock and publish immediately; parent DB
    // writes use their own ordered chain so a stale running write can never
    // overwrite a later pause/complete record.
    session.aggregateProgressTimer = Timer(kParallelProgressCoalesceDelay, () {
      session.aggregateProgressTimer = null;
      if (_disposed ||
          !session.active ||
          session.deleted ||
          !session.aggregateProgressDirty) {
        return;
      }
      session.aggregateProgressDirty = false;
      _emitAggregateProgress(session);
    });
  }

  void _emitAggregateProgress(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return;
    final task = session.task;
    final progress = session.progress;
    final creditedBytes = session.creditedBytes;
    final expectedBytes = session.size;
    final telemetry = _speedTelemetry.observe(
      taskId: task.taskId,
      transferredBytes: creditedBytes,
      expectedBytes: expectedBytes,
    );
    final speed = telemetry.speedBytesPerSecond > 0
        ? telemetry.speedBytesPerSecond / 1000 / 1000
        : 0.0;
    final timeRemaining = telemetry.timeRemaining;

    if (speed > 0) {
      final now = DateTime.now();
      final previousSample = session.lastHostProfileSampleAt;
      if (previousSample == null ||
          now.difference(previousSample) >=
              kParallelHostProfileSampleInterval) {
        session.lastHostProfileSampleAt = now;
        onHostSample?.call(
          task.url,
          _activeConnectionsForSession(session).clamp(1, 1 << 30),
          speed * 1000 * 1000,
        );
      }
    }

    onUpdate(
      TaskProgressUpdate(
        task,
        progress,
        expectedBytes,
        speed,
        timeRemaining,
      ),
    );
    unawaited(
      _writeParentRecord(
        session,
        TaskRecord(task, TaskStatus.running, progress, expectedBytes),
      ).catchError((Object _, StackTrace __) {}),
    );
  }
'''
replace_once(parallel, old_aggregate, new_aggregate)

replace_once(
    parallel,
    '''    await saveRecord(
      TaskRecord(session.task, status, session.progress, session.size),
    );
    onUpdate(TaskStatusUpdate(session.task, status));''',
    '''    await _writeParentRecord(
      session,
      TaskRecord(session.task, status, session.progress, session.size),
    );
    onUpdate(TaskStatusUpdate(session.task, status));''',
)

replace_once(
    parallel,
    "  Future<void> get idle => _pending;\n",
    '''  Future<void> get idle async {
    await _pending;
    await parentRecordWrite;
  }
''',
)

service = "lib/core/services/download_service.dart"
replace_once(
    service,
    '''          final fallbackSpeedBytes =
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
                    : (previous?.timeRemaining ?? Duration.zero));''',
    '''          final isAggregateMultipart = update.task is ParallelDownloadTask;
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
          // PersistentParallelDownload already owns the aggregate byte clock
          // and smoothing window. Re-estimating its synthetic parent here made
          // the card and iOS continued-processing task use different speeds.
          final measuredSpeed = isAggregateMultipart
              ? fallbackSpeedBytes
              : telemetry.speedBytesPerSecond;
          final speed = isAggregateMultipart
              ? (update.networkSpeed.isFinite && update.networkSpeed > 0
                    ? update.networkSpeed
                    : 0.0)
              : (measuredSpeed > 0
                    ? measuredSpeed / 1000000
                    : (_telemetry.hasRecentBytes(update.task.taskId)
                          ? -1.0
                          : 0.0));
          final remaining = isAggregateMultipart
              ? update.timeRemaining
              : (telemetry.timeRemaining > Duration.zero
                    ? telemetry.timeRemaining
                    : (update.timeRemaining > Duration.zero
                          ? update.timeRemaining
                          : (previous?.timeRemaining ?? Duration.zero)));''',
)

progress_test = "test/core/services/persistent_parallel_download_progress_test.dart"
text = Path(progress_test).read_text()
anchor = "\n  test('pause cancels a pending aggregate progress emission', () async {"
if text.count(anchor) != 1:
    raise SystemExit("progress test anchor not found exactly once")
new_test = r'''

  test('parent progress is not blocked by slow record persistence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'parallel-progress-nonblocking-',
    );
    final parent = ParallelDownloadTask(
      taskId: 'parallel-progress-nonblocking',
      url: 'https://example.com/video',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 1,
      allowPause: true,
    );
    final records = <String, TaskRecord>{};
    final starts = <DownloadTask>[];
    final updates = <TaskUpdate>[];
    final blockedWrite = Completer<void>();
    var blockRunningParentWrite = false;
    final coordinator = PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        return true;
      },
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (record) async {
        if (blockRunningParentWrite &&
            record.task.taskId == parent.taskId &&
            record.status == TaskStatus.running) {
          await blockedWrite.future;
        }
        records[record.task.taskId] = record;
      },
      recordForId: (id) async => records[id],
      onUpdate: updates.add,
      onPartProgress: (_, _, _) {},
    );

    try {
      expect(await coordinator.start(parent, 1000000), isTrue);
      final child = starts.single;
      coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.running));
      await waitUntil(() => coordinator.activeConnectionCount == 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      updates.clear();
      blockRunningParentWrite = true;

      coordinator.handleUpdate(
        TaskProgressUpdate(
          child,
          0.25,
          1000000,
          0.5,
          const Duration(seconds: 2),
        ),
      );

      await Future<void>.delayed(
        kParallelProgressCoalesceDelay + const Duration(milliseconds: 150),
      );
      expect(
        updates.whereType<TaskProgressUpdate>(),
        isNotEmpty,
        reason: 'UI telemetry must publish before the DB write completes',
      );
    } finally {
      if (!blockedWrite.isCompleted) blockedWrite.complete();
      await coordinator.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
'''
Path(progress_test).write_text(text.replace(anchor, new_test + anchor, 1))

runtime_test = "test/core/services/download_runtime_stability_review_test.dart"
text = Path(runtime_test).read_text()
anchor = "\n    test('continued-processing speed zero explicitly clears stale speed', () {"
if text.count(anchor) != 1:
    raise SystemExit("runtime test anchor not found exactly once")
new_runtime_tests = r'''

    test('multipart parent presentation clock is not serialized behind IO', () {
      final source = File('lib/core/services/persistent_parallel_download.dart')
          .readAsStringSync();
      final start = source.indexOf('void _scheduleAggregateProgress(');
      final end = source.indexOf('Duration _aggregateTimeRemaining', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final section = source.substring(start, end);
      expect(section, isNot(contains('session.serialize(')));
      expect(section, contains('void _emitAggregateProgress('));
      expect(section, contains('_writeParentRecord('));
    });

    test('multipart card uses coordinator speed as the canonical speed', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      expect(
        source,
        contains('final isAggregateMultipart = update.task is ParallelDownloadTask;'),
      );
      expect(source, contains('final measuredSpeed = isAggregateMultipart'));
      expect(source, contains('? update.networkSpeed'));
    });
'''
Path(runtime_test).write_text(text.replace(anchor, new_runtime_tests + anchor, 1))
