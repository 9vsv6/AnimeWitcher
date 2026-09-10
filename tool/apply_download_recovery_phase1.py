from pathlib import Path

path = Path('lib/core/services/persistent_parallel_download.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "const Duration kParallelDiskProgressPollInterval = Duration(seconds: 1);\n",
    "const Duration kParallelDiskProgressPollInterval = Duration(seconds: 1);\n\n"
    "/// Multipart recovery checkpoints are versioned snapshots. The sequence is\n"
    "/// monotonic so a crash after flushing manifest.json.tmp but before rename\n"
    "/// can restore the newer snapshot instead of silently accepting an older\n"
    "/// manifest.json.\n"
    "const int kParallelManifestSchemaVersion = 2;\n",
    'manifest schema constant',
)

replace_once(
    "  Future<File> _manifest(DownloadTask task) async =>\n"
    "      File('${await task.filePath()}.parts/manifest.json');\n\n"
    "  Future<void> dispose() async {",
    "  Future<File> _manifest(DownloadTask task) async =>\n"
    "      File('${await task.filePath()}.parts/manifest.json');\n\n"
    "  Future<List<File>> _orderedManifestCandidates(\n"
    "    File manifest,\n"
    "    File temp,\n"
    "    String taskId,\n"
    "  ) async {\n"
    "    final ranked = <_ManifestRestoreCandidate>[];\n"
    "    for (final file in <File>[manifest, temp]) {\n"
    "      try {\n"
    "        if (!await file.exists()) continue;\n"
    "        final decoded = jsonDecode(await file.readAsString());\n"
    "        if (decoded is! Map) continue;\n"
    "        final snapshot = Map<String, dynamic>.from(decoded);\n"
    "        final parentTaskId = snapshot['parentTaskId']?.toString().trim();\n"
    "        if (parentTaskId != null &&\n"
    "            parentTaskId.isNotEmpty &&\n"
    "            parentTaskId != taskId) {\n"
    "          continue;\n"
    "        }\n"
    "        final sequence =\n"
    "            (snapshot['checkpointSequence'] as num?)?.toInt() ?? 0;\n"
    "        if (sequence < 0) continue;\n"
    "        final stat = await file.stat();\n"
    "        ranked.add(\n"
    "          _ManifestRestoreCandidate(\n"
    "            file: file,\n"
    "            sequence: sequence,\n"
    "            modifiedMillis: stat.modified.millisecondsSinceEpoch,\n"
    "            isTemp: file.path == temp.path,\n"
    "          ),\n"
    "        );\n"
    "      } catch (_) {\n"
    "        // A torn candidate is ignored; the other durable snapshot can win.\n"
    "      }\n"
    "    }\n"
    "    ranked.sort((a, b) {\n"
    "      final bySequence = b.sequence.compareTo(a.sequence);\n"
    "      if (bySequence != 0) return bySequence;\n"
    "      final byModified = b.modifiedMillis.compareTo(a.modifiedMillis);\n"
    "      if (byModified != 0) return byModified;\n"
    "      if (a.isTemp == b.isTemp) return 0;\n"
    "      return a.isTemp ? -1 : 1;\n"
    "    });\n"
    "    return ranked.map((candidate) => candidate.file).toList(growable: false);\n"
    "  }\n\n"
    "  bool _validRestoredLayout(\n"
    "    List<_DownloadPart> parts,\n"
    "    int declaredTotalBytes,\n"
    "  ) {\n"
    "    if (parts.isEmpty) return false;\n"
    "    var nextByte = 0;\n"
    "    var total = 0;\n"
    "    for (final part in parts) {\n"
    "      if (part.from != nextByte || part.to < part.from) return false;\n"
    "      total += part.size;\n"
    "      nextByte = part.to + 1;\n"
    "    }\n"
    "    if (total <= 0) return false;\n"
    "    return declaredTotalBytes <= 0 || declaredTotalBytes == total;\n"
    "  }\n\n"
    "  int? _taskAttemptGeneration(DownloadTask task) {\n"
    "    try {\n"
    "      final raw = task.metaData.trim();\n"
    "      if (raw.isEmpty) return null;\n"
    "      final decoded = jsonDecode(raw);\n"
    "      if (decoded is! Map) return null;\n"
    "      return (decoded['attemptGeneration'] as num?)?.toInt();\n"
    "    } catch (_) {\n"
    "      return null;\n"
    "    }\n"
    "  }\n\n"
    "  String _partAttemptMetadata(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part,\n"
    "  ) {\n"
    "    final metadata = <String, dynamic>{};\n"
    "    try {\n"
    "      final raw = part.task.metaData.trim();\n"
    "      if (raw.isNotEmpty) {\n"
    "        final decoded = jsonDecode(raw);\n"
    "        if (decoded is Map) {\n"
    "          metadata.addAll(Map<String, dynamic>.from(decoded));\n"
    "        }\n"
    "      }\n"
    "    } catch (_) {}\n"
    "    metadata['parentTaskId'] = session.task.taskId;\n"
    "    metadata['attemptGeneration'] = part.attemptGeneration;\n"
    "    return jsonEncode(metadata);\n"
    "  }\n\n"
    "  void _refreshPartAttemptMetadata(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part,\n"
    "  ) {\n"
    "    part.task = part.task.copyWith(\n"
    "      metaData: _partAttemptMetadata(session, part),\n"
    "    );\n"
    "  }\n\n"
    "  void _preparePartAttempt(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part,\n"
    "  ) {\n"
    "    if (part.attemptGeneration <= 0) part.attemptGeneration = 1;\n"
    "    _refreshPartAttemptMetadata(session, part);\n"
    "  }\n\n"
    "  void _invalidatePartAttempt(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part,\n"
    "  ) {\n"
    "    part.attemptGeneration = part.attemptGeneration <= 0\n"
    "        ? 1\n"
    "        : part.attemptGeneration + 1;\n"
    "    _refreshPartAttemptMetadata(session, part);\n"
    "  }\n\n"
    "  Future<void> dispose() async {",
    'manifest helpers',
)

