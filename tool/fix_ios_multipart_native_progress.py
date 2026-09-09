from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one replacement, found {count}")
    write(path, text.replace(old, new, 1))


def regex_once(path, pattern, replacement):
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: regex replacement count={count}")
    write(path, updated)


persistent = "lib/core/services/persistent_parallel_download.dart"
service = "lib/core/services/download_service.dart"
continued = "lib/core/services/download_continued_processing_service.dart"
swift = "ios/Runner/DownloadNativeWaitingQueue.swift"
appdelegate = "ios/Runner/AppDelegate.swift"
ptest = "test/core/services/persistent_parallel_download_test.dart"

# Accept byte-accurate native iOS URLSession child updates directly.
native_method = r'''
  /// iOS writes DownloadTask bodies into URLSession-owned temporary files, so
  /// the final `.part` path can remain invisible until didFinishDownloadingTo.
  /// The native delegate bridge reports the bytes here while they are still in
  /// that temp file. This is byte evidence, not a guessed percentage: it wakes
  /// the logical parent, advances slow-start and keeps speed/progress live even
  /// when background_downloader's Dart callbacks are delayed or lost.
  Future<void> handleNativeChunkUpdate({
    required String parentTaskId,
    required String chunkTaskId,
    double? progress,
    int? writtenBytes,
    int? expectedBytes,
    double? speedBytesPerSecond,
    bool completed = false,
  }) async {
    if (_disposed) return;
    final session = _sessions[parentTaskId] ?? _children[chunkTaskId];
    if (session == null || session.deleted) return;

    await session.serialize(() async {
      if (_disposed ||
          session.deleted ||
          !identical(_sessions[session.task.taskId], session)) {
        return;
      }

      _DownloadPart? part;
      for (final candidate in session.parts) {
        if (candidate.task.taskId == chunkTaskId) {
          part = candidate;
          break;
        }
      }
      if (part == null || part.complete) return;

      // The immutable Range in the manifest is the authority. Never trust a
      // server-reported expected length enough to credit bytes outside it.
      int? observedBytes;
      double? credible;
      if (writtenBytes != null &&
          writtenBytes >= 0 &&
          writtenBytes <= part.size) {
        observedBytes = writtenBytes;
        credible = part.size > 0 ? writtenBytes / part.size : 0;
      } else if (progress != null && progress >= 0 && progress <= 1) {
        credible = progress;
      }

      // didFinishDownloadingTo is hooked after the plugin moves the temp body
      // to our final child path. Completion still requires exact local bytes.
      if (completed) {
        final file = File(await part.task.filePath());
        if (await file.exists() &&
            await file.length() == part.size &&
            await _adoptExactSizePart(
              session,
              part,
              settleNativeOwner: false,
            )) {
          await _afterAdoptedPart(session);
          return;
        }
      }

      if (credible == null) return;
      credible = credible.clamp(0.0, 1.0).toDouble();

      final previousCredible = part.credibleProgress;
      final now = DateTime.now();
      if (credible > previousCredible) {
        if (speedBytesPerSecond != null && speedBytesPerSecond > 0) {
          part.speed = speedBytesPerSecond / 1000 / 1000;
        } else if (observedBytes != null &&
            part.lastNativeBridgeBytes >= 0 &&
            part.lastNativeBridgeAt != null) {
          final elapsedMicros =
              now.difference(part.lastNativeBridgeAt!).inMicroseconds;
          final deltaBytes = observedBytes - part.lastNativeBridgeBytes;
          if (elapsedMicros > 0 && deltaBytes > 0) {
            part.speed =
                deltaBytes *
                Duration.microsecondsPerSecond /
                elapsedMicros /
                1000 /
                1000;
          }
        }

        part.credibleProgress = credible;
        if (part.progress >= kParallelNativeCompletionSentinel ||
            credible > part.progress) {
          part.progress = credible;
        }
        part.recoveryAttempts = 0;
        part.tailRecoveryAttempted = false;
      } else if (speedBytesPerSecond != null && speedBytesPerSecond > 0) {
        part.speed = speedBytesPerSecond / 1000 / 1000;
      }

      if (observedBytes != null) {
        part.lastNativeBridgeBytes = observedBytes;
        part.lastNativeBridgeAt = now;
      }

      if (session.active) {
        part.launched = true;
        _activeConnectionIds.add(part.task.taskId);
        _markConnectionReady(session, part);
      }

      if (credible > previousCredible || completed) {
        onPartProgress(
          session.task.taskId,
          part.task.taskId,
          part.credibleProgress,
        );
        await _persist(session);
      }

      if (!session.active) return;
      if (!session.parentRunningReported) {
        await _status(session, TaskStatus.running);
      }
      await _emitAggregateProgress(session);
      _schedulePumpAll();
    });
  }

'''
replace_once(
    persistent,
    "  bool handleUpdate(TaskUpdate update) {\n",
    native_method + "  bool handleUpdate(TaskUpdate update) {\n",
)

