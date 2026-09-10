from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, found {count}')
    file.write_text(text.replace(old, new, 1))


# 1) Give internal multipart children a stable way to resolve their logical
# parent without treating child metadata as a tracking URL.
replace_once(
    'lib/core/services/download_parallel.dart',
    "import 'package:background_downloader/background_downloader.dart';\n",
    "import 'dart:convert';\n\nimport 'package:background_downloader/background_downloader.dart';\n",
)
replace_once(
    'lib/core/services/download_parallel.dart',
    "bool isInternalDownloaderChunk(Task task) =>\n    task.group == FileDownloader.chunkGroup ||\n    task.group == kPersistentDownloadChunkGroup;\n\nbool isLogicalEpisodeDownloadTask(Task task) =>\n",
    "bool isInternalDownloaderChunk(Task task) =>\n    task.group == FileDownloader.chunkGroup ||\n    task.group == kPersistentDownloadChunkGroup;\n\n/// Persistent multipart children store only their logical parent identity in\n/// JSON metadata. Keep this parsing centralized so retry/source-refresh code\n/// never mistakes a child for an independent logical download.\nString? downloadInternalParentTaskId(Task task) {\n  if (!isInternalDownloaderChunk(task)) return null;\n  final raw = task.metaData.trim();\n  if (raw.isEmpty) return null;\n  try {\n    final decoded = jsonDecode(raw);\n    if (decoded is! Map) return null;\n    final value = decoded['parentTaskId'];\n    final parent = value is String ? value.trim() : '';\n    return parent.isEmpty ? null : parent;\n  } catch (_) {\n    return null;\n  }\n}\n\nbool isLogicalEpisodeDownloadTask(Task task) =>\n",
)

# 2) PersistentParallelDownload owns child scheduling only while a failed start
# is locally recoverable. Terminal RangeTransfer outcomes are parked rather than
# being relaunched forever. Native 401/403 can ask the logical owner to refresh.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    "import 'download_parallel.dart';\nimport 'download_telemetry.dart';\n",
    "import 'download_parallel.dart';\nimport 'download_retry_policy.dart';\nimport 'download_telemetry.dart';\n",
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    "    this.livePartIds,\n    this.recoveryDelay = const Duration(seconds: 1),\n",
    "    this.livePartIds,\n    this.shouldRecoverFailedStart,\n    this.onSourceRefreshNeeded,\n    this.recoveryDelay = const Duration(seconds: 1),\n",
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    "  final Future<Set<String>> Function()? livePartIds;\n  final Duration recoveryDelay;\n",
    "  final Future<Set<String>> Function()? livePartIds;\n  final bool Function(String childTaskId)? shouldRecoverFailedStart;\n  final void Function(String parentTaskId)? onSourceRefreshNeeded;\n  final Duration recoveryDelay;\n",
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    "        if (!started) {\n          // A false enqueue result has identical ownership semantics: no native\n          // worker exists, so restore the scheduler reservation and retry the\n          // exact same taskId/Range without teaching a lower host ceiling.\n          rollbackUnownedReservation();\n          _schedulePartRecovery(session, part);\n          await _status(session, TaskStatus.running);\n          return true;\n        }\n",
    "        if (!started) {\n          // A false enqueue result has no native owner. Retry it only when the\n          // transport did not already classify the attempt as terminal. Range\n          // refresh/reconcile/disk failures belong to the logical parent; an\n          // unconditional child retry here used to relaunch the same expired\n          // signed URL forever.\n          rollbackUnownedReservation();\n          final shouldRecover =\n              shouldRecoverFailedStart?.call(part.task.taskId) ?? true;\n          if (!shouldRecover) {\n            diagnosticLog?.record('parallel.childStartParked', {\n              'taskId': part.task.taskId,\n              'parentTaskId': session.task.taskId,\n            });\n            await _pause(session);\n            return true;\n          }\n          _schedulePartRecovery(session, part);\n          await _status(session, TaskStatus.running);\n          return true;\n        }\n",
)
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    "            // Permanent client-side HTTP errors (for example 401/403/404) are\n            // not helped by hammering the same signed URL forever. Preserve all\n            // bytes and park the logical episode so a later source refresh/user\n            // resume can obtain a new URL.\n            _markConnectionReady(session, part);\n",
    "            // Permanent client-side HTTP errors are not helped by hammering\n            // the same signed URL forever. 401/403 specifically mean the logical\n            // owner may be able to mint a fresh signed source; schedule that\n            // outside this session serialization, then park all current workers.\n            final exception = update.exception;\n            final statusCode =\n                update.responseStatusCode ??\n                (exception is TaskHttpException\n                    ? exception.httpResponseCode\n                    : null);\n            if (isDownloadUrlRefreshStatus(statusCode, include404: false)) {\n              onSourceRefreshNeeded?.call(session.task.taskId);\n            }\n            _markConnectionReady(session, part);\n",
)

