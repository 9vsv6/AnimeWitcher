import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import 'download_parallel.dart';

/// Native DownloadTasks transfer the parts; this coordinator persists their
/// identity before starting them. A process restart must not create new parts
/// or ask the plugin to resume an already completed part.
///
/// Fresh sessions use Gopeed-style slow start: 1, 2, 4, 8... connections. A
/// batch is not expanded until every child in that batch has actually reached
/// running/progress (or completed). This is intentionally response-gated rather
/// than timer-gated: if iOS/Android or the origin can only admit four requests,
/// the remaining connections stay queued instead of causing a connection storm.
class PersistentParallelDownload {
  PersistentParallelDownload({
    required this.startPart,
    required this.pausePart,
    required this.cancelParts,
    required this.saveRecord,
    required this.recordForId,
    required this.onUpdate,
    required this.onPartProgress,
    this.maxActiveConnections = kDownloadGlobalConnectionBudget,
  });

  final Future<bool> Function(DownloadTask task, double progress, int size)
  startPart;
  final Future<void> Function(DownloadTask task) pausePart;
  final Future<void> Function(List<String> ids) cancelParts;
  final Future<void> Function(TaskRecord record) saveRecord;
  final Future<TaskRecord?> Function(String id) recordForId;
  final void Function(TaskUpdate update) onUpdate;
  final void Function(String parent, String child, double progress)
  onPartProgress;
  final int maxActiveConnections;

  final Map<String, _ParallelSession> _sessions = {};
  final Map<String, _ParallelSession> _children = {};
  final Set<String> _activeConnectionIds = {};
  Future<void>? _pumpFuture;
  bool _disposed = false;

  bool isActive(String id) => !_disposed && (_sessions[id]?.active ?? false);

  /// Includes native tasks that were handed to the OS but are still waiting
  /// for a socket. Counting them is deliberate: the manager never queues more
  /// than the global connection budget into URLSession/background_downloader.
  int get activeConnectionCount => _activeConnectionIds.length;

  int get _connectionBudget =>
      maxActiveConnections.clamp(1, kDownloadGlobalConnectionBudget).toInt();

  Future<File> _manifest(DownloadTask task) async =>
      File('${await task.filePath()}.parts/manifest.json');

  /// Stops this Dart coordinator without pausing/canceling native children.
  ///
  /// URLSession/background_downloader may legitimately keep transferring after
  /// the ProviderScope is gone. We only stop scheduling new children and wait
  /// for already-queued manifest writes to settle, so the next process can
  /// restore those same ranges instead of racing an old coordinator.
  Future<void> dispose() async {
    if (_disposed) {
      final pump = _pumpFuture;
      if (pump != null) await pump;
      await Future.wait<void>(
        _sessions.values.map((session) => session.idle),
      );
      return;
    }
    _disposed = true;
    final pump = _pumpFuture;
    if (pump != null) await pump;
    await Future.wait<void>(
      _sessions.values.map((session) => session.idle),
    );
  }

  Future<bool> restore(ParallelDownloadTask task) async {
    if (_disposed) return false;
    if (_sessions.containsKey(task.taskId)) return true;
    final manifest = await _manifest(task);
    final temp = File('${manifest.path}.tmp');

    for (final candidate in <File>[manifest, temp]) {
      try {
        if (!await candidate.exists()) continue;
        final raw = await candidate.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final partJson = json['parts'];
        if (partJson is! List || partJson.isEmpty) continue;
        final parts = partJson
            .map(
              (part) => _DownloadPart.fromJson(
                Map<String, dynamic>.from(part as Map),
              ),
            )
            .toList(growable: false);
        if (parts.length > kDownloadPartsMax ||
            parts.any((part) => part.from < 0 || part.to < part.from)) {
          continue;
        }
        final session = _ParallelSession(task, manifest, parts);
        _register(session);

        // A kill can happen after the durable .tmp write and before rename.
        // Recover that checkpoint instead of throwing all saved ranges away.
        if (candidate.path == temp.path) {
          await manifest.parent.create(recursive: true);
          await manifest.writeAsString(raw, flush: true);
          try {
            if (await temp.exists()) await temp.delete();
          } catch (_) {}
        }
        return true;
      } catch (_) {
        // Try the .tmp checkpoint when the primary manifest was torn/corrupt.
      }
    }
    return false;
  }

  void _register(_ParallelSession session) {
    _sessions[session.task.taskId] = session;
    for (final part in session.parts) {
      _children[part.task.taskId] = session;
    }
  }