# Make parent pause truthful: only publish paused after native children no
# longer own URLSession work. A failed pause keeps the parent running.
regex_once(
    persistent,
    r"  Future<void> _pause\(_ParallelSession session\) async \{.*?\n  \}\n\n  Future<void> cancel\(",
    r'''  Future<bool> _pause(_ParallelSession session) async {
    session.active = false;
    session.generation++;
    session.cancelAggregateProgress();
    session.cancelDiskProgressPoll();
    session.resetRamp();

    final unfinished = session.parts
        .where((part) => !part.complete)
        .toList(growable: false);
    var pauseFailed = false;

    // Pause every actual child identity concurrently. DownloadService routes
    // these child tasks to FileDownloader.pause, which owns their URLSession
    // resume data; it must never route them through the single-file Transfer.
    await Future.wait(
      unfinished.map((part) async {
        try {
          await pausePart(part.task);
        } catch (_) {
          pauseFailed = true;
        }
      }),
    );

    Set<String> live = <String>{};
    final lookupLive = livePartIds;
    if (lookupLive != null) {
      try {
        live = await lookupLive();
      } catch (_) {
        pauseFailed = true;
      }
    }

    var stillLive = unfinished
        .where((part) => live.contains(part.task.taskId))
        .toList(growable: false);

    // A pause acknowledgement and the URLSession state transition are
    // asynchronous on iOS. Retry only identities that are still demonstrably
    // live; never cancel them, because cancel can discard resume bytes.
    if (stillLive.isNotEmpty) {
      await Future.wait(
        stillLive.map((part) async {
          try {
            await pausePart(part.task);
          } catch (_) {
            pauseFailed = true;
          }
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (lookupLive != null) {
        try {
          live = await lookupLive();
        } catch (_) {
          pauseFailed = true;
        }
      }
      stillLive = unfinished
          .where((part) => live.contains(part.task.taskId))
          .toList(growable: false);
    }

    if (stillLive.isNotEmpty || (lookupLive == null && pauseFailed)) {
      final stillIds = stillLive.map((part) => part.task.taskId).toSet();
      session.active = true;
      for (final part in unfinished) {
        final owns = stillIds.contains(part.task.taskId);
        part.launched = owns;
        part.speed = 0;
        if (owns) {
          _activeConnectionIds.add(part.task.taskId);
        } else {
          _activeConnectionIds.remove(part.task.taskId);
        }
      }
      _scheduleDiskProgressPoll(session);
      await _persist(session);
      await _status(session, TaskStatus.running);
      return false;
    }

    for (final part in unfinished) {
      part.launched = false;
      part.speed = 0;
    }
    final ids = session.parts.map((part) => part.task.taskId).toSet();
    _activeConnectionIds.removeWhere(ids.contains);
    await _persist(session);
    await _status(session, TaskStatus.paused);
    _schedulePumpAll();
    return true;
  }

  Future<void> cancel(''',
)