# 3) DownloadService becomes the sole owner of logical source refresh. It
# coalesces simultaneous child failures, refreshes the parent once, and resumes
# only after a genuinely new source was accepted.
replace_once(
    'lib/core/services/download_service.dart',
    "  final Set<String> _startingTaskIds = {};\n  final List<String> _sessionOrder = [];\n",
    "  final Set<String> _startingTaskIds = {};\n  final Set<String> _refreshingParallelParentIds = <String>{};\n  final List<String> _sessionOrder = [];\n",
)
replace_once(
    'lib/core/services/download_service.dart',
    "      recordForId: (id) => FileDownloader().database.recordForId(id),\n      livePartIds: _livePartIds,\n      onUpdate: (update) {\n",
    "      recordForId: (id) => FileDownloader().database.recordForId(id),\n      livePartIds: _livePartIds,\n      shouldRecoverFailedStart: (childTaskId) =>\n          _rangeTransfers.failureFor(childTaskId) == null,\n      onSourceRefreshNeeded: _scheduleParallelParentRefresh,\n      onUpdate: (update) {\n",
)
replace_once(
    'lib/core/services/download_service.dart',
    "  Future<bool> _appendRemainingWithDio(\n    DownloadTask task, {\n",
    "  Future<ParallelDownloadTask?> _parallelParentForInternalPart(\n    DownloadTask task,\n  ) async {\n    final parentTaskId = downloadInternalParentTaskId(task);\n    if (parentTaskId == null) return null;\n    final record = await FileDownloader().database.recordForId(parentTaskId);\n    final parent = record?.task;\n    return parent is ParallelDownloadTask ? parent : null;\n  }\n\n  void _scheduleParallelParentRefresh(String parentTaskId) {\n    if (parentTaskId.isEmpty || !_refreshingParallelParentIds.add(parentTaskId)) {\n      return;\n    }\n    Future<void>.delayed(Duration.zero, () async {\n      try {\n        if (_disposed || _userPausedIds.contains(parentTaskId)) return;\n        await _serializeQueue(() async {\n          if (_disposed || _userPausedIds.contains(parentTaskId)) return;\n          var record = await FileDownloader().database.recordForId(parentTaskId);\n          if (record?.task is! ParallelDownloadTask) return;\n          var parent = record!.task as ParallelDownloadTask;\n          final trackingUrl = downloadTrackingUrl(parent);\n          if (_cancellingUrls.contains(trackingUrl)) return;\n\n          final descriptor = await _ref\n              .read(downloadUrlRefreshStoreProvider)\n              .get(trackingUrl);\n          if (descriptor == null) {\n            diagnosticLog.record('source.refreshUnavailable', {\n              'taskId': parentTaskId,\n            });\n            return;\n          }\n\n          // A child failure callback can arrive while healthy siblings are still\n          // owned by URLSession. Settle them first so replaceSource can update one\n          // coherent generation without racing stale native callbacks.\n          if (_parallel.isActive(parentTaskId)) {\n            if (!await _parallel.pause(parent)) return;\n          }\n\n          record = await FileDownloader().database.recordForId(parentTaskId);\n          if (record?.task is! ParallelDownloadTask) return;\n          parent = record!.task as ParallelDownloadTask;\n          final saved = await _savedProgressFor(parent);\n          final refreshed = await _refreshTaskBeforeResume(\n            parent,\n            expectedBytes: saved.totalSize,\n            partialBytes: saved.partialBytes,\n          );\n          if (!refreshed.refreshed || refreshed.task is! ParallelDownloadTask) {\n            diagnosticLog.record('source.refreshParked', {\n              'taskId': parentTaskId,\n            });\n            return;\n          }\n\n          await _resumeDownloadTask(refreshed.task);\n        });\n      } finally {\n        _refreshingParallelParentIds.remove(parentTaskId);\n      }\n    });\n  }\n\n  Future<bool> _appendRemainingWithDio(\n    DownloadTask task, {\n",
)
replace_once(
    'lib/core/services/download_service.dart',
    "    final logical = isLogicalEpisodeDownloadTask(task);\n    DownloadAttemptToken? token;\n    var canRefreshUrl = false;\n    if (logical) {\n      token = await _beginLogicalRangeAttempt(\n        task,\n        existingBytes: existingBytes,\n        expectedBytes: expectedBytes,\n      );\n      canRefreshUrl =\n          await _ref\n              .read(downloadUrlRefreshStoreProvider)\n              .get(downloadTrackingUrl(task)) !=\n          null;\n    }\n\n    return _rangeTransfers.start(\n",
    "    final logical = isLogicalEpisodeDownloadTask(task);\n    final parallelParent = logical\n        ? null\n        : await _parallelParentForInternalPart(task);\n    DownloadAttemptToken? token;\n    var canRefreshUrl = false;\n    if (logical) {\n      token = await _beginLogicalRangeAttempt(\n        task,\n        existingBytes: existingBytes,\n        expectedBytes: expectedBytes,\n      );\n      canRefreshUrl =\n          await _ref\n              .read(downloadUrlRefreshStoreProvider)\n              .get(downloadTrackingUrl(task)) !=\n          null;\n    } else if (parallelParent != null) {\n      canRefreshUrl =\n          await _ref\n              .read(downloadUrlRefreshStoreProvider)\n              .get(downloadTrackingUrl(parallelParent)) !=\n          null;\n    }\n\n    return _rangeTransfers.start(\n",
)
replace_once(
    'lib/core/services/download_service.dart',
    "      onFailure: (failure) async {\n        if (!logical || token == null) return;\n        final activeToken = token;\n",
    "      onFailure: (failure) async {\n        if (!logical || token == null) {\n          if (parallelParent != null &&\n              failure.action == DownloadFailureAction.refreshUrl) {\n            _scheduleParallelParentRefresh(parallelParent.taskId);\n          }\n          return;\n        }\n        final activeToken = token;\n",
)

