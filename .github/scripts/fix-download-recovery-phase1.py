from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}\n--- needle ---\n{old}")
    p.write_text(text.replace(old, new, 1))


parallel = "lib/core/services/persistent_parallel_download.dart"
service = "lib/core/services/download_service.dart"
progress_test = "test/core/services/persistent_parallel_download_progress_test.dart"
runtime_test = "test/core/services/download_runtime_stability_review_test.dart"

# Phase 1: make multipart recovery snapshots self-describing and monotonic across
# process relaunches. Legacy manifests remain readable as schema v1.
replace_once(
    parallel,
    "const Duration kParallelProgressPersistInterval = Duration(seconds: 1);\n",
    "const Duration kParallelProgressPersistInterval = Duration(seconds: 1);\n\n"
    "/// Durable multipart manifest schema. Version 1 was the legacy payload that\n"
    "/// contained only `parts`. Version 2 also records the logical generation and\n"
    "/// expected byte count so a process relaunch cannot silently combine a torn\n"
    "/// checkpoint with incompatible recovery metadata.\n"
    "const int kParallelManifestSchemaVersion = 2;\n",
)

replace_once(
    parallel,
    "  double? progressFor(String id) => _sessions[id]?.progress;\n\n",
    "  double? progressFor(String id) => _sessions[id]?.progress;\n\n"
    "  /// Repair a child whose native resume checkpoint claimed progress but no\n"
    "  /// resumable/native/on-disk bytes survived. The immutable Range itself is\n"
    "  /// retained; only the unprovable prefix is discarded so recovery can fetch\n"
    "  /// that one Range again instead of retrying a phantom checkpoint forever.\n"
    "  ///\n"
    "  /// This is intentionally synchronous because it is called by [startPart]\n"
    "  /// while the owning session is already serialized in [_pumpSession].\n"
    "  bool resetUndurablePartProgress(String childTaskId, {int durableBytes = 0}) {\n"
    "    if (_disposed) return false;\n"
    "    final session = _children[childTaskId];\n"
    "    if (session == null || session.deleted) return false;\n"
    "    _DownloadPart? part;\n"
    "    for (final candidate in session.parts) {\n"
    "      if (candidate.task.taskId == childTaskId) {\n"
    "        part = candidate;\n"
    "        break;\n"
    "      }\n"
    "    }\n"
    "    if (part == null || part.complete) return false;\n"
    "    if (durableBytes < 0 || durableBytes > part.size) return false;\n"
    "\n"
    "    final repaired = part.size > 0\n"
    "        ? (durableBytes / part.size).clamp(0.0, 1.0).toDouble()\n"
    "        : 0.0;\n"
    "    _cancelTailStallWatch(part);\n"
    "    part.progress = repaired;\n"
    "    part.credibleProgress = repaired;\n"
    "    part.speed = 0;\n"
    "    part.recoveryAttempts = 0;\n"
    "    part.tailRecoveryAttempted = false;\n"
    "    part.tailWatchProgress = -1;\n"
    "    part.lastNativeBridgeBytes = durableBytes;\n"
    "    part.lastNativeBridgeAt = null;\n"
    "    onPartProgress(session.task.taskId, childTaskId, repaired);\n"
    "    if (session.active) _scheduleAggregateProgress(session);\n"
    "    return true;\n"
    "  }\n\n",
)