replace_once(
    persistent,
    '''  Future<void> pause(ParallelDownloadTask task) async {
    if (_disposed) return;
    if (!await restore(task)) return;
    final session = _sessions[task.taskId]!;
    await session.serialize(() => _pause(session));
  }
''',
    '''  Future<bool> pause(ParallelDownloadTask task) async {
    if (_disposed) return false;
    if (!await restore(task)) return false;
    final session = _sessions[task.taskId]!;
    return session.serialize(() => _pause(session));
  }
''',
)

replace_once(
    persistent,
    "  bool needsCredibleProgressRepair;\n\n  int get size => to - from + 1;\n",
    '''  bool needsCredibleProgressRepair;
  int lastNativeBridgeBytes = -1;
  DateTime? lastNativeBridgeAt;

  int get size => to - from + 1;
''',
)

# Wire native chunk updates into the coordinator, not only the decorative
# per-chunk provider.
replace_once(
    service,
    "      pausePart: _pauseTransfer,\n",
    '''      pausePart: (task) async {
        if (!await _pauseTransfer(task)) {
          throw StateError('Native multipart child did not pause');
        }
      },
''',
)

old_handle = '''  void _handleNativeChunkUpdate({
    required String parentTaskId,
    required String chunkTaskId,
    double? progress,
    int? statusOrdinal,
  }) {
    _ref
        .read(downloadChunkProgressProvider.notifier)
        .update(
          parentTaskId: parentTaskId,
          chunkTaskId: chunkTaskId,
          progress: progress,
          statusOrdinal: statusOrdinal,
        );
  }
'''
new_handle = '''  void _handleNativeChunkUpdate({
    required String parentTaskId,
    required String chunkTaskId,
    double? progress,
    int? statusOrdinal,
    int? writtenBytes,
    int? expectedBytes,
    double? speedBytesPerSecond,
    bool completed = false,
  }) {
    final derivedProgress = completed
        ? 1.0
        : (progress ??
              ((writtenBytes != null &&
                      expectedBytes != null &&
                      expectedBytes > 0)
                  ? writtenBytes / expectedBytes
                  : null));
    _ref
        .read(downloadChunkProgressProvider.notifier)
        .update(
          parentTaskId: parentTaskId,
          chunkTaskId: chunkTaskId,
          progress: derivedProgress,
          statusOrdinal: completed ? TaskStatus.complete.index : statusOrdinal,
        );

    unawaited(
      _parallel.handleNativeChunkUpdate(
        parentTaskId: parentTaskId,
        chunkTaskId: chunkTaskId,
        progress: derivedProgress,
        writtenBytes: writtenBytes,
        expectedBytes: expectedBytes,
        speedBytesPerSecond: speedBytesPerSecond,
        completed: completed,
      ),
    );
  }
'''
replace_once(service, old_handle, new_handle)

regex_once(
    service,
    r"  Future<void> _pauseTransfer\(DownloadTask task\) async \{.*?\n  \}\n\n  Future<bool> _startPart",
    r'''  Future<bool> _pauseTransfer(DownloadTask task) async {
    if (_rangeTransfers.isActive(task.taskId)) {
      await _rangeTransfers.stop(task.taskId);
      return true;
    }
    if (task is ParallelDownloadTask && await _parallel.restore(task)) {
      return _parallel.pause(task);
    }

    final settled = Completer<void>();
    final listener = _sharedEvents.stream.listen((update) {
      if (update.task.taskId == task.taskId &&
          update is TaskStatusUpdate &&
          (update.status == TaskStatus.paused || update.status.isFinalState)) {
        if (!settled.isCompleted) settled.complete();
      }
    });

    try {
      final accepted = isInternalDownloaderChunk(task)
          ? await FileDownloader().pause(task)
          : await _nativeTransport.pause(task);
      if (!accepted) return false;

      // pause() acknowledges the command before URLSession has necessarily
      // produced resume data. Wait for its state callback before resume can run.
      await settled.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

      if (isInternalDownloaderChunk(task)) {
        // Verify the child really left the live native set. If the first pause
        // raced URLSession hand-off, retry the same identity once; never cancel.
        var stillLive = (await _liveTransferTasks()).any(
          (live) => live.taskId == task.taskId,
        );
        if (stillLive) {
          if (!await FileDownloader().pause(task)) return false;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          stillLive = (await _liveTransferTasks()).any(
            (live) => live.taskId == task.taskId,
          );
        }
        if (stillLive) return false;
      }
      return true;
    } finally {
      await listener.cancel();
    }
  }

  Future<bool> _startPart''',
)