replace_once(
    "    final temp = File('${manifest.path}.tmp');\n\n"
    "    for (final candidate in <File>[manifest, temp]) {",
    "    final temp = File('${manifest.path}.tmp');\n"
    "    final candidates = await _orderedManifestCandidates(\n"
    "      manifest,\n"
    "      temp,\n"
    "      task.taskId,\n"
    "    );\n\n"
    "    for (final candidate in candidates) {",
    'restore candidate order',
)

replace_once(
    "        final json = jsonDecode(raw) as Map<String, dynamic>;\n"
    "        final partJson = json['parts'];",
    "        final json = jsonDecode(raw) as Map<String, dynamic>;\n"
    "        final parentTaskId = json['parentTaskId']?.toString().trim();\n"
    "        if (parentTaskId != null &&\n"
    "            parentTaskId.isNotEmpty &&\n"
    "            parentTaskId != task.taskId) {\n"
    "          continue;\n"
    "        }\n"
    "        final manifestGeneration =\n"
    "            (json['generation'] as num?)?.toInt() ?? 0;\n"
    "        final checkpointSequence =\n"
    "            (json['checkpointSequence'] as num?)?.toInt() ?? 0;\n"
    "        final declaredTotalBytes =\n"
    "            (json['totalBytes'] as num?)?.toInt() ?? -1;\n"
    "        if (manifestGeneration < 0 || checkpointSequence < 0) continue;\n"
    "        final partJson = json['parts'];",
    'restore metadata parse',
)