  /// Imports legacy plugin checkpoints without cancelling/deleting their files.
  /// Completed parts keep their filenames; the remaining native resume blobs
  /// stay associated with the same child taskIds.
  Future<void> importLegacy(
    ParallelDownloadTask task,
    String resumeData,
  ) async {
    if (_disposed) return;
    if (await restore(task)) return;
    final chunks = jsonDecode(resumeData) as List;
    if (chunks.isEmpty) throw const FormatException('Empty chunk checkpoint');
    final parts = chunks.map((raw) {
      final chunk = Map<String, dynamic>.from(raw as Map);
      final child = Task.createFromJson(
        Map<String, dynamic>.from(chunk['task'] as Map),
      ) as DownloadTask;
      return _DownloadPart(
        child.copyWith(group: kPersistentDownloadChunkGroup),
        (chunk['fromByte'] as num).toInt(),
        (chunk['toByte'] as num).toInt(),
        progress: (chunk['progress'] as num? ?? 0).toDouble(),
        complete: chunk['status'] == TaskStatus.complete.index,
      );
    }).toList();
    final session = _ParallelSession(task, await _manifest(task), parts);
    await _persist(session);
    _register(session);
  }

  Future<bool> start(ParallelDownloadTask task, int totalBytes) async {
    if (_disposed) return false;
    final restored = await restore(task);
    if (!restored) {
      if (totalBytes <= 0) return false;
      final count = task.chunks
          .clamp(1, totalBytes)
          .clamp(kDownloadPartsMin, kDownloadPartsMax)
          .toInt();
      final parts = <_DownloadPart>[];
      for (var index = 0; index < count; index++) {
        final from = totalBytes * index ~/ count;
        final to = totalBytes * (index + 1) ~/ count - 1;
        final headers = Map<String, String>.from(task.headers)
          ..removeWhere((key, _) => key.toLowerCase() == 'range');
        headers['Range'] = 'bytes=$from-$to';
        headers['Accept-Encoding'] = 'identity';
        parts.add(
          _DownloadPart(
            DownloadTask(
              taskId: '${task.taskId}.part.$index',
              url: task.url,
              filename: '$index.part',
              directory: p.join(task.directory, '${task.filename}.parts'),
              baseDirectory: task.baseDirectory,
              headers: headers,
              updates: Updates.statusAndProgress,
              retries: kDownloadPartRetries,
              allowPause: true,
              group: kPersistentDownloadChunkGroup,
              metaData: jsonEncode({'parentTaskId': task.taskId}),
            ),
            from,
            to,
          ),
        );
      }
      final session = _ParallelSession(task, await _manifest(task), parts);
      await _persist(session);
      _register(session);
    }

    final session = _sessions[task.taskId]!;
    return session.serialize(() async {
      if (_disposed) return false;
      if (session.active) return true;
      session.active = true;
      session.resetRamp();
      try {
        await _status(session, TaskStatus.enqueued);

        // Crash window: assembly may already have atomically renamed the final
        // file before the parent complete record/cleanup was persisted. Adopt
        // that exact-size target instead of assembling or downloading again.
        if (await _adoptCompletedTarget(session)) return true;

        for (final part in session.parts) {
          part.launched = false;
          part.speed = 0;
          final file = File(await part.task.filePath());
          if (await file.exists() && await file.length() == part.size) {
            part.complete = true;
            part.progress = 1;
            continue;
          }
          // A previously completed file that vanished must not be silently
          // downloaded again. Keep the episode paused for an explicit delete.
          if (part.complete) throw StateError('A completed part is missing');
        }

        final pending = session.parts.where((part) => !part.complete).length;
        if (pending == 0) {
          await _assemble(session);
          return true;
        }

        // Use the same response-gated slow start for fresh and resumed files.
        // A child already owned by URLSession is recognized below from its
        // running database record, so process recovery can advance without
        // reopening all persisted ranges at once.
        session.rampBatches = downloadConnectionRampBatches(pending);

        if (!await _pumpSession(session)) {
          throw StateError('Could not start initial download connection');
        }
        await _persist(session);
        _schedulePumpAll();
        return true;
      } catch (_) {
        await _pause(session);
        return false;
      }
    });
  }

