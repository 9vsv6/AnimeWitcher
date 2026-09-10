from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, found {count}')
    file.write_text(text.replace(old, new, 1))


def insert_before_once(path: str, marker: str, addition: str) -> None:
    file = Path(path)
    text = file.read_text()
    if text.count(marker) != 1:
        raise SystemExit(f'{path}: insertion marker count={text.count(marker)}')
    file.write_text(text.replace(marker, addition + marker, 1))


state_path = 'lib/core/services/download_job_state.dart'
insert_before_once(
    state_path,
    '/// Identifies one concrete execution attempt of a logical episode.\n',
    r'''/// Reconcile executor evidence against an existing durable logical job.
///
/// Once a DownloadJobStore record exists it is the authority for user intent
/// and logical queue ownership. Plugin/URLSession status is still authoritative
/// for *live execution ownership*, but stale executor rows may not erase a
/// durable user pause, waiter, terminal state, or interrupted job.
DownloadRecoveryPlan planDownloadRecoveryWithJobAuthority({
  required TaskStatus persisted,
  required bool queueWaiting,
  required bool userPaused,
  required bool stillInNativeQueue,
  required bool hasMetadata,
  DownloadJobState? authoritativeState,
  bool authoritativeUserPaused = false,
  bool authoritativeQueueWaiting = false,
}) {
  if (authoritativeState == null) {
    return planDownloadRecovery(
      persisted: persisted,
      queueWaiting: queueWaiting,
      userPaused: userPaused,
      stillInNativeQueue: stillInNativeQueue,
      hasMetadata: hasMetadata,
    );
  }

  switch (authoritativeState) {
    case DownloadJobState.completed:
    case DownloadJobState.canceled:
    case DownloadJobState.orphaned:
      return DownloadRecoveryPlan(
        state: authoritativeState,
        action: DownloadRecoveryAction.ignore,
      );
    default:
      break;
  }

  // Keep legacy userPaused=true as migration evidence too. A pause is safer to
  // preserve than to accidentally turn into network activity after relaunch.
  if (authoritativeUserPaused ||
      userPaused ||
      authoritativeState == DownloadJobState.pausedByUser ||
      authoritativeState == DownloadJobState.pausing) {
    return const DownloadRecoveryPlan(
      state: DownloadJobState.pausedByUser,
      action: DownloadRecoveryAction.keepPaused,
    );
  }

  if (stillInNativeQueue) {
    final state = switch (authoritativeState) {
      DownloadJobState.queued => DownloadJobState.queued,
      DownloadJobState.starting => DownloadJobState.starting,
      DownloadJobState.retryWaiting => DownloadJobState.retryWaiting,
      DownloadJobState.assembling => DownloadJobState.assembling,
      DownloadJobState.verifying => DownloadJobState.verifying,
      _ => DownloadJobState.running,
    };
    return DownloadRecoveryPlan(
      state: state,
      action: DownloadRecoveryAction.keepNative,
    );
  }

  if (authoritativeQueueWaiting ||
      authoritativeState == DownloadJobState.queued) {
    return const DownloadRecoveryPlan(
      state: DownloadJobState.queued,
      action: DownloadRecoveryAction.requeue,
    );
  }

  return const DownloadRecoveryPlan(
    state: DownloadJobState.interrupted,
    action: DownloadRecoveryAction.requeue,
  );
}

''',
)