replace_once(
    "        if (parts.length > kDownloadWorkUnitsMax ||\n"
    "            parts.any((part) => part.from < 0 || part.to < part.from)) {\n"
    "          continue;\n"
    "        }\n"
    "        final session = _ParallelSession(task, manifest, parts);\n"
    "        _register(session);",
    "        if (parts.length > kDownloadWorkUnitsMax ||\n"
    "            parts.any((part) => part.from < 0 || part.to < part.from) ||\n"
    "            !_validRestoredLayout(parts, declaredTotalBytes)) {\n"
    "          continue;\n"
    "        }\n"
    "        final session = _ParallelSession(task, manifest, parts)\n"
    "          ..generation = manifestGeneration\n"
    "          ..checkpointSequence = checkpointSequence;\n"
    "        _register(session);",
    'restore layout validation',
)

replace_once(
    "      session.generation++;\n"
    "      session.active = true;\n"
    "      session.resetRamp();\n"
    "      try {\n"
    "        await _status(session, TaskStatus.enqueued);",
    "      session.generation++;\n"
    "      session.active = true;\n"
    "      session.resetRamp();\n"
    "      try {\n"
    "        // Persist the logical generation before any child is handed to native IO.\n"
    "        await _persist(session);\n"
    "        await _status(session, TaskStatus.enqueued);",
    'persist session generation before launch',
)

replace_once(
    "        // Reserve before enqueueing to close the enqueue->running race. This\n"
    "        // also keeps 5 episodes x 16 parts from becoming 80 native requests.\n"
    "        part.launched = true;",
    "        // Give every native enqueue a durable attempt token. Retried/resumed\n"
    "        // workers keep the same taskId/Range but never the same generation.\n"
    "        _preparePartAttempt(session, part);\n"
    "        await _persist(session);\n\n"
    "        // Reserve before enqueueing to close the enqueue->running race. This\n"
    "        // also keeps 5 episodes x 16 parts from becoming 80 native requests.\n"
    "        part.launched = true;",
    'prepare child attempt before native enqueue',
)

replace_once(
    "          rollbackUnownedReservation();\n"
    "          _schedulePartRecovery(session, part);\n"
    "          try {\n"
    "            await _status(session, TaskStatus.running);",
    "          rollbackUnownedReservation();\n"
    "          _schedulePartRecovery(session, part);\n"
    "          await _persist(session);\n"
    "          try {\n"
    "            await _status(session, TaskStatus.running);",
    'persist thrown enqueue recovery',
)

replace_once(
    "          rollbackUnownedReservation();\n"
    "          _schedulePartRecovery(session, part);\n"
    "          await _status(session, TaskStatus.running);",
    "          rollbackUnownedReservation();\n"
    "          _schedulePartRecovery(session, part);\n"
    "          await _persist(session);\n"
    "          await _status(session, TaskStatus.running);",
    'persist false enqueue recovery',
)

replace_once(
    "      if (part == null || part.complete) return;\n\n"
    "      // The immutable Range in the manifest is the authority.",
    "      // Native bridge updates do not carry the Dart task metadata token.\n"
    "      // Accept them only while this exact child currently owns a slot.\n"
    "      if (part == null || part.complete || !part.launched) return;\n\n"
    "      // The immutable Range in the manifest is the authority.",
    'native bridge stale owner guard',
)