replace_once(
    parallel,
    "        final json = jsonDecode(raw) as Map<String, dynamic>;\n"
    "        final partJson = json['parts'];\n"
    "        if (partJson is! List || partJson.isEmpty) continue;\n"
    "        final parts = partJson\n"
    "            .map(\n"
    "              (part) => _DownloadPart.fromJson(\n"
    "                Map<String, dynamic>.from(part as Map),\n"
    "              ),\n"
    "            )\n"
    "            .toList(growable: false);\n"
    "        if (parts.length > kDownloadWorkUnitsMax ||\n"
    "            parts.any((part) => part.from < 0 || part.to < part.from)) {\n"
    "          continue;\n"
    "        }\n"
    "        final session = _ParallelSession(task, manifest, parts);\n",
    "        final json = jsonDecode(raw) as Map<String, dynamic>;\n"
    "        final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;\n"
    "        if (schemaVersion < 1 || schemaVersion > kParallelManifestSchemaVersion) {\n"
    "          continue;\n"
    "        }\n"
    "        final savedGeneration = (json['generation'] as num?)?.toInt() ?? 0;\n"
    "        if (savedGeneration < 0) continue;\n"
    "        final partJson = json['parts'];\n"
    "        if (partJson is! List || partJson.isEmpty) continue;\n"
    "        final parts = partJson\n"
    "            .map(\n"
    "              (part) => _DownloadPart.fromJson(\n"
    "                Map<String, dynamic>.from(part as Map),\n"
    "              ),\n"
    "            )\n"
    "            .toList(growable: false);\n"
    "        if (parts.length > kDownloadWorkUnitsMax ||\n"
    "            parts.any((part) => part.from < 0 || part.to < part.from)) {\n"
    "          continue;\n"
    "        }\n"
    "        var contiguous = parts.first.from == 0;\n"
    "        for (var index = 1; index < parts.length && contiguous; index++) {\n"
    "          contiguous = parts[index].from == parts[index - 1].to + 1;\n"
    "        }\n"
    "        if (!contiguous) continue;\n"
    "        final calculatedBytes = parts.fold<int>(\n"
    "          0,\n"
    "          (sum, part) => sum + part.size,\n"
    "        );\n"
    "        final savedExpectedBytes = (json['expectedBytes'] as num?)?.toInt() ?? -1;\n"
    "        if (savedExpectedBytes > 0 && savedExpectedBytes != calculatedBytes) {\n"
    "          continue;\n"
    "        }\n"
    "        final session = _ParallelSession(\n"
    "          task,\n"
    "          manifest,\n"
    "          parts,\n"
    "          generation: savedGeneration,\n"
    "        );\n",
)

replace_once(
    parallel,
    "    final payload = jsonEncode({\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n"
    "    });\n",
    "    final payload = jsonEncode({\n"
    "      'schemaVersion': kParallelManifestSchemaVersion,\n"
    "      'generation': session.generation,\n"
    "      'expectedBytes': session.size,\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n"
    "    });\n",
)

replace_once(
    parallel,
    "  Future<bool> _adoptCompletedTarget(_ParallelSession session) async {\n"
    "    final target = File(await session.task.filePath());\n"
    "    if (!await target.exists()) return false;\n"
    "    if (await target.length() != session.size) return false;\n"
    "    await _finishCompleteSession(session);\n"
    "    return true;\n"
    "  }\n",
    "  Future<bool> _adoptCompletedTarget(_ParallelSession session) async {\n"
    "    final target = File(await session.task.filePath());\n"
    "    if (await target.exists()) {\n"
    "      if (await target.length() != session.size) return false;\n"
    "      await _finishCompleteSession(session);\n"
    "      return true;\n"
    "    }\n"
    "\n"
    "    // A crash can happen after the complete staging file was flushed and\n"
    "    // closed but before its atomic rename. Reuse it only when every source\n"
    "    // Range is still exact, which proves this staging file belongs to this\n"
    "    // recoverable multipart generation. Otherwise normal assembly rewrites it.\n"
    "    final staging = File('${target.path}.assembling');\n"
    "    if (!await staging.exists() || await staging.length() != session.size) {\n"
    "      return false;\n"
    "    }\n"
    "    for (final part in session.parts) {\n"
    "      final file = File(await part.task.filePath());\n"
    "      if (!await file.exists() || await file.length() != part.size) {\n"
    "        return false;\n"
    "      }\n"
    "    }\n"
    "    await staging.rename(target.path);\n"
    "    await _finishCompleteSession(session);\n"
    "    return true;\n"
    "  }\n",
)

replace_once(
    parallel,
    "class _ParallelSession {\n"
    "  _ParallelSession(this.task, this.manifest, this.parts);\n\n"
    "  ParallelDownloadTask task;\n"
    "  final File manifest;\n"
    "  final List<_DownloadPart> parts;\n"
    "  bool active = false;\n"
    "  bool deleted = false;\n"
    "  int generation = 0;\n",
    "class _ParallelSession {\n"
    "  _ParallelSession(\n"
    "    this.task,\n"
    "    this.manifest,\n"
    "    this.parts, {\n"
    "    this.generation = 0,\n"
    "  });\n\n"
    "  ParallelDownloadTask task;\n"
    "  final File manifest;\n"
    "  final List<_DownloadPart> parts;\n"
    "  bool active = false;\n"
    "  bool deleted = false;\n"
    "  int generation;\n",
)