service_path = 'lib/core/services/download_service.dart'
insert_before_once(
    service_path,
    '  Future<void> _recoverPersistedDownloads() async {\n',
    r'''  /// Persist lifecycle boundaries for the logical episode without turning
  /// hot progress callbacks into Hive writes. Durable bytes are monotonic and
  /// identity evidence from an existing job is never discarded.
  Future<void> _checkpointLogicalJob(
    DownloadTask task, {
    required DownloadJobState state,
    int? durableBytes,
    int? expectedBytes,
    bool? userPaused,
    bool? queueWaiting,
  }) async {
    try {
      final current = await _jobStore.get(task.taskId);
      final currentBytes = current?.durableBytes ?? 0;
      final incomingBytes = durableBytes ?? 0;
      final keptBytes = incomingBytes > currentBytes
          ? incomingBytes
          : currentBytes;
      final keptExpected = knownDownloadSize(<int?>[
        expectedBytes,
        current?.expectedBytes,
      ]);
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = current == null
          ? DownloadJobRecord(
              taskId: task.taskId,
              trackingUrl: downloadTrackingUrl(task),
              state: state,
              generation: 0,
              durableBytes: keptBytes,
              expectedBytes: keptExpected,
              userPaused: userPaused ?? false,
              queueWaiting: queueWaiting ?? false,
              updatedAtMillis: now,
              fingerprint: DownloadResourceFingerprint(
                expectedBytes: keptExpected,
                finalUrl: task.url,
              ),
            )
          : current.copyWith(
              state: state,
              durableBytes: keptBytes,
              expectedBytes: keptExpected > 0
                  ? keptExpected
                  : current.expectedBytes,
              userPaused: userPaused ?? current.userPaused,
              queueWaiting: queueWaiting ?? current.queueWaiting,
              updatedAtMillis: now,
            );
      if (!await _jobStore.put(next)) {
        diagnosticLog.record('job.checkpointRejected', {
          'taskId': task.taskId,
          'status': state.name,
        });
      }
    } catch (error) {
      diagnosticLog.record('job.checkpointError', {
        'taskId': task.taskId,
        'status': state.name,
        'errorType': error.runtimeType.toString(),
      });
    }
  }

''',
)

replace_once(
    service_path,
    r'''      final metadata = await storage.getDownloadMetadata(task.taskId);
      final userPausedMeta = isUserPausedMetadata(metadata);
      if (record.status == TaskStatus.complete) {
        continue;
      }
      if (record.status == TaskStatus.canceled &&
          metadata == null &&
          !userPausedMeta) {
        continue;
      }
      final queueWaiting = isQueueWaitingMetadata(metadata);
''',
    r'''      final metadata = await storage.getDownloadMetadata(task.taskId);
      // JobStore is read before any legacy/plugin early-exit. A stale canceled
      // executor row must not hide a durable logical job after process death.
      final oldJob = await _jobStore.get(task.taskId);
      final userPausedMeta = isUserPausedMetadata(metadata);
      if (record.status == TaskStatus.complete) {
        continue;
      }
      if (record.status == TaskStatus.canceled &&
          metadata == null &&
          oldJob == null &&
          !userPausedMeta) {
        continue;
      }
      final legacyQueueWaiting = isQueueWaitingMetadata(metadata);
      final queueWaiting = oldJob == null
          ? legacyQueueWaiting
          : oldJob.queueWaiting || oldJob.state == DownloadJobState.queued;
''',
)

replace_once(
    service_path,
    r'''      final userPaused =
          isUserPausedMetadata(metadata) ||
          _userPausedIds.contains(task.taskId);
      final recoveryPlan = planDownloadRecovery(
        persisted: record.status,
        queueWaiting: queueWaiting,
        userPaused: userPaused,
        stillInNativeQueue: stillNative,
        hasMetadata: metadata != null,
      );
''',
    r'''      final userPaused =
          isUserPausedMetadata(metadata) ||
          _userPausedIds.contains(task.taskId) ||
          oldJob?.userPaused == true ||
          oldJob?.state == DownloadJobState.pausedByUser ||
          oldJob?.state == DownloadJobState.pausing;
      final recoveryPlan = planDownloadRecoveryWithJobAuthority(
        persisted: record.status,
        queueWaiting: queueWaiting,
        userPaused: userPaused,
        stillInNativeQueue: stillNative,
        hasMetadata: metadata != null,
        authoritativeState: oldJob?.state,
        authoritativeUserPaused: oldJob?.userPaused ?? false,
        authoritativeQueueWaiting: oldJob?.queueWaiting ?? false,
      );
''',
)

replace_once(
    service_path,
    r'''      final expectedBytes = knownDownloadSize(<int?>[
        saved.totalSize,
        record.expectedFileSize,
        downloadMetadataExpectedBytes(metadata),
      ]);
      var durableBytes = saved.partialBytes;
      if (task is ParallelDownloadTask && expectedBytes > 0) {
        durableBytes = (progress * expectedBytes).floor();
      }
      final oldJob = await _jobStore.get(task.taskId);
      if (oldJob != null && oldJob.durableBytes > durableBytes) {
''',
    r'''      final expectedBytes = knownDownloadSize(<int?>[
        saved.totalSize,
        record.expectedFileSize,
        downloadMetadataExpectedBytes(metadata),
        oldJob?.expectedBytes,
      ]);
      var durableBytes = saved.partialBytes;
      if (task is ParallelDownloadTask && expectedBytes > 0) {
        durableBytes = (progress * expectedBytes).floor();
      }
      if (oldJob != null && oldJob.durableBytes > durableBytes) {
''',
)