replace_once(
    service,
    '''    final didPause = downloadTask is ParallelDownloadTask
        ? await FileDownloader().pause(downloadTask)
        : await _nativeTransport.pause(downloadTask);
''',
    '''    final didPause = downloadTask is ParallelDownloadTask
        ? await _parallel.pause(downloadTask)
        : await _nativeTransport.pause(downloadTask);
''',
)

replace_once(
    service,
    '''        try {
          await _pauseTransfer(downloadTask);
        } catch (_) {}
        final trackingUrl = downloadTrackingUrl(downloadTask);
''',
    '''        var didPause = false;
        try {
          didPause = await _pauseTransfer(downloadTask);
        } catch (_) {}
        final trackingUrl = downloadTrackingUrl(downloadTask);
''',
)

pause_record_marker = '''        await FileDownloader().database.updateRecord(
          TaskRecord(downloadTask, TaskStatus.paused, progress, totalSize),
        );
'''
pause_failure_branch = '''        if (!didPause) {
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
            trackingUrl: trackingUrl,
            taskId: taskId,
            progress: progress,
            totalSize: totalSize,
            status: TaskStatus.running,
            networkSpeed: current?.networkSpeed ?? 0,
            timeRemaining: current?.timeRemaining ?? Duration.zero,
          );
          _updatesController.add(
            TaskStatusUpdate(downloadTask, TaskStatus.running),
          );
          await _syncSessionOverlay(completedSuccess: false);
          await _persistNativeWaitingSnapshot();
          return;
        }

''' + pause_record_marker
replace_once(service, pause_record_marker, pause_failure_branch)

# Extend the existing native -> Dart chunk channel with raw byte evidence.
replace_once(
    continued,
    '''typedef SystemDownloadChunkUpdate =
    void Function({
      required String parentTaskId,
      required String chunkTaskId,
      double? progress,
      int? statusOrdinal,
    });
''',
    '''typedef SystemDownloadChunkUpdate =
    void Function({
      required String parentTaskId,
      required String chunkTaskId,
      double? progress,
      int? statusOrdinal,
      int? writtenBytes,
      int? expectedBytes,
      double? speedBytesPerSecond,
      required bool completed,
    });
''',
)

replace_once(
    continued,
    '''      final rawProgress = arguments['progress'];
      final rawStatus = arguments['status'];
      onChunkUpdate?.call(
        parentTaskId: parentTaskId,
        chunkTaskId: chunkTaskId,
        progress: rawProgress is num ? rawProgress.toDouble() : null,
        statusOrdinal: rawStatus is num ? rawStatus.toInt() : null,
      );
''',
    '''      final rawProgress = arguments['progress'];
      final rawStatus = arguments['status'];
      final rawWritten = arguments['writtenBytes'];
      final rawExpected = arguments['expectedBytes'];
      final rawSpeed = arguments['speedBytesPerSecond'];
      onChunkUpdate?.call(
        parentTaskId: parentTaskId,
        chunkTaskId: chunkTaskId,
        progress: rawProgress is num ? rawProgress.toDouble() : null,
        statusOrdinal: rawStatus is num ? rawStatus.toInt() : null,
        writtenBytes: rawWritten is num ? rawWritten.toInt() : null,
        expectedBytes: rawExpected is num ? rawExpected.toInt() : null,
        speedBytesPerSecond: rawSpeed is num ? rawSpeed.toDouble() : null,
        completed: arguments['completed'] == true,
      );
''',
)

