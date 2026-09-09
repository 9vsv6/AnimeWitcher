from pathlib import Path

source_path = Path('lib/core/services/persistent_parallel_download.dart')
source = source_path.read_text()
marker = 'kParallelDiskProgressPollInterval'

if marker not in source:
    replacements = [
        (
            "const Duration kParallelHostProfileSampleInterval = Duration(seconds: 5);\n",
            """const Duration kParallelHostProfileSampleInterval = Duration(seconds: 5);

/// iOS URLSession can keep writing/finalizing a child Range while its Dart
/// progress/status callbacks are delayed or lost. Poll only visible final part
/// paths as a fallback so durable bytes can wake the logical parent, advance
/// slow-start and update the UI without restarting any Range.
const Duration kParallelDiskProgressPollInterval = Duration(seconds: 1);
""",
        ),
        (
            """    this.recoveryDelay = const Duration(seconds: 1),
    this.tailStallDelay = kParallelTailStallDelay,
    this.maxActiveConnections = kDownloadGlobalConnectionBudget,
""",
            """    this.recoveryDelay = const Duration(seconds: 1),
    this.tailStallDelay = kParallelTailStallDelay,
    this.diskProgressPollInterval = kParallelDiskProgressPollInterval,
    this.maxActiveConnections = kDownloadGlobalConnectionBudget,
""",
        ),
        (
            """  final Duration recoveryDelay;
  final Duration tailStallDelay;
  final void Function(String url, int fallbackCeiling)? onHostPressure;
""",
            """  final Duration recoveryDelay;
  final Duration tailStallDelay;
  final Duration diskProgressPollInterval;
  final void Function(String url, int fallbackCeiling)? onHostPressure;
""",
        ),
        (
            """    for (final session in _sessions.values) {
      session.cancelAggregateProgress();
      session.cancelPartRetries();
    }
""",
            """    for (final session in _sessions.values) {
      session.cancelAggregateProgress();
      session.cancelDiskProgressPoll();
      session.cancelPartRetries();
    }
""",
        ),
        (
            """        if (!await _pumpSession(session)) {
          throw StateError('Could not start initial download connection');
        }
        await _persist(session);
""",
            """        if (!await _pumpSession(session)) {
          throw StateError('Could not start initial download connection');
        }
        _scheduleDiskProgressPoll(session);
        await _persist(session);
""",
        ),
        (
            "  void _scheduleAggregateProgress(_ParallelSession session) {\n",
            """  void _scheduleDiskProgressPoll(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return;
    if (session.diskProgressTimer != null) return;

    if (session.lastDiskObservedBytes < 0) {
      session.lastDiskObservedBytes = session.creditedBytes;
      session.lastDiskObservedAt = DateTime.now();
    }
    session.diskProgressTimer = Timer(diskProgressPollInterval, () {
      session.diskProgressTimer = null;
      if (_disposed) return;
      unawaited(
        session.serialize(() async {
          if (_disposed || !session.active || session.deleted) return;
          try {
            await _pollDiskProgress(session);
          } catch (_) {
            // This is only a fallback for missing native callbacks. A transient
            // file move/read race must never pause a healthy parent download.
          } finally {
            if (!_disposed && session.active && !session.deleted) {
              _scheduleDiskProgressPoll(session);
            }
          }
        }),
      );
    });
  }

  Future<void> _pollDiskProgress(_ParallelSession session) async {
    var changed = false;

    for (final part in session.parts) {
      if (part.complete) continue;
      try {
        final file = File(await part.task.filePath());
        if (!await file.exists()) continue;
        final bytes = await file.length();
        if (bytes <= 0 || bytes > part.size) continue;

        if (bytes == part.size &&
            await _adoptExactSizePart(
              session,
              part,
              settleNativeOwner: part.launched,
            )) {
          changed = true;
          continue;
        }

        final diskProgress = (bytes / part.size).clamp(0.0, 1.0).toDouble();
        if (diskProgress <= part.credibleProgress) continue;

        part.credibleProgress = diskProgress;
        if (part.progress >= kParallelNativeCompletionSentinel ||
            diskProgress > part.progress) {
          part.progress = diskProgress;
        }
        part.recoveryAttempts = 0;
        part.tailRecoveryAttempted = false;
        if (part.launched) _markConnectionReady(session, part);
        onPartProgress(
          session.task.taskId,
          part.task.taskId,
          part.credibleProgress,
        );
        changed = true;
      } on FileSystemException {
        // URLSession may atomically move a child while it is sampled.
      }
    }

    final now = DateTime.now();
    final creditedBytes = session.creditedBytes;
    final previousBytes = session.lastDiskObservedBytes;
    final previousAt = session.lastDiskObservedAt;
    if (previousBytes >= 0 && previousAt != null) {
      final elapsedMicros = now.difference(previousAt).inMicroseconds;
      final deltaBytes = creditedBytes - previousBytes;
      if (elapsedMicros > 0 && deltaBytes > 0) {
        session.diskObservedSpeed =
            deltaBytes * Duration.microsecondsPerSecond /
            elapsedMicros /
            1000 /
            1000;
      } else if (deltaBytes <= 0) {
        session.diskObservedSpeed = 0;
      }
    }
    session.lastDiskObservedBytes = creditedBytes;
    session.lastDiskObservedAt = now;

    if (!changed) return;
    await _persist(session);
    if (session.parts.every((part) => part.complete)) {
      await _assemble(session);
      return;
    }
    if (!session.parentRunningReported) {
      await _status(session, TaskStatus.running);
    }
    await _emitAggregateProgress(session);
    _schedulePumpAll();
  }

  void _scheduleAggregateProgress(_ParallelSession session) {
""",
        ),
        (
            """    final speed = session.parts.fold<double>(
      0,
      (sum, child) => sum + (child.complete ? 0 : child.speed),
    );
""",
            """    final nativeSpeed = session.parts.fold<double>(
      0,
      (sum, child) => sum + (child.complete ? 0 : child.speed),
    );
    final speed = nativeSpeed > 0 ? nativeSpeed : session.diskObservedSpeed;
""",
        ),
        (
            """  Future<void> _pause(_ParallelSession session) async {
    session.active = false;
    session.generation++;
    session.cancelAggregateProgress();
""",
            """  Future<void> _pause(_ParallelSession session) async {
    session.active = false;
    session.generation++;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
""",
        ),
        (
            """    session.deleted = true;
    session.active = false;
    session.cancelAggregateProgress();
    session.resetRamp();
""",
            """    session.deleted = true;
    session.active = false;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();
""",
        ),
        (
            """  Future<void> _status(_ParallelSession session, TaskStatus status) async {
    await saveRecord(
""",
            """  Future<void> _status(_ParallelSession session, TaskStatus status) async {
    if (status == TaskStatus.running) {
      session.parentRunningReported = true;
    } else if (status == TaskStatus.enqueued || status == TaskStatus.paused) {
      session.parentRunningReported = false;
    }
    await saveRecord(
""",
        ),
        (
            """  Future<void> _finishCompleteSession(_ParallelSession session) async {
    session.active = false;
    session.cancelAggregateProgress();
    session.resetRamp();
""",
            """  Future<void> _finishCompleteSession(_ParallelSession session) async {
    session.active = false;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();
""",
        ),
        (
            """  Timer? aggregateProgressTimer;
  bool aggregateProgressDirty = false;
  DateTime? lastHostProfileSampleAt;
""",
            """  Timer? aggregateProgressTimer;
  bool aggregateProgressDirty = false;
  Timer? diskProgressTimer;
  int lastDiskObservedBytes = -1;
  DateTime? lastDiskObservedAt;
  double diskObservedSpeed = 0;
  bool parentRunningReported = false;
  DateTime? lastHostProfileSampleAt;
""",
        ),
        (
            """  int get size => parts.fold(0, (sum, part) => sum + part.size);
  double get progress =>
""",
            """  int get size => parts.fold(0, (sum, part) => sum + part.size);
  int get creditedBytes => parts.fold<int>(
    0,
    (sum, part) =>
        sum +
        (part.complete
            ? part.size
            : (part.size * part.credibleProgress).floor()),
  );
  double get progress =>
""",
        ),
        (
            "  void resetRamp() {\n",
            """  void cancelDiskProgressPoll() {
    diskProgressTimer?.cancel();
    diskProgressTimer = null;
    lastDiskObservedBytes = -1;
    lastDiskObservedAt = null;
    diskObservedSpeed = 0;
  }

  void resetRamp() {
""",
        ),
    ]

    for old, new in replacements:
        count = source.count(old)
        if count != 1:
            raise SystemExit(f'source anchor expected once, got {count}: {old[:90]!r}')
        source = source.replace(old, new, 1)
    source_path.write_text(source)