replace_once(
    service_path,
    r'''      await _jobStore.put(migratedJob);

      if (userPaused) {
''',
    r'''      await _jobStore.put(migratedJob);

      if (oldJob != null &&
          recoveryPlan.action == DownloadRecoveryAction.ignore) {
        _queueWaitingIds.remove(task.taskId);
        _waitingPayloads.remove(task.taskId);
        _forgetSessionTask(task.taskId);
        continue;
      }

      if (userPaused) {
''',
)

replace_once(
    service_path,
    r'''    final status = transferring
        ? TaskStatus.running
        : (record?.status ?? TaskStatus.enqueued);
    _publishProgress(
''',
    r'''    final status = transferring
        ? TaskStatus.running
        : (record?.status ?? TaskStatus.enqueued);
    if (!_userPausedIds.contains(attached.taskId)) {
      final durableBytes = totalSize > 0 && progress > 0
          ? (totalSize * progress).floor()
          : 0;
      await _checkpointLogicalJob(
        attached,
        state: transferring
            ? DownloadJobState.running
            : DownloadJobState.starting,
        durableBytes: durableBytes,
        expectedBytes: totalSize,
        userPaused: false,
        queueWaiting: false,
      );
    }
    _publishProgress(
''',
)

replace_once(
    service_path,
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(task.taskId, queueWaiting: true);
    await FileDownloader().database.updateRecord(
''',
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(task.taskId, queueWaiting: true);
    await _checkpointLogicalJob(
      task,
      state: DownloadJobState.queued,
      expectedBytes: totalSize,
      userPaused: false,
      queueWaiting: true,
    );
    await FileDownloader().database.updateRecord(
''',
)

replace_once(
    service_path,
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(
          task.taskId,
          lastProgress: progress,
          lastExpectedBytes: totalSize,
        );

    _ref.read(activeDownloadsProvider.notifier).add(trackingUrl);
''',
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(
          task.taskId,
          lastProgress: progress,
          lastExpectedBytes: totalSize,
        );
    await _checkpointLogicalJob(
      task,
      state: DownloadJobState.interrupted,
      durableBytes: totalSize > 0 && progress > 0
          ? (totalSize * progress).floor()
          : 0,
      expectedBytes: totalSize,
      userPaused: false,
      queueWaiting: false,
    );

    _ref.read(activeDownloadsProvider.notifier).add(trackingUrl);
''',
)

replace_once(
    service_path,
    r'''      if (downloadTask != null) {
        // Plugin pause produces URLSession resumeData and drops the
''',
    r'''      if (downloadTask != null) {
        await _checkpointLogicalJob(
          downloadTask,
          state: DownloadJobState.pausing,
          userPaused: true,
          queueWaiting: false,
        );
        // Plugin pause produces URLSession resumeData and drops the
''',
)

replace_once(
    service_path,
    r'''        if (!didPause) {
          _userPausedIds.remove(taskId);
          await _ref
              .read(storageServiceProvider)
              .patchDownloadMetadata(
                taskId,
                queueWaiting: false,
                userPaused: false,
                lastProgress: progress,
                lastExpectedBytes: totalSize,
              );
          _publishProgress(
''',
    r'''        if (!didPause) {
          _userPausedIds.remove(taskId);
          await _ref
              .read(storageServiceProvider)
              .patchDownloadMetadata(
                taskId,
                queueWaiting: false,
                userPaused: false,
                lastProgress: progress,
                lastExpectedBytes: totalSize,
              );
          await _checkpointLogicalJob(
            downloadTask,
            state: DownloadJobState.running,
            durableBytes: totalSize > 0 && progress > 0
                ? (totalSize * progress).floor()
                : 0,
            expectedBytes: totalSize,
            userPaused: false,
            queueWaiting: false,
          );
          _publishProgress(
''',
)

replace_once(
    service_path,
    r'''        await _ref
            .read(storageServiceProvider)
            .patchDownloadMetadata(
              taskId,
              queueWaiting: false,
              userPaused: true,
              lastProgress: progress,
              lastExpectedBytes: totalSize,
            );
        _publishProgress(
''',
    r'''        await _ref
            .read(storageServiceProvider)
            .patchDownloadMetadata(
              taskId,
              queueWaiting: false,
              userPaused: true,
              lastProgress: progress,
              lastExpectedBytes: totalSize,
            );
        await _checkpointLogicalJob(
          downloadTask,
          state: DownloadJobState.pausedByUser,
          durableBytes: totalSize > 0 && progress > 0
              ? (totalSize * progress).floor()
              : 0,
          expectedBytes: totalSize,
          userPaused: true,
          queueWaiting: false,
        );
        _publishProgress(
''',
)

replace_once(
    service_path,
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(taskId, queueWaiting: false, userPaused: false);

    final max = clampDownloadConcurrency(
''',
    r'''    await _ref
        .read(storageServiceProvider)
        .patchDownloadMetadata(taskId, queueWaiting: false, userPaused: false);
    await _checkpointLogicalJob(
      downloadTask,
      state: DownloadJobState.starting,
      userPaused: false,
      queueWaiting: false,
    );

    final max = clampDownloadConcurrency(
''',
)

replace_once(
    service_path,
    r'''        if (!started) {
          final saved = await _savedProgressFor(downloadTask);
          await FileDownloader().database.updateRecord(
''',
    r'''        if (!started) {
          final saved = await _savedProgressFor(downloadTask);
          await _checkpointLogicalJob(
            downloadTask,
            state: DownloadJobState.interrupted,
            durableBytes: saved.totalSize > 0 && saved.progress > 0
                ? (saved.totalSize * saved.progress).floor()
                : saved.partialBytes,
            expectedBytes: saved.totalSize,
            userPaused: false,
            queueWaiting: false,
          );
          await FileDownloader().database.updateRecord(
''',
)

replace_once(
    service_path,
    r'''        if (!success) {
          _waitingPayloads.remove(task.taskId);
          await FileDownloader().database.updateRecord(
''',
    r'''        if (!success) {
          _waitingPayloads.remove(task.taskId);
          await _checkpointLogicalJob(
            transferTask,
            state: DownloadJobState.interrupted,
            expectedBytes: expectedBytes,
            userPaused: false,
            queueWaiting: false,
          );
          await FileDownloader().database.updateRecord(
''',
)

replace_once(
    service_path,
    r'''        final storage = _ref.read(storageServiceProvider);
        await storage.removeDownloadMetadata(task.taskId);
        _ref.read(activeDownloadsProvider.notifier).remove(trackingUrl ?? url);
''',
    r'''        final storage = _ref.read(storageServiceProvider);
        await storage.removeDownloadMetadata(task.taskId);
        // A start that never established recoverable ownership must not leave
        // an authoritative JobStore row that resurrects itself on relaunch.
        await _jobStore.remove(task.taskId);
        _ref.read(activeDownloadsProvider.notifier).remove(trackingUrl ?? url);
''',
)

replace_once(
    service_path,
    r'''  Future<void> _persistCompletedFilePath(Task task) async {
    try {
      final path = await task.filePath();
      await _ref
          .read(storageServiceProvider)
          .patchDownloadMetadata(
            task.taskId,
            trackingUrl: downloadTrackingUrl(task),
            filePath: path,
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DownloadService] persist filePath failed: $e');
      }
    }
  }
''',
    r'''  Future<void> _persistCompletedFilePath(Task task) async {
    try {
      final path = await task.filePath();
      var fileBytes = -1;
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) fileBytes = await file.length();
      }
      final record = await FileDownloader().database.recordForId(task.taskId);
      final expectedBytes = knownDownloadSize(<int?>[
        fileBytes,
        record?.expectedFileSize,
        _telemetry.expectedBytesFor(task.taskId),
      ]);
      await _ref
          .read(storageServiceProvider)
          .patchDownloadMetadata(
            task.taskId,
            trackingUrl: downloadTrackingUrl(task),
            filePath: path,
            lastProgress: 1,
            lastExpectedBytes: expectedBytes,
          );
      if (task is DownloadTask) {
        await _checkpointLogicalJob(
          task,
          state: DownloadJobState.completed,
          durableBytes: expectedBytes > 0 ? expectedBytes : fileBytes,
          expectedBytes: expectedBytes,
          userPaused: false,
          queueWaiting: false,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DownloadService] persist filePath failed: $e');
      }
    }
  }
''',
)

# Pure state-machine regression coverage.
state_test = 'test/core/services/download_job_state_test.dart'
insert_before_once(
    state_test,
    "  group('download attempt fence', () {\n",
    r'''  group('DownloadJobStore recovery authority', () {
    test('authoritative user pause beats stale live executor state', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.running,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: false,
        authoritativeState: DownloadJobState.pausedByUser,
        authoritativeUserPaused: true,
      );
      expect(plan.state, DownloadJobState.pausedByUser);
      expect(plan.action, DownloadRecoveryAction.keepPaused);
    });

    test('authoritative interrupted work revives without legacy metadata', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.canceled,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: false,
        authoritativeState: DownloadJobState.running,
      );
      expect(plan.state, DownloadJobState.interrupted);
      expect(plan.action, DownloadRecoveryAction.requeue);
    });

    test('authoritative waiter attaches to native ownership without reenqueue', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.paused,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: false,
        authoritativeState: DownloadJobState.queued,
        authoritativeQueueWaiting: true,
      );
      expect(plan.state, DownloadJobState.queued);
      expect(plan.action, DownloadRecoveryAction.keepNative);
      expect(plan.shouldRequeue, isFalse);
    });

    test('terminal authoritative jobs are never revived by stale executor rows', () {
      for (final state in <DownloadJobState>[
        DownloadJobState.completed,
        DownloadJobState.canceled,
        DownloadJobState.orphaned,
      ]) {
        final plan = planDownloadRecoveryWithJobAuthority(
          persisted: TaskStatus.running,
          queueWaiting: true,
          userPaused: false,
          stillInNativeQueue: true,
          hasMetadata: true,
          authoritativeState: state,
        );
        expect(plan.state, state, reason: state.name);
        expect(plan.action, DownloadRecoveryAction.ignore, reason: state.name);
      }
    });

    test('missing authority preserves legacy migration behavior', () {
      final legacy = planDownloadRecovery(
        persisted: TaskStatus.failed,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
      );
      final migrated = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.failed,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
      );
      expect(migrated.state, legacy.state);
      expect(migrated.action, legacy.action);
    });
  });

''',
)

runtime_test = 'test/core/services/download_runtime_stability_review_test.dart'
replace_once(
    runtime_test,
    r'''    test(
      'continued-processing metric updates are coalesced to one per second',
      () {
        final source = File(
          'lib/core/services/download_continued_processing_service.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('_updateSampleInterval = Duration(seconds: 1)'),
        );
        expect(source, contains('Future<void> _queueUpdate('));
        expect(source, contains('_pendingUpdate = arguments'));
        expect(source, contains('_cancelPendingUpdate();'));
      },
    );
''',
    r'''    test(
      'continued-processing metric updates are coalesced to one per second',
      () {
        final source = File(
          'lib/core/services/download_continued_processing_service.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('_updateSampleInterval = Duration(seconds: 1)'),
        );
        expect(source, contains('Future<void> _queueUpdate('));
        expect(source, contains('_pendingUpdate = arguments'));
        expect(source, contains('_cancelPendingUpdate();'));
      },
    );

    test('startup reconciliation reads JobStore before legacy cancel filtering', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      final start = source.indexOf('Future<void> _recoverPersistedDownloads()');
      final end = source.indexOf('int _occupiedSlotCount(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final recovery = source.substring(start, end);
      final jobRead = recovery.indexOf(
        'final oldJob = await _jobStore.get(task.taskId);',
      );
      final canceledFilter = recovery.indexOf(
        'record.status == TaskStatus.canceled',
      );
      expect(jobRead, greaterThanOrEqualTo(0));
      expect(canceledFilter, greaterThan(jobRead));
      expect(recovery, contains('planDownloadRecoveryWithJobAuthority('));
      expect(recovery, contains('oldJob?.expectedBytes'));
      expect(recovery, contains('oldJob?.userPaused == true'));
    });

    test('logical lifecycle boundaries checkpoint authoritative JobStore state', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      expect(source, contains('Future<void> _checkpointLogicalJob('));
      expect(source, contains('state: DownloadJobState.pausing'));
      expect(source, contains('state: DownloadJobState.pausedByUser'));
      expect(source, contains('state: DownloadJobState.starting'));
      expect(source, contains('state: DownloadJobState.queued'));
      expect(source, contains('state: DownloadJobState.interrupted'));
      expect(source, contains('state: DownloadJobState.completed'));
      expect(source, contains('await _jobStore.remove(task.taskId);'));
    });
''',
)

print('DownloadJobStore authority phase applied')