  /// Launches as much of the current slow-start batch as the global budget
  /// permits. Once a full batch is launched, expansion stops until all members
  /// have produced a running/progress/completion signal, matching Gopeed's
  /// response-driven slow-start controller.
  Future<bool> _pumpSession(_ParallelSession session) async {
    if (_disposed || !session.active || session.deleted) return true;

    while (!_disposed && session.active && !session.deleted) {
      if (session.currentBatchRemaining == 0) {
        if (session.currentBatchPendingIds.isNotEmpty) return true;
        if (session.rampBatchIndex >= session.rampBatches.length) return true;
        session.currentBatchRemaining =
            session.rampBatches[session.rampBatchIndex++];
      }

      final available = _connectionBudget - _activeConnectionIds.length;
      if (available <= 0) return true;

      final launchCount = session.currentBatchRemaining < available
          ? session.currentBatchRemaining
          : available;
      final parts = session.parts
          .where((part) => !part.complete && !part.launched)
          .take(launchCount)
          .toList(growable: false);

      if (parts.isEmpty) {
        session.currentBatchRemaining = 0;
        continue;
      }

      for (final part in parts) {
        if (_disposed) return true;
        final record = await recordForId(part.task.taskId);
        final progress = record?.progress ?? 0;
        if (progress > part.progress && progress <= 1) {
          part.progress = progress;
        }

        // Reserve before enqueueing to close the same enqueue->running race as
        // the logical episode queue. This is also what keeps 5 episodes x 16
        // parts from turning into 80 native requests.
        part.launched = true;
        _activeConnectionIds.add(part.task.taskId);
        session.currentBatchPendingIds.add(part.task.taskId);
        session.currentBatchRemaining--;

        if (!await startPart(part.task, part.progress, part.size)) {
          part.launched = false;
          _activeConnectionIds.remove(part.task.taskId);
          session.currentBatchPendingIds.remove(part.task.taskId);
          return false;
        }

        // On process recovery a native child can already be transferring, in
        // which case no fresh `running` callback is guaranteed. Treat an
        // existing running/retrying record as Gopeed's connect-success signal.
        if (record != null &&
            (record.status == TaskStatus.running ||
                record.status == TaskStatus.waitingToRetry)) {
          session.currentBatchPendingIds.remove(part.task.taskId);
        }
      }

      // A partially launched batch is waiting for capacity. A completed/paused
      // child in any session will schedule the global pump again.
      if (session.currentBatchRemaining > 0) return true;
      if (session.currentBatchPendingIds.isNotEmpty) return true;
    }
    return true;
  }

  void _markConnectionReady(_ParallelSession session, _DownloadPart part) {
    if (!session.currentBatchPendingIds.remove(part.task.taskId)) return;
    if (session.currentBatchRemaining == 0 &&
        session.currentBatchPendingIds.isEmpty) {
      _schedulePumpAll();
    }
  }

  void _releaseConnection(_DownloadPart part) {
    _activeConnectionIds.remove(part.task.taskId);
    part.launched = false;
    part.speed = 0;
    _schedulePumpAll();
  }

  void _schedulePumpAll() {
    if (_disposed || _pumpFuture != null) return;

    late final Future<void> pump;
    pump = Future<void>.microtask(() async {
      final sessions = List<_ParallelSession>.from(_sessions.values);
      for (final session in sessions) {
        if (_disposed) return;
        if (!session.active || session.deleted) continue;
        await session.serialize(() async {
          if (_disposed || !session.active || session.deleted) return;
          if (!await _pumpSession(session)) {
            await _pause(session);
          } else {
            await _persist(session);
          }
        });
      }
    }).catchError((Object _, StackTrace _) {
      // Session-level failures park their parent. An unexpected lifecycle race
      // must not become an unhandled asynchronous exception.
    }).whenComplete(() {
      if (identical(_pumpFuture, pump)) _pumpFuture = null;
      if (!_disposed &&
          _activeConnectionIds.length < _connectionBudget &&
          _sessions.values.any(_hasImmediatelyPumpableWork)) {
        _schedulePumpAll();
      }
    });
    _pumpFuture = pump;
  }

  bool _hasImmediatelyPumpableWork(_ParallelSession session) {
    if (_disposed || !session.active || session.deleted) return false;
    if (session.currentBatchRemaining > 0) return true;
    return session.currentBatchPendingIds.isEmpty &&
        session.rampBatchIndex < session.rampBatches.length;
  }