# 4) Regression coverage for metadata ownership and terminal child-start loops.
replace_once(
    'test/core/services/download_parallel_test.dart',
    "    test('internal chunks are never logical episode tasks', () {\n",
    "    test('persistent child metadata resolves only its logical parent', () {\n      final child = DownloadTask(\n        taskId: 'episode.part.0',\n        url: 'https://cdn.test/video',\n        group: kPersistentDownloadChunkGroup,\n        metaData: '{\"parentTaskId\":\"episode\"}',\n      );\n      final malformed = child.copyWith(metaData: 'not-json');\n      final logical = DownloadTask(\n        taskId: 'episode',\n        url: 'https://cdn.test/video',\n        group: kLogicalDownloadGroup,\n        metaData: '{\"parentTaskId\":\"wrong\"}',\n      );\n\n      expect(downloadInternalParentTaskId(child), 'episode');\n      expect(downloadInternalParentTaskId(malformed), isNull);\n      expect(downloadInternalParentTaskId(logical), isNull);\n    });\n\n    test('internal chunks are never logical episode tasks', () {\n",
)
replace_once(
    'test/core/services/persistent_parallel_download_auto_recovery_test.dart',
    "    bool pauseClearsLive = true,\n    bool deleteCanceledFiles = false,\n  }) {\n    return PersistentParallelDownload(\n      startPart: (task, progress, size) async {\n        starts.add(task);\n        startProgresses.add(progress);\n        return true;\n      },\n",
    "    bool pauseClearsLive = true,\n    bool deleteCanceledFiles = false,\n    Future<bool> Function(DownloadTask task, double progress, int size)?\n    startPartOverride,\n    bool Function(String childTaskId)? shouldRecoverFailedStart,\n  }) {\n    return PersistentParallelDownload(\n      startPart: (task, progress, size) async {\n        starts.add(task);\n        startProgresses.add(progress);\n        if (startPartOverride != null) {\n          return startPartOverride(task, progress, size);\n        }\n        return true;\n      },\n",
)
replace_once(
    'test/core/services/persistent_parallel_download_auto_recovery_test.dart',
    "      livePartIds: () async => Set<String>.from(livePartIds),\n      recoveryDelay: recoveryDelay,\n",
    "      livePartIds: () async => Set<String>.from(livePartIds),\n      shouldRecoverFailedStart: shouldRecoverFailedStart,\n      recoveryDelay: recoveryDelay,\n",
)
replace_once(
    'test/core/services/persistent_parallel_download_auto_recovery_test.dart',
    "  test('multipart child uses only AnimeWitcher recovery, not native retries', () async {\n    expect(await coordinator.start(parent, 32), isTrue);\n    expect(starts, hasLength(1));\n    expect(starts.single.retries, 0);\n  });\n\n",
    "  test('multipart child uses only AnimeWitcher recovery, not native retries', () async {\n    expect(await coordinator.start(parent, 32), isTrue);\n    expect(starts, hasLength(1));\n    expect(starts.single.retries, 0);\n  });\n\n  test('terminal failed start parks parent instead of relaunching forever', () async {\n    await coordinator.dispose();\n    clearHarness();\n    var attempts = 0;\n    coordinator = buildCoordinator(\n      recoveryDelay: const Duration(milliseconds: 5),\n      shouldRecoverFailedStart: (_) => false,\n      startPartOverride: (_, _, _) async {\n        attempts++;\n        return false;\n      },\n    );\n\n    expect(await coordinator.start(parent, 32), isTrue);\n    await waitUntil(() => parentStatuses.contains(TaskStatus.paused));\n    await Future<void>.delayed(const Duration(milliseconds: 40));\n\n    expect(attempts, 1);\n    expect(starts, hasLength(1));\n    expect(coordinator.isActive(parent.taskId), isFalse);\n    expect(parentStatuses.last, TaskStatus.paused);\n  });\n\n",
)

print('Phase 3 patch applied')