replace_once(
    "          final part = session.parts.firstWhere(\n"
    "            (part) => part.task.taskId == update.task.taskId,\n"
    "          );\n"
    "          // Completion is durable; a late running/progress/retry callback must\n"
    "          // never reserve its connection again or park the remaining parts.\n"
    "          if (part.complete) return;",
    "          final part = session.parts.firstWhere(\n"
    "            (part) => part.task.taskId == update.task.taskId,\n"
    "          );\n"
    "          final callbackAttempt = _taskAttemptGeneration(update.task);\n"
    "          if (callbackAttempt != null &&\n"
    "              part.attemptGeneration > 0 &&\n"
    "              callbackAttempt != part.attemptGeneration) {\n"
    "            diagnosticLog?.record('parallel.staleChildCallback', {\n"
    "              'taskId': session.task.taskId,\n"
    "              'childTaskId': part.task.taskId,\n"
    "              'callbackAttempt': callbackAttempt,\n"
    "              'currentAttempt': part.attemptGeneration,\n"
    "            });\n"
    "            return;\n"
    "          }\n"
    "          // Completion is durable; a late running/progress/retry callback must\n"
    "          // never reserve its connection again or park the remaining parts.\n"
    "          if (part.complete) return;\n"
    "          if (!part.launched &&\n"
    "              !(update is TaskStatusUpdate &&\n"
    "                  update.status == TaskStatus.complete)) {\n"
    "            return;\n"
    "          }",
    'plugin callback attempt fence',
)

replace_once(
    "              _stabilizeSessionForRecovery(session);\n"
    "              _schedulePartRecovery(session, part);\n"
    "              await _status(session, TaskStatus.running);",
    "              _stabilizeSessionForRecovery(session);\n"
    "              _schedulePartRecovery(session, part);\n"
    "              await _persist(session);\n"
    "              await _status(session, TaskStatus.running);",
    'persist automatic child recovery',
)

replace_once(
    "    _cancelTailStallWatch(part);\n"
    "    part.recoveryAttempts++;\n"
    "    part.speed = 0;\n\n"
    "    // Backoff is not an active connection.",
    "    _cancelTailStallWatch(part);\n"
    "    part.recoveryAttempts++;\n"
    "    part.speed = 0;\n"
    "    _invalidatePartAttempt(session, part);\n\n"
    "    // Backoff is not an active connection.",
    'invalidate child on recovery',
)

replace_once(
    "        if (owns) {\n"
    "          _activeConnectionIds.add(part.task.taskId);\n"
    "        } else {\n"
    "          _activeConnectionIds.remove(part.task.taskId);\n"
    "        }",
    "        if (owns) {\n"
    "          _activeConnectionIds.add(part.task.taskId);\n"
    "        } else {\n"
    "          _invalidatePartAttempt(session, part);\n"
    "          _activeConnectionIds.remove(part.task.taskId);\n"
    "        }",
    'invalidate settled children when pause partially fails',
)

replace_once(
    "    for (final part in unfinished) {\n"
    "      part.launched = false;\n"
    "      part.speed = 0;\n"
    "    }",
    "    for (final part in unfinished) {\n"
    "      _invalidatePartAttempt(session, part);\n"
    "      part.launched = false;\n"
    "      part.speed = 0;\n"
    "    }",
    'invalidate children on successful pause',
)

replace_once(
    "  Future<void> _persist(_ParallelSession session) async {\n"
    "    if (session.deleted) return;\n"
    "    await session.manifest.parent.create(recursive: true);\n"
    "    final payload = jsonEncode({\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n"
    "    });",
    "  Future<void> _persist(_ParallelSession session) async {\n"
    "    if (session.deleted) return;\n"
    "    await session.manifest.parent.create(recursive: true);\n"
    "    session.checkpointSequence++;\n"
    "    final payload = jsonEncode({\n"
    "      'schemaVersion': kParallelManifestSchemaVersion,\n"
    "      'parentTaskId': session.task.taskId,\n"
    "      'generation': session.generation,\n"
    "      'checkpointSequence': session.checkpointSequence,\n"
    "      'totalBytes': session.size,\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n"
    "    });",
    'versioned manifest payload',
)

replace_once(
    "  bool deleted = false;\n"
    "  int generation = 0;\n"
    "  int connectionCeiling = kDownloadPartsMin;",
    "  bool deleted = false;\n"
    "  int generation = 0;\n"
    "  int checkpointSequence = 0;\n"
    "  int connectionCeiling = kDownloadPartsMin;",
    'session checkpoint sequence',
)