# Produce the chunk events from the native URLSession delegate.
replace_once(
    swift,
    "  private static var lastWrites: [String: WriteSample] = [:]\n",
    '''  private static var lastWrites: [String: WriteSample] = [:]
  private static var lastChunkWrites: [String: WriteSample] = [:]
  private static let chunkBridgeInterval: CFTimeInterval = 0.25
''',
)

replace_once(
    swift,
    "    lastWrites.removeAll()\n",
    '''    lastWrites.removeAll()
    lastChunkWrites.removeAll()
''',
)

chunk_helpers = r'''
  private static func parentTaskId(from task: URLSessionTask) -> String? {
    let description = task.taskDescription ?? ""
    let json = description.components(separatedBy: "***<<<|>>>***").first ?? description
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    if let meta = object["metaData"] as? String,
       let metaData = meta.data(using: .utf8),
       let metadata = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
       let parent = metadata["parentTaskId"] as? String,
       !parent.isEmpty {
      return parent
    }

    let child = object["taskId"] as? String ?? ""
    if let range = child.range(of: ".part.", options: .backwards) {
      let parent = String(child[..<range.lowerBound])
      return parent.isEmpty ? nil : parent
    }
    return nil
  }

  /// Forward native URLSession byte counts for multipart children while the
  /// body still lives in Apple's temporary file. Dart cannot stat that file,
  /// which is why polling only `0.part`/`1.part` updated in whole-part jumps.
  private static func postMultipartChunkUpdate(
    _ task: URLSessionTask,
    totalWritten: Int64,
    totalExpected: Int64,
    completed: Bool
  ) {
    guard isDownloadPart(task),
          let childId = taskId(from: task),
          let parentId = parentTaskId(from: task)
    else {
      return
    }

    let now = CFAbsoluteTimeGetCurrent()
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

    var values: [String: Any] = [
      "parentTaskId": parentId,
      "chunkTaskId": childId,
      "completed": completed,
    ]
    if totalWritten >= 0 {
      values["writtenBytes"] = totalWritten
    }
    if totalExpected > 0 {
      values["expectedBytes"] = totalExpected
      values["progress"] = completed
        ? 1.0
        : min(max(Double(totalWritten) / Double(totalExpected), 0), 1)
    } else if completed {
      values["progress"] = 1.0
    }
    if speed > 0 {
      values["speedBytesPerSecond"] = speed
    }

    NotificationCenter.default.post(
      name: Notification.Name("AnimeWitcherBackgroundDownloaderChunkUpdate"),
      object: nil,
      userInfo: values
    )
  }

'''
replace_once(
    swift,
    "  static func handleBytesWritten(\n",
    chunk_helpers + "  static func handleBytesWritten(\n",
)

replace_once(
    swift,
    '''  ) {
    guard !isDownloadPart(downloadTask) else { return }
    guard let id = taskId(from: downloadTask) else { return }
''',
    '''  ) {
    if isDownloadPart(downloadTask) {
      postMultipartChunkUpdate(
        downloadTask,
        totalWritten: totalWritten,
        totalExpected: totalExpected,
        completed: false
      )
      return
    }
    guard let id = taskId(from: downloadTask) else { return }
''',
)

replace_once(
    swift,
    '''    // A native part is not an episode. Dart owns its parent and only frees
    // that slot after all parts are safely assembled.
    guard !isDownloadPart(task) else { return }
''',
    '''    // A native part is not an episode, but its URLSession byte/completion
    // evidence belongs to the Dart multipart parent. didFinishDownloadingTo
    // calls us after the plugin moved the temp file, so completion can now be
    // verified against the exact `.part` path by PersistentParallelDownload.
    if isDownloadPart(task) {
      postMultipartChunkUpdate(
        task,
        totalWritten: task.countOfBytesReceived,
        totalExpected: task.countOfBytesExpectedToReceive,
        completed: error == nil
      )
      return
    }
''',
)