  bool handleUpdate(TaskUpdate update) {
    if (update.task.group != kPersistentDownloadChunkGroup) return false;
    if (_disposed) return true;
    final session = _children[update.task.taskId];
    if (session == null) return true; // recovery reads the child's DB record

    unawaited(
      session.serialize(() async {
        try {
          if (_disposed || session.deleted) return;
          final part = session.parts.firstWhere(
            (part) => part.task.taskId == update.task.taskId,
          );

          if (update is TaskProgressUpdate &&
              update.progress >= 0 &&
              update.progress <= 1) {
            if (session.active) {
              part.launched = true;
              _activeConnectionIds.add(part.task.taskId);
              _markConnectionReady(session, part);
            }
            part.progress = update.progress > part.progress
                ? update.progress
                : part.progress;
            part.speed = update.networkSpeed > 0 ? update.networkSpeed : 0;
            onPartProgress(
              session.task.taskId,
              part.task.taskId,
              part.progress,
            );
            await _persist(session);
            if (session.active) {
              final progress = session.progress;
              await saveRecord(
                TaskRecord(
                  session.task,
                  TaskStatus.running,
                  progress,
                  session.size,
                ),
              );
              onUpdate(
                TaskProgressUpdate(
                  session.task,
                  progress,
                  session.size,
                  session.parts.fold<double>(
                    0,
                    (sum, child) => sum + child.speed,
                  ),
                ),
              );
            }
            _schedulePumpAll();
            return;
          }

          if (update is! TaskStatusUpdate) return;
          if (update.status == TaskStatus.complete) {
            // Validate the byte range before freeing its connection or
            // expanding. Gopeed treats invalid/incomplete range responses as
            // terminal for that connection and never lets them unlock more IO.
            final file = File(await part.task.filePath());
            if (!await file.exists() || await file.length() != part.size) {
              throw StateError(
                'Invalid byte count for part ${part.task.taskId}',
              );
            }
            _markConnectionReady(session, part);
            _releaseConnection(part);
            part.complete = true;
            part.progress = 1;
            onPartProgress(session.task.taskId, part.task.taskId, 1);
            await _persist(session);
            if (session.active &&
                session.parts.every((child) => child.complete)) {
              await _assemble(session);
            } else {
              _schedulePumpAll();
            }
            return;
          }

          if (session.active && update.status == TaskStatus.running) {
            part.launched = true;
            _activeConnectionIds.add(part.task.taskId);
            _markConnectionReady(session, part);
            await _status(session, TaskStatus.running);
            _schedulePumpAll();
            return;
          }

          if (session.active &&
              (update.status == TaskStatus.failed ||
                  update.status == TaskStatus.notFound ||
                  update.status == TaskStatus.canceled ||
                  update.status == TaskStatus.paused)) {
            _markConnectionReady(session, part);
            _releaseConnection(part);
            // Each child already had three bounded native attempts. Unlike
            // Gopeed we cannot safely steal this fixed byte range without
            // mutating an in-flight URLSession task, so preserve every byte and
            // pause the parent for an exact-range resume instead of corrupting
            // the file or spinning on retries.
            await _pause(session);
          }
        } catch (_) {
          if (!_disposed && !session.deleted) await _pause(session);
        }
      }),
    );
    return true;
  }

  Future<void> pause(ParallelDownloadTask task) async {
    if (_disposed) return;
    if (!await restore(task)) return;
    final session = _sessions[task.taskId]!;
    await session.serialize(() => _pause(session));
  }

  Future<void> _pause(_ParallelSession session) async {
    session.active = false;
    session.resetRamp();
    for (final part in session.parts.where(
      (part) => !part.complete && part.launched,
    )) {
      try {
        await pausePart(part.task);
      } catch (_) {}
      part.launched = false;
      part.speed = 0;
    }
    final ids = session.parts.map((part) => part.task.taskId).toSet();
    _activeConnectionIds.removeWhere(ids.contains);
    await _persist(session);
    await _status(session, TaskStatus.paused);
    _schedulePumpAll();
  }

  Future<void> cancel(ParallelDownloadTask task) async {
    if (_disposed) return;
    if (!await restore(task)) return;
    final session = _sessions[task.taskId]!;
    session.deleted = true;
    session.active = false;
    session.resetRamp();
    await session.serialize(() async {
      for (final part in session.parts) {
        _activeConnectionIds.remove(part.task.taskId);
      }
      await cancelParts(session.parts.map((part) => part.task.taskId).toList());
      for (final part in session.parts) {
        _children.remove(part.task.taskId);
        final file = File(await part.task.filePath());
        if (await file.exists()) await file.delete();
      }
      if (await session.manifest.parent.exists()) {
        await session.manifest.parent.delete(recursive: true);
      }
      final staging = File('${await task.filePath()}.assembling');
      if (await staging.exists()) await staging.delete();
      _sessions.remove(task.taskId);
    });
    _schedulePumpAll();
  }