replace_once(
    "    this.progress = 0,\n"
    "    this.complete = false,\n"
    "    double? credibleProgress,",
    "    this.progress = 0,\n"
    "    this.complete = false,\n"
    "    this.attemptGeneration = 0,\n"
    "    double? credibleProgress,",
    'part attempt constructor',
)

replace_once(
    "  bool complete;\n"
    "  bool launched = false;\n"
    "  double speed = 0;",
    "  bool complete;\n"
    "  int attemptGeneration;\n"
    "  bool launched = false;\n"
    "  double speed = 0;",
    'part attempt field',
)

replace_once(
    "      progress: complete ? 1 : rawProgress,\n"
    "      complete: complete,\n"
    "      credibleProgress: complete",
    "      progress: complete ? 1 : rawProgress,\n"
    "      complete: complete,\n"
    "      attemptGeneration:\n"
    "          (json['attemptGeneration'] as num?)?.toInt() ?? 0,\n"
    "      credibleProgress: complete",
    'restore part attempt generation',
)

replace_once(
    "    'credibleProgress': credibleProgress,\n"
    "    'complete': complete,\n"
    "  };\n}",
    "    'credibleProgress': credibleProgress,\n"
    "    'complete': complete,\n"
    "    'attemptGeneration': attemptGeneration,\n"
    "  };\n}",
    'persist part attempt generation',
)

text += "\n\nclass _ManifestRestoreCandidate {\n  const _ManifestRestoreCandidate({\n    required this.file,\n    required this.sequence,\n    required this.modifiedMillis,\n    required this.isTemp,\n  });\n\n  final File file;\n  final int sequence;\n  final int modifiedMillis;\n  final bool isTemp;\n}\n"
path.write_text(text)


