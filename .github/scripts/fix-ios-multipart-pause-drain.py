from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))


def replace_regex(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: regex match count={count}: {pattern[:120]!r}")
    write(path, updated)


parallel = 'lib/core/services/persistent_parallel_download.dart'
service = 'lib/core/services/download_service.dart'
test = 'test/core/services/persistent_parallel_download_test.dart'
runtime_test = 'test/core/services/download_runtime_stability_review_test.dart'

# The iOS plugin implements pause by cancelByProducingResumeData(). If Apple
# returns nil resumeData the URLSession task is already cancelled, which loses
# its temp-file prefix. Give user/system pause a non-destructive mode: stop new
# multipart launches, but let already-owned native Range children drain to a
# durable .part boundary instead of asking the plugin to cancel them.
replace_once(
    parallel,
    '    this.verifyPartSource,\n    this.recoveryDelay = const Duration(seconds: 1),\n',
    '    this.verifyPartSource,\n    this.shouldDrainPartOnPause,\n    this.onPausedDrainSettled,\n    this.recoveryDelay = const Duration(seconds: 1),\n',
)
replace_once(
    parallel,
    '  verifyPartSource;\n  final Duration recoveryDelay;\n',
    '''  verifyPartSource;\n  /// Whether this launched child must avoid transport pause and finish its\n  /// current immutable Range into a durable file instead. Used on iOS where\n  /// URLSession cancelByProducingResumeData can cancel a task and still return\n  /// no resume data. The policy is consulted only when pause() explicitly asks\n  /// to preserve live parts.\n  final bool Function(DownloadTask task)? shouldDrainPartOnPause;\n  final void Function(String parentTaskId)? onPausedDrainSettled;\n  final Duration recoveryDelay;\n''',
)

# A completed drain child can release the logical episode slot once the final
# native owner is gone. This callback never starts multipart work itself.
replace_once(
    parallel,
    '''  Future<void> _afterAdoptedPart(_ParallelSession session) async {\n    await _persist(session);\n    if (session.parts.every((child) => child.complete)) {\n      await _assemble(session);\n    } else {\n      _scheduleAggregateProgress(session);\n      _schedulePumpAll();\n    }\n  }\n''',
    '''  void _notifyPausedDrainSettled(_ParallelSession session) {\n    if (session.active || _activeConnectionsForSession(session) > 0) return;\n    diagnosticLog?.record('parallel.pauseDrainSettled', {\n      'taskId': session.task.taskId,\n    });\n    onPausedDrainSettled?.call(session.task.taskId);\n  }\n\n  Future<void> _afterAdoptedPart(_ParallelSession session) async {\n    await _persist(session);\n    if (session.parts.every((child) => child.complete)) {\n      await _assemble(session);\n    } else {\n      _scheduleAggregateProgress(session);\n      _schedulePumpAll();\n      _notifyPausedDrainSettled(session);\n    }\n  }\n''',
)

replace_once(
    parallel,
    '''  Future<bool> pause(ParallelDownloadTask task) async {\n    if (_disposed) return false;\n    if (!await restore(task)) return false;\n    final session = _sessions[task.taskId]!;\n    return session.serialize(() => _pause(session));\n  }\n''',
    '''  Future<bool> pause(\n    ParallelDownloadTask task, {\n    bool preserveLiveParts = false,\n  }) async {\n    if (_disposed) return false;\n    if (!await restore(task)) return false;\n    final session = _sessions[task.taskId]!;\n    return session.serialize(\n      () => _pause(session, preserveLiveParts: preserveLiveParts),\n    );\n  }\n''',
)

# When a draining native child fails while the logical parent is already
# paused, release its scheduler reservation but do not recover/re-enqueue it.
# The next explicit resume will inspect native resumeData / exact disk bytes and
# safely restart only that Range if neither survived.
needle = '''          if (session.active &&\n              (update.status == TaskStatus.failed ||\n                  update.status == TaskStatus.notFound ||\n                  update.status == TaskStatus.canceled ||\n                  update.status == TaskStatus.paused)) {\n'''
replacement = '''          if (!session.active &&\n              (update.status == TaskStatus.failed ||\n                  update.status == TaskStatus.notFound ||\n                  update.status == TaskStatus.canceled ||\n                  update.status == TaskStatus.paused)) {\n            _markConnectionReady(session, part);\n            _releaseConnection(part);\n            _invalidatePartAttempt(session, part);\n            await _persist(session);\n            _notifyPausedDrainSettled(session);\n            return;\n          }\n\n''' + needle
replace_once(parallel, needle, replacement)

# Direct TaskStatus.complete (as opposed to the custom native byte bridge) also
# needs to release a paused-drain slot.
replace_once(
    parallel,
    '''            onPartProgress(session.task.taskId, part.task.taskId, 1);\n            await _persist(session);\n            if (session.active &&\n                session.parts.every((child) => child.complete)) {\n''',
    '''            onPartProgress(session.task.taskId, part.task.taskId, 1);\n            await _persist(session);\n            _notifyPausedDrainSettled(session);\n            if (session.active &&\n                session.parts.every((child) => child.complete)) {\n''',
)

# Replace the old "pause every unfinished child" implementation. Only launched
# children are transport-owned. In preserve mode, selected iOS native children
# are intentionally left alone to drain; unlaunched work is never paused.
replace_regex(
    parallel,
    r'''  Future<bool> _pause\(_ParallelSession session\) async \{.*?\n  \}\n\n  Future<void> cancel\(ParallelDownloadTask task\) async \{''',
    r'''  Future<bool> _pause(\n    _ParallelSession session, {\n    bool preserveLiveParts = false,\n  }) async {\n    session.active = false;\n    session.generation++;\n    _speedTelemetry.resetSpeed(session.task.taskId);\n    session.cancelAggregateProgress();\n    session.cancelProgressPersist();\n    session.cancelDiskProgressPoll();\n    session.cancelCoordinatorRecovery();\n    session.resetRamp();\n\n    final unfinished = session.parts\n        .where((part) => !part.complete)\n        .toList(growable: false);\n    final drainIds = <String>{};\n    final pauseCandidates = <_DownloadPart>[];\n    for (final part in unfinished) {\n      if (!part.launched) continue;\n      final drain =\n          preserveLiveParts &&\n          (shouldDrainPartOnPause?.call(part.task) ?? false);\n      if (drain) {\n        drainIds.add(part.task.taskId);\n      } else {\n        pauseCandidates.add(part);\n      }\n    }\n\n    if (drainIds.isNotEmpty) {\n      diagnosticLog?.record('parallel.pauseDrain', {\n        'taskId': session.task.taskId,\n        'count': drainIds.length,\n      });\n    }\n\n    var pauseFailed = false;\n    await Future.wait(\n      pauseCandidates.map((part) async {\n        try {\n          await pausePart(part.task);\n        } catch (_) {\n          pauseFailed = true;\n        }\n      }),\n    );\n\n    Set<String> live = <String>{};\n    var liveLookupSucceeded = livePartIds == null;\n    final lookupLive = livePartIds;\n    if (lookupLive != null) {\n      try {\n        live = await lookupLive();\n        liveLookupSucceeded = true;\n      } catch (_) {\n        pauseFailed = true;\n      }\n    }\n\n    // Retry only transport-pause candidates that are still demonstrably live.\n    // Never retry the drain set: on iOS the retry itself is the destructive\n    // cancelByProducingResumeData operation we are avoiding.\n    var stillUnexpected = pauseCandidates\n        .where((part) => live.contains(part.task.taskId))\n        .toList(growable: false);\n    if (stillUnexpected.isNotEmpty) {\n      await Future.wait(\n        stillUnexpected.map((part) async {\n          try {\n            await pausePart(part.task);\n          } catch (_) {\n            pauseFailed = true;\n          }\n        }),\n      );\n      await Future<void>.delayed(const Duration(milliseconds: 150));\n      if (lookupLive != null) {\n        try {\n          live = await lookupLive();\n          liveLookupSucceeded = true;\n        } catch (_) {\n          pauseFailed = true;\n          liveLookupSucceeded = false;\n        }\n      }\n      stillUnexpected = pauseCandidates\n          .where((part) => live.contains(part.task.taskId))\n          .toList(growable: false);\n    }\n\n    if (stillUnexpected.isNotEmpty ||\n        (lookupLive == null && pauseFailed && drainIds.isEmpty)) {\n      final stillIds = stillUnexpected\n          .map((part) => part.task.taskId)\n          .toSet()\n        ..addAll(drainIds);\n      session.active = true;\n      for (final part in unfinished) {\n        final owns = stillIds.contains(part.task.taskId);\n        part.launched = owns;\n        part.speed = 0;\n        if (owns) {\n          _activeConnectionIds.add(part.task.taskId);\n        } else {\n          _invalidatePartAttempt(session, part);\n          _activeConnectionIds.remove(part.task.taskId);\n        }\n      }\n      _scheduleDiskProgressPoll(session);\n      await _persist(session);\n      await _status(session, TaskStatus.running);\n      return false;\n    }\n\n    var retainedDrainCount = 0;\n    for (final part in unfinished) {\n      final requestedDrain = drainIds.contains(part.task.taskId);\n      // If native liveness could not be queried, retaining a launched drain is\n      // safer than invoking a destructive pause or freeing its slot early. A\n      // later native completion/failure or explicit resume reconciles it.\n      final ownsDrain =\n          requestedDrain &&\n          (!liveLookupSucceeded || lookupLive == null || live.contains(part.task.taskId));\n      if (ownsDrain) {\n        retainedDrainCount++;\n        part.launched = true;\n        part.speed = 0;\n        _activeConnectionIds.add(part.task.taskId);\n        continue;\n      }\n\n      // A drain candidate that disappeared between enqueue and the liveness\n      // snapshot may already have moved its complete file. Adopt exact bytes\n      // before fencing the old attempt.\n      if (requestedDrain &&\n          await _adoptExactSizePart(\n            session,\n            part,\n            settleNativeOwner: false,\n          )) {\n        continue;\n      }\n\n      _invalidatePartAttempt(session, part);\n      part.launched = false;\n      part.speed = 0;\n      _activeConnectionIds.remove(part.task.taskId);\n    }\n\n    await _persist(session);\n    await _status(session, TaskStatus.paused);\n    diagnosticLog?.record('parallel.pauseCommitted', {\n      'taskId': session.task.taskId,\n      'draining': retainedDrainCount,\n    });\n    _schedulePumpAll();\n    if (retainedDrainCount == 0) _notifyPausedDrainSettled(session);\n    return true;\n  }\n\n  Future<void> cancel(ParallelDownloadTask task) async {''',
)

# Wire preservation only for a user pause on iOS. Source-refresh settlement and
# integrity parking continue using the ordinary transport pause semantics.
replace_once(
    service,
    '''      verifyPartSource: (task, file, bytes) =>\n          _rangeTransfers.verifyExistingPrefix(\n            id: task.taskId,\n            url: task.url,\n            headers: task.headers,\n            file: file,\n            written: bytes,\n          ),\n      onUpdate: (update) {\n''',
    '''      verifyPartSource: (task, file, bytes) =>\n          _rangeTransfers.verifyExistingPrefix(\n            id: task.taskId,\n            url: task.url,\n            headers: task.headers,\n            file: file,\n            written: bytes,\n          ),\n      shouldDrainPartOnPause: (task) =>\n          Platform.isIOS &&\n          isInternalDownloaderChunk(task) &&\n          !_rangeTransfers.isActive(task.taskId),\n      onPausedDrainSettled: (parentTaskId) {\n        diagnosticLog.record('parallel.pauseDrainQueueRelease', {\n          'taskId': parentTaskId,\n        });\n        unawaited(_serializeQueue(_syncQueueToCapUnlocked));\n        unawaited(_syncSessionOverlay(completedSuccess: false));\n      },\n      onUpdate: (update) {\n''',
)

replace_once(
    service,
    '''    if (task is ParallelDownloadTask && await _parallel.restore(task)) {\n      return _parallel.pause(task);\n    }\n''',
    '''    if (task is ParallelDownloadTask && await _parallel.restore(task)) {\n      return _parallel.pause(\n        task,\n        preserveLiveParts: Platform.isIOS && _userPausedIds.contains(task.taskId),\n      );\n    }\n''',
)

# A system/continued-processing pause should use the same non-destructive iOS
# boundary. It is semantically a park, not a source-refresh/integrity pause.
replace_once(
    service,
    '''    final didPause = downloadTask is ParallelDownloadTask\n        ? await _parallel.pause(downloadTask)\n        : await _nativeTransport.pause(downloadTask);\n''',
    '''    final didPause = downloadTask is ParallelDownloadTask\n        ? await _parallel.pause(\n            downloadTask,\n            preserveLiveParts: Platform.isIOS,\n          )\n        : await _nativeTransport.pause(downloadTask);\n''',
)

# Paused parent rows with native children still draining continue to reserve one
# logical queue slot. This prevents user pause at N=1 from momentarily running a
# second episode while the old Range children are finishing their durable edge.
replace_once(
    service,
    '''      final taskId = record.task.taskId;\n      if (_userPausedIds.contains(taskId)) continue;\n      if (reservesDownloadSlot(\n''',
    '''      final taskId = record.task.taskId;\n      if (_userPausedIds.contains(taskId)) {\n        if (_parallel.hasLiveConnections(taskId)) occupying.add(taskId);\n        continue;\n      }\n      if (reservesDownloadSlot(\n''',
)
replace_once(
    service,
    '''    occupying.addAll(_startingTaskIds);\n    occupying.removeAll(_userPausedIds);\n    occupying.removeAll(_restackingWaiterIds);\n''',
    '''    occupying.addAll(_startingTaskIds);\n    occupying.removeAll(_restackingWaiterIds);\n''',
)

# Do not discard native completion/byte evidence while the user-visible parent
# is paused. PersistentParallelDownload is inactive so it will not emit parent
# running progress or launch replacement ranges; it only tracks/drains the
# already-owned child and adopts an exact completed .part.
replace_once(
    service,
    '''    if (_terminalJobIds.contains(parentTaskId) ||\n        _userPausedIds.contains(parentTaskId)) {\n      return;\n    }\n''',
    '''    if (_terminalJobIds.contains(parentTaskId)) return;\n    final parentUserPaused = _userPausedIds.contains(parentTaskId);\n''',
)
replace_once(
    service,
    '''    _publishChunkProgress(\n      parentTaskId: parentTaskId,\n      chunkTaskId: chunkTaskId,\n      progress: derivedProgress,\n      statusOrdinal: completed ? TaskStatus.complete.index : statusOrdinal,\n    );\n\n    unawaited(\n''',
    '''    if (!parentUserPaused || completed) {\n      _publishChunkProgress(\n        parentTaskId: parentTaskId,\n        chunkTaskId: chunkTaskId,\n        progress: derivedProgress,\n        statusOrdinal: completed ? TaskStatus.complete.index : statusOrdinal,\n      );\n    }\n\n    unawaited(\n''',
)

# Test helper supports the iOS preservation policy and drain-settled callback.
replace_once(
    test,
    '''  PersistentParallelDownload create({\n    int maxActiveConnections = 16,\n    Duration diskProgressPollInterval = const Duration(seconds: 1),\n  }) => PersistentParallelDownload(\n''',
    '''  PersistentParallelDownload create({\n    int maxActiveConnections = 16,\n    Duration diskProgressPollInterval = const Duration(seconds: 1),\n    bool preserveNativeParts = false,\n    void Function(String parentTaskId)? onPausedDrainSettled,\n  }) => PersistentParallelDownload(\n''',
)
replace_once(
    test,
    '''    livePartIds: () async => liveIds,\n    recoveryDelay: const Duration(milliseconds: 10),\n''',
    '''    livePartIds: () async => liveIds,\n    shouldDrainPartOnPause: preserveNativeParts ? (_) => true : null,\n    onPausedDrainSettled: onPausedDrainSettled,\n    recoveryDelay: const Duration(milliseconds: 10),\n''',
)

anchor = "  test('user pause cancels a pending automatic part recovery', () async {\n"
addition = r'''  test(
    'iOS user pause drains launched native range without destructive pause',
    () async {
      final settled = <String>[];
      await coordinator.dispose();
      coordinator = create(
        preserveNativeParts: true,
        onPausedDrainSettled: settled.add,
      );

      expect(await coordinator.start(parent, 25), isTrue);
      expect(starts.length, 1);
      final first = starts.single;
      liveIds = <String>{first.taskId};
      await markRunning(<DownloadTask>[first]);

      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      expect(pauses, isEmpty);
      expect(coordinator.isActive(parent.taskId), isFalse);
      expect(coordinator.activeConnectionCount, 1);
      expect(statuses.last, TaskStatus.paused);
      expect(starts.length, 1, reason: 'paused parent must not launch tail work');

      await completePart(first, <int>[0, 1, 2, 3, 4]);
      await waitUntil(() => coordinator.activeConnectionCount == 0);
      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(starts.length, 1);
    },
  );

  test(
    'resume during iOS pause drain reuses the same native child identity',
    () async {
      await coordinator.dispose();
      coordinator = create(preserveNativeParts: true);

      expect(await coordinator.start(parent, 25), isTrue);
      final first = starts.single;
      liveIds = <String>{first.taskId};
      await markRunning(<DownloadTask>[first]);
      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      expect(coordinator.activeConnectionCount, 1);

      expect(await coordinator.start(parent, 25), isTrue);
      expect(
        starts.where((task) => task.taskId == first.taskId).length,
        1,
        reason: 'the still-owned URLSession range must not be enqueued twice',
      );
      expect(coordinator.isActive(parent.taskId), isTrue);
    },
  );

  test(
    'failed child while parent is pause-draining releases slot without retry',
    () async {
      final settled = <String>[];
      await coordinator.dispose();
      coordinator = create(
        preserveNativeParts: true,
        onPausedDrainSettled: settled.add,
      );

      expect(await coordinator.start(parent, 25), isTrue);
      final first = starts.single;
      liveIds = <String>{first.taskId};
      await markRunning(<DownloadTask>[first]);
      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      final startsAtPause = starts.length;

      coordinator.handleUpdate(TaskStatusUpdate(first, TaskStatus.failed));
      await waitUntil(() => coordinator.activeConnectionCount == 0);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(starts.length, startsAtPause);
      expect(coordinator.isActive(parent.taskId), isFalse);
      expect(settled, contains(parent.taskId));
      expect(statuses.last, TaskStatus.paused);
    },
  );

'''
text = read(test)
if text.count(anchor) != 1:
    raise SystemExit('test insertion anchor missing')
write(test, text.replace(anchor, addition + anchor, 1))

# The old recreation test deliberately exercised pausing every restored identity
# even when there was no native ownership evidence. The new invariant is the
# opposite: unlaunched/unowned ranges must not invoke a transport pause.
replace_once(
    test,
    '''  test(\n    'pause after recreation stops native children with no launched flags',\n    () async {\n      await coordinator.start(parent, 25);\n      await expandFreshTo(5);\n      await coordinator.dispose();\n      coordinator = create();\n      await coordinator.pause(parent);\n      expect(pauses.toSet(), starts.map((task) => task.taskId).toSet());\n      expect(coordinator.activeConnectionCount, 0);\n    },\n  );\n'''.replace('\\n', '\n'),
    '''  test(\n    'pause after recreation does not pause children with no native owner',\n    () async {\n      await coordinator.start(parent, 25);\n      await expandFreshTo(5);\n      await coordinator.dispose();\n      pauses.clear();\n      liveIds = <String>{};\n      coordinator = create();\n      await coordinator.pause(parent);\n      expect(pauses, isEmpty);\n      expect(coordinator.activeConnectionCount, 0);\n    },\n  );\n'''.replace('\\n', '\n'),
)

# Lock the DownloadService integration against regression: iOS user pause opts
# into drain mode; paused native completions are still forwarded; draining
# parents reserve a logical queue slot until the last child settles.
insert_anchor = "    test(\n      'lost multipart resume checkpoint is repaired instead of retried forever',\n"
runtime_addition = r'''    test('iOS multipart pause preserves live URLSession range bytes', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      expect(source, contains('preserveLiveParts: Platform.isIOS'));
      expect(source, contains('shouldDrainPartOnPause: (task) =>'));
      expect(source, contains("diagnosticLog.record('parallel.pauseDrainQueueRelease'"));
      expect(
        source,
        contains('if (_parallel.hasLiveConnections(taskId)) occupying.add(taskId);'),
      );
      expect(source, contains('final parentUserPaused = _userPausedIds.contains(parentTaskId);'));
      expect(source, contains('if (!parentUserPaused || completed)'));
    });

'''
runtime = read(runtime_test)
if runtime.count(insert_anchor) != 1:
    raise SystemExit('runtime test insertion anchor missing')
write(runtime_test, runtime.replace(insert_anchor, runtime_addition + insert_anchor, 1))

print('Applied non-destructive iOS multipart pause-drain fix and regressions.')