# The observed failure: iOS pause returned false because URLSession could not
# produce resumeData. No native task and no visible partial bytes survived, but
# the old percentage stayed in the manifest. _startPart therefore returned false
# forever. Repair the stale checkpoint and re-fetch only that immutable Range.
replace_once(
    service,
    "  Future<bool> _startPart(DownloadTask task, double progress, int size) async {\n"
    "    diagnosticLog.record('part.start', {\n"
    "      'taskId': task.taskId,\n"
    "      'progress': progress,\n"
    "      'total': size,\n"
    "    });\n"
    "    if (_rangeTransfers.isActive(task.taskId)) return true;\n"
    "    if ((await _liveTransferTasks()).any((live) => live.taskId == task.taskId))\n"
    "      return true;\n"
    "    try {\n"
    "      final canResume = await FileDownloader()\n"
    "          .taskCanResume(task)\n"
    "          .timeout(const Duration(seconds: 3));\n"
    "      if (canResume && await FileDownloader().resume(task)) return true;\n"
    "    } catch (_) {\n"
    "      // A stale native checkpoint must not prevent the disk-prefix fallback.\n"
    "    }\n"
    "    final partial = await canonicalizePartialDownloadFile(\n"
    "      destinationPath: await task.filePath(),\n"
    "    );\n"
    "    final bytes = partial?.bytes ?? 0;\n"
    "    if (bytes == size && size > 0) {\n"
    "      await FileDownloader().database.updateRecord(\n"
    "        TaskRecord(task, TaskStatus.complete, 1, size),\n"
    "      );\n"
    "      _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));\n"
    "      return true;\n"
    "    }\n"
    "    if (bytes > 0 && bytes < size) {\n"
    "      return _appendRemainingWithDio(\n"
    "        task,\n"
    "        dest: partial!.file,\n"
    "        existingBytes: bytes,\n"
    "        expectedBytes: size,\n"
    "      );\n"
    "    }\n"
    "    if (progress > 0 || bytes > 0) return false;\n"
    "    return FileDownloader().enqueue(task);\n"
    "  }\n",
    "  Future<bool> _startPart(DownloadTask task, double progress, int size) async {\n"
    "    diagnosticLog.record('part.start', {\n"
    "      'taskId': task.taskId,\n"
    "      'progress': progress,\n"
    "      'total': size,\n"
    "    });\n"
    "    if (_rangeTransfers.isActive(task.taskId)) return true;\n"
    "    if ((await _liveTransferTasks()).any((live) => live.taskId == task.taskId))\n"
    "      return true;\n"
    "\n"
    "    var nativeCanResume = false;\n"
    "    try {\n"
    "      nativeCanResume = await FileDownloader()\n"
    "          .taskCanResume(task)\n"
    "          .timeout(const Duration(seconds: 3));\n"
    "      if (nativeCanResume && await FileDownloader().resume(task)) return true;\n"
    "    } catch (_) {\n"
    "      // A stale native checkpoint must not prevent the disk-prefix fallback.\n"
    "    }\n"
    "    final partial = await canonicalizePartialDownloadFile(\n"
    "      destinationPath: await task.filePath(),\n"
    "    );\n"
    "    final bytes = partial?.bytes ?? 0;\n"
    "    if (bytes == size && size > 0) {\n"
    "      await FileDownloader().database.updateRecord(\n"
    "        TaskRecord(task, TaskStatus.complete, 1, size),\n"
    "      );\n"
    "      _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));\n"
    "      return true;\n"
    "    }\n"
    "    if (bytes > 0 && bytes < size) {\n"
    "      return _appendRemainingWithDio(\n"
    "        task,\n"
    "        dest: partial!.file,\n"
    "        existingBytes: bytes,\n"
    "        expectedBytes: size,\n"
    "      );\n"
    "    }\n"
    "\n"
    "    if (progress > 0 && bytes == 0 && !nativeCanResume) {\n"
    "      // iOS pause is implemented by background_downloader using\n"
    "      // cancelByProducingResumeData(). Some Range tasks return nil resume\n"
    "      // data; URLSession then removes its private temp file. The old child\n"
    "      // percentage is no longer durable and retrying it can never succeed.\n"
    "      // Drop only that phantom prefix and re-fetch the same immutable Range.\n"
    "      final repaired = _parallel.resetUndurablePartProgress(\n"
    "        task.taskId,\n"
    "        durableBytes: 0,\n"
    "      );\n"
    "      if (!repaired) return false;\n"
    "      diagnosticLog.record('part.checkpointLost', {\n"
    "        'taskId': task.taskId,\n"
    "        'progress': progress,\n"
    "        'total': size,\n"
    "      });\n"
    "      await FileDownloader().database.updateRecord(\n"
    "        TaskRecord(task, TaskStatus.paused, 0, size),\n"
    "      );\n"
    "      return FileDownloader().enqueue(task);\n"
    "    }\n"
    "\n"
    "    if (bytes > 0) return false;\n"
    "    return FileDownloader().enqueue(task);\n"
    "  }\n",
)