  Future<void> _status(_ParallelSession session, TaskStatus status) async {
    await saveRecord(
      TaskRecord(session.task, status, session.progress, session.size),
    );
    onUpdate(TaskStatusUpdate(session.task, status));
  }

  Future<void> _persist(_ParallelSession session) async {
    if (session.deleted) return;
    await session.manifest.parent.create(recursive: true);
    final payload = jsonEncode({
      'parts': session.parts.map((part) => part.toJson()).toList(),
    });
    final temp = File('${session.manifest.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    try {
      await temp.rename(session.manifest.path);
    } on FileSystemException {
      // Some Windows filesystems do not replace an existing target on rename.
      // Keep the old manifest until the new checkpoint is fully written, then
      // fall back to an in-place flushed replacement.
      await session.manifest.writeAsString(payload, flush: true);
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  Future<bool> _adoptCompletedTarget(_ParallelSession session) async {
    final target = File(await session.task.filePath());
    if (!await target.exists()) return false;
    if (await target.length() != session.size) return false;
    await _finishCompleteSession(session);
    return true;
  }

  Future<void> _finishCompleteSession(_ParallelSession session) async {
    session.active = false;
    session.resetRamp();
    for (final part in session.parts) {
      _activeConnectionIds.remove(part.task.taskId);
    }
    onUpdate(TaskProgressUpdate(session.task, 1, session.size));
    await _status(session, TaskStatus.complete);

    // Delete child checkpoints only after the final file and parent complete
    // record are durable. A kill before this point leaves enough state to adopt
    // the completed target on the next launch.
    for (final part in session.parts) {
      _children.remove(part.task.taskId);
      final file = File(await part.task.filePath());
      if (await file.exists()) await file.delete();
    }
    if (await session.manifest.parent.exists()) {
      await session.manifest.parent.delete(recursive: true);
    }
    _sessions.remove(session.task.taskId);
    _schedulePumpAll();
  }

  Future<void> _assemble(_ParallelSession session) async {
    final target = File(await session.task.filePath());
    final staging = File('${target.path}.assembling');
    final output = await staging.open(mode: FileMode.write);
    try {
      for (final part in session.parts) {
        final file = File(await part.task.filePath());
        if (await file.length() != part.size) {
          throw StateError('Part size changed');
        }
        await for (final bytes in file.openRead()) {
          if (session.deleted) return;
          await output.writeFrom(bytes);
        }
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (session.deleted) return;
    if (await staging.length() != session.size) {
      throw StateError('Incomplete assembly');
    }
    if (await target.exists()) await target.delete();
    await staging.rename(target.path);
    await _finishCompleteSession(session);
  }
}

class _ParallelSession {
  _ParallelSession(this.task, this.manifest, this.parts);

  final ParallelDownloadTask task;
  final File manifest;
  final List<_DownloadPart> parts;
  bool active = false;
  bool deleted = false;
  List<int> rampBatches = const <int>[];
  int rampBatchIndex = 0;
  int currentBatchRemaining = 0;
  final Set<String> currentBatchPendingIds = {};
  Future<void> _pending = Future<void>.value();

  int get size => parts.fold(0, (sum, part) => sum + part.size);
  double get progress =>
      parts.fold<double>(0, (sum, part) => sum + part.size * part.progress) /
      size;
  Future<void> get idle => _pending;

  void resetRamp() {
    rampBatches = const <int>[];
    rampBatchIndex = 0;
    currentBatchRemaining = 0;
    currentBatchPendingIds.clear();
  }

  Future<T> serialize<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

class _DownloadPart {
  _DownloadPart(
    this.task,
    this.from,
    this.to, {
    this.progress = 0,
    this.complete = false,
  });

  final DownloadTask task;
  final int from;
  final int to;
  double progress;
  bool complete;
  bool launched = false;
  double speed = 0;

  int get size => to - from + 1;

  factory _DownloadPart.fromJson(Map<String, dynamic> json) => _DownloadPart(
    Task.createFromJson(
          Map<String, dynamic>.from(json['task'] as Map),
        )
        as DownloadTask,
    json['from'] as int,
    json['to'] as int,
    progress: (json['progress'] as num).toDouble(),
    complete: json['complete'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'task': task.toJson(),
    'from': from,
    'to': to,
    'progress': progress,
    'complete': complete,
  };
}