# Forward the richer native notification payload through AppDelegate.
replace_once(
    appdelegate,
    '''      if let status = values["status"] as? NSNumber {
        arguments["status"] = status.intValue
      }
      channel?.invokeMethod("chunkUpdate", arguments: arguments)
''',
    '''      if let status = values["status"] as? NSNumber {
        arguments["status"] = status.intValue
      }
      if let written = values["writtenBytes"] as? NSNumber {
        arguments["writtenBytes"] = written.int64Value
      }
      if let expected = values["expectedBytes"] as? NSNumber {
        arguments["expectedBytes"] = expected.int64Value
      }
      if let speed = values["speedBytesPerSecond"] as? NSNumber {
        arguments["speedBytesPerSecond"] = speed.doubleValue
      }
      if let completed = values["completed"] as? Bool {
        arguments["completed"] = completed
      }
      channel?.invokeMethod("chunkUpdate", arguments: arguments)
''',
)

# Functional regression tests: byte callbacks work before final files exist,
# and completion adopts the exact moved child without re-downloading it.
test_insert = r'''
  test(
    'native iOS byte bridge advances parent before final part file exists',
    () async {
      expect(await coordinator.start(parent, 100), isTrue);
      expect(starts.length, 1);
      final first = starts.single;

      await coordinator.handleNativeChunkUpdate(
        parentTaskId: parent.taskId,
        chunkTaskId: first.taskId,
        writtenBytes: 10,
        expectedBytes: 20,
        speedBytesPerSecond: 500000,
      );

      final parentRecord = records[parent.taskId]!;
      expect(parentRecord.status, TaskStatus.running);
      expect(parentRecord.progress, closeTo(.1, .001));
      expect(statuses, contains(TaskStatus.running));
      await waitUntil(() => starts.length >= 3);
    },
  );

  test(
    'native iOS completion bridge adopts the exact moved part',
    () async {
      expect(await coordinator.start(parent, 100), isTrue);
      final first = starts.single;
      final file = File(await first.filePath());
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(20, 4), flush: true);

      await coordinator.handleNativeChunkUpdate(
        parentTaskId: parent.taskId,
        chunkTaskId: first.taskId,
        writtenBytes: 20,
        expectedBytes: 20,
        completed: true,
      );

      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(coordinator.progressFor(parent.taskId), greaterThanOrEqualTo(.2));
      await waitUntil(() => starts.length >= 3);
    },
  );

'''
replace_once(
    ptest,
    "  test('repeated system pauses recover only the affected identity', () async {\n",
    test_insert + "  test('repeated system pauses recover only the affected identity', () async {\n",
)

source_test = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS native bridge forwards multipart URLSession bytes to Dart', () async {
    final swift = await File(
      'ios/Runner/DownloadNativeWaitingQueue.swift',
    ).readAsString();
    final appDelegate = await File('ios/Runner/AppDelegate.swift').readAsString();

    expect(swift, contains('postMultipartChunkUpdate('));
    expect(swift, contains('AnimeWitcherBackgroundDownloaderChunkUpdate'));
    expect(swift, contains('"writtenBytes"'));
    expect(swift, contains('"completed"'));
    expect(appDelegate, contains('arguments["writtenBytes"]'));
    expect(appDelegate, contains('arguments["completed"]'));
  });

  test('multipart child pause uses the FileDownloader owner', () async {
    final service = await File(
      'lib/core/services/download_service.dart',
    ).readAsString();

    expect(service, contains('isInternalDownloaderChunk(task)'));
    expect(service, contains('await FileDownloader().pause(task)'));
    expect(service, contains('Native multipart child did not pause'));
  });
}
'''
Path("test/core/services/ios_multipart_native_bridge_source_test.dart").write_text(source_test)

print("Applied iOS multipart native progress + pause fix")