test = Path('test/core/services/persistent_parallel_download_recovery_snapshot_test.dart')
test.write_text(r'''import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late ParallelDownloadTask parent;
  late Map<String, TaskRecord> records;
  late List<DownloadTask> starts;
  late Set<String> liveIds;
  late PersistentParallelDownload coordinator;

  PersistentParallelDownload create() => PersistentParallelDownload(
    startPart: (task, progress, size) async {
      starts.add(task);
      return true;
    },
    pausePart: (task) async {},
    cancelParts: (ids) async {},
    saveRecord: (record) async {
      records[record.task.taskId] = record;
    },
    recordForId: (id) async => records[id],
    onUpdate: (_) {},
    onPartProgress: (_, _, _) {},
    livePartIds: () async => liveIds,
    recoveryDelay: const Duration(milliseconds: 40),
    diskProgressPollInterval: const Duration(seconds: 30),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('parallel-snapshot-');
    parent = ParallelDownloadTask(
      taskId: 'episode-snapshot',
      url: 'https://example.test/video.mp4',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 1,
      allowPause: true,
    );
    records = <String, TaskRecord>{};
    starts = <DownloadTask>[];
    liveIds = <String>{};
    coordinator = create();
  });

  tearDown(() async {
    await coordinator.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> waitUntil(bool Function() predicate) async {
    for (var index = 0; index < 200; index++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for recovery state');
  }

  int attemptGeneration(DownloadTask task) {
    final decoded = jsonDecode(task.metaData) as Map<String, dynamic>;
    return (decoded['attemptGeneration'] as num).toInt();
  }

  Future<File> manifestFile() async =>
      File('${await parent.filePath()}.parts/manifest.json');

  test('manifest persists identity, generation, sequence, and attempt token', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    expect(starts, hasLength(1));

    final manifest = await manifestFile();
    final json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    expect(json['schemaVersion'], kParallelManifestSchemaVersion);
    expect(json['parentTaskId'], parent.taskId);
    expect(json['totalBytes'], 20);
    expect((json['generation'] as num).toInt(), greaterThanOrEqualTo(1));
    expect((json['checkpointSequence'] as num).toInt(), greaterThan(0));
    expect(
      ((json['parts'] as List).single as Map)['attemptGeneration'],
      attemptGeneration(starts.single),
    );
  });

  test('newer tmp checkpoint wins over an older valid primary manifest', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    expect(await coordinator.pause(parent), isTrue);
    await coordinator.dispose();

    final manifest = await manifestFile();
    final primary = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final primaryPart = (primary['parts'] as List).single as Map<String, dynamic>;
    primary['checkpointSequence'] = 100;
    primaryPart['progress'] = 0.10;
    primaryPart['credibleProgress'] = 0.10;
    primaryPart['complete'] = false;
    await manifest.writeAsString(jsonEncode(primary), flush: true);

    final newer = jsonDecode(jsonEncode(primary)) as Map<String, dynamic>;
    final newerPart = (newer['parts'] as List).single as Map<String, dynamic>;
    newer['checkpointSequence'] = 101;
    newerPart['progress'] = 0.60;
    newerPart['credibleProgress'] = 0.60;
    final temp = File('${manifest.path}.tmp');
    await temp.writeAsString(jsonEncode(newer), flush: true);

    starts = <DownloadTask>[];
    coordinator = create();
    expect(await coordinator.restore(parent), isTrue);
    expect(coordinator.progressFor(parent.taskId), closeTo(0.60, 0.001));

    final promoted = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    expect(promoted['checkpointSequence'], 101);
    expect(await temp.exists(), isFalse);
  });

  test('restore rejects a snapshot that belongs to another parent', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    expect(await coordinator.pause(parent), isTrue);
    await coordinator.dispose();

    final manifest = await manifestFile();
    final json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    json['parentTaskId'] = 'different-episode';
    await manifest.writeAsString(jsonEncode(json), flush: true);

    coordinator = create();
    expect(await coordinator.restore(parent), isFalse);
  });

  test('restore rejects gaps or overlaps in persisted range layout', () async {
    parent = ParallelDownloadTask(
      taskId: 'episode-snapshot',
      url: 'https://example.test/video.mp4',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 2,
      allowPause: true,
    );
    expect(await coordinator.start(parent, 20), isTrue);
    expect(await coordinator.pause(parent), isTrue);
    await coordinator.dispose();

    final manifest = await manifestFile();
    final json = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final parts = json['parts'] as List;
    final second = parts[1] as Map<String, dynamic>;
    second['from'] = (second['from'] as int) + 1;
    await manifest.writeAsString(jsonEncode(json), flush: true);

    coordinator = create();
    expect(await coordinator.restore(parent), isFalse);
  });

  test('stale plugin running callback cannot cancel scheduled recovery', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    final firstAttempt = starts.single;
    final firstGeneration = attemptGeneration(firstAttempt);

    coordinator.handleUpdate(TaskStatusUpdate(firstAttempt, TaskStatus.paused));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    coordinator.handleUpdate(TaskStatusUpdate(firstAttempt, TaskStatus.running));

    await waitUntil(() => starts.length >= 2);
    final recovered = starts.last;
    expect(recovered.taskId, firstAttempt.taskId);
    expect(attemptGeneration(recovered), greaterThan(firstGeneration));
    expect(coordinator.isActive(parent.taskId), isTrue);
  });

  test('late native bridge bytes cannot resurrect a released child', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    final firstAttempt = starts.single;

    coordinator.handleUpdate(TaskStatusUpdate(firstAttempt, TaskStatus.paused));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await coordinator.handleNativeChunkUpdate(
      parentTaskId: parent.taskId,
      chunkTaskId: firstAttempt.taskId,
      writtenBytes: 1,
      expectedBytes: 20,
      speedBytesPerSecond: 1000,
    );

    await waitUntil(() => starts.length >= 2);
    expect(starts.last.taskId, firstAttempt.taskId);
    expect(coordinator.isActive(parent.taskId), isTrue);
  });
}
''')