test_path = Path('test/core/services/persistent_parallel_download_test.dart')
test = test_path.read_text()
test_marker = 'visible part bytes wake a parent when native callbacks are missing'

if test_marker not in test:
    old = """  PersistentParallelDownload create({int maxActiveConnections = 16}) =>
      PersistentParallelDownload(
"""
    new = """  PersistentParallelDownload create({
    int maxActiveConnections = 16,
    Duration diskProgressPollInterval = const Duration(seconds: 1),
  }) => PersistentParallelDownload(
"""
    if test.count(old) != 1:
        raise SystemExit('test create anchor mismatch')
    test = test.replace(old, new, 1)

    old = """        recoveryDelay: const Duration(milliseconds: 10),
      );
"""
    new = """        recoveryDelay: const Duration(milliseconds: 10),
        diskProgressPollInterval: diskProgressPollInterval,
      );
"""
    if test.count(old) != 1:
        raise SystemExit('test constructor anchor mismatch')
    test = test.replace(old, new, 1)

    anchor = """  test(
    'repeated system pauses recover only the affected identity',
"""
    addition = """  test(
    'visible part bytes wake a parent when native callbacks are missing',
    () async {
      await coordinator.dispose();
      coordinator = create(
        diskProgressPollInterval: const Duration(milliseconds: 10),
      );

      expect(await coordinator.start(parent, 100), isTrue);
      expect(starts.length, 1);
      final first = starts.single;
      final file = File(await first.filePath());
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(10, 7), flush: true);

      await waitUntil(() => (records[parent.taskId]?.progress ?? 0) > 0);
      final parentRecord = records[parent.taskId]!;
      expect(parentRecord.status, TaskStatus.running);
      expect(parentRecord.progress, closeTo(.1, .001));
      expect(statuses, contains(TaskStatus.running));
      await waitUntil(() => starts.length >= 3);
    },
  );

  test(
    'exact visible part is adopted when native completion callback is lost',
    () async {
      await coordinator.dispose();
      coordinator = create(
        diskProgressPollInterval: const Duration(milliseconds: 10),
      );

      expect(await coordinator.start(parent, 100), isTrue);
      final first = starts.single;
      final file = File(await first.filePath());
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(20, 9), flush: true);

      await waitUntil(
        () => records[first.taskId]?.status == TaskStatus.complete,
      );
      expect(coordinator.progressFor(parent.taskId), greaterThanOrEqualTo(.2));
      expect(pauses, contains(first.taskId));
      await waitUntil(() => starts.length >= 3);
    },
  );

"""
    if test.count(anchor) != 1:
        raise SystemExit('test insertion anchor mismatch')
    test = test.replace(anchor, addition + anchor, 1)
    test_path.write_text(test)