# Add a behavioral regression test for the exact phantom-checkpoint failure.
p = Path(progress_test)
text = p.read_text()
marker = "\n  test('pause cancels a pending aggregate progress emission', () async {"
if marker not in text:
    raise SystemExit(f"{progress_test}: insertion marker missing")
new_test = r'''

  test('lost native checkpoint can reset only its immutable part to disk bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'parallel-progress-lost-checkpoint-',
    );
    final parent = ParallelDownloadTask(
      taskId: 'parallel-lost-checkpoint',
      url: 'https://example.com/video',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 1,
      allowPause: true,
    );
    final records = <String, TaskRecord>{};
    final starts = <DownloadTask>[];
    final coordinator = PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        return true;
      },
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (record) async {
        records[record.task.taskId] = record;
      },
      recordForId: (id) async => records[id],
      onUpdate: (_) {},
      onPartProgress: (_, _, _) {},
    );

    try {
      expect(await coordinator.start(parent, 1000000), isTrue);
      final child = starts.single;
      coordinator.handleUpdate(
        TaskProgressUpdate(
          child,
          0.30,
          1000000,
          0.5,
          const Duration(seconds: 2),
        ),
      );
      await waitUntil(() => (coordinator.progressFor(parent.taskId) ?? 0) >= 0.30);

      expect(
        coordinator.resetUndurablePartProgress(child.taskId, durableBytes: 0),
        isTrue,
      );
      expect(coordinator.progressFor(parent.taskId), 0);
    } finally {
      await coordinator.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
'''
text = text.replace(marker, new_test + marker, 1)
p.write_text(text)

# Source-level guards keep future refactors from reintroducing the exact hang or
# reverting the recovery-snapshot invariants.
p = Path(runtime_test)
text = p.read_text()
needle = "\n    test('continued-processing speed zero explicitly clears stale speed', () {"
if needle not in text:
    raise SystemExit(f"{runtime_test}: insertion marker missing")
new_runtime_tests = r'''

    test('lost multipart resume checkpoint is repaired instead of retried forever', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      final start = source.indexOf('Future<bool> _startPart(');
      final end = source.indexOf('Future<bool> _enqueueTransfer(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final section = source.substring(start, end);
      expect(section, contains("part.checkpointLost"));
      expect(section, contains('resetUndurablePartProgress('));
      expect(section, contains('return FileDownloader().enqueue(task);'));
      expect(section, isNot(contains('if (progress > 0 || bytes > 0) return false;'));
    });

    test('multipart manifests persist generation and expected byte identity', () {
      final source = File('lib/core/services/persistent_parallel_download.dart')
          .readAsStringSync();
      expect(source, contains('kParallelManifestSchemaVersion = 2'));
      expect(source, contains("'schemaVersion': kParallelManifestSchemaVersion"));
      expect(source, contains("'generation': session.generation"));
      expect(source, contains("'expectedBytes': session.size"));
      expect(source, contains('generation: savedGeneration'));
      expect(source, contains('if (!contiguous) continue;'));
    });

    test('complete assembly staging file is adopted after a crash', () {
      final source = File('lib/core/services/persistent_parallel_download.dart')
          .readAsStringSync();
      final start = source.indexOf('Future<bool> _adoptCompletedTarget(');
      final end = source.indexOf('bool _requestedByteRange(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final section = source.substring(start, end);
      expect(section, contains(".assembling"));
      expect(section, contains('await staging.rename(target.path)'));
      expect(section, contains('await file.length() != part.size'));
    });
'''
text = text.replace(needle, new_runtime_tests + needle, 1)
p.write_text(text)

print('Applied download recovery phase 1 and lost-checkpoint fix.')
