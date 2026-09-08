import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late ParallelDownloadTask parent;
  late PersistentParallelDownload coordinator;
  late List<DownloadTask> starts;
  late List<String> pauses;
  late List<TaskStatus> parentStatuses;
  late Map<String, TaskRecord> records;

  Future<void> waitUntil(bool Function() predicate) async {
    for (var i = 0; i < 400; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for automatic multipart recovery');
  }

  PersistentParallelDownload buildCoordinator({
    Duration recoveryDelay = const Duration(milliseconds: 10),
    int maxActiveConnections = 16,
  }) {
    return PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        return true;
      },
      pausePart: (task) async {
        pauses.add(task.taskId);
      },
      cancelParts: (_) async {},
      saveRecord: (record) async {
        records[record.task.taskId] = record;
      },
      recordForId: (id) async => records[id],
      onUpdate: (update) {
        if (update is TaskStatusUpdate && update.task.taskId == parent.taskId) {
          parentStatuses.add(update.status);
        }
      },
      onPartProgress: (_, _, _) {},
      livePartIds: () async => <String>{},
      recoveryDelay: recoveryDelay,
      maxActiveConnections: maxActiveConnections,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('parallel-auto-recovery-');
    parent = ParallelDownloadTask(
      taskId: 'episode',
      url: 'https://cdn.example.test/video.mp4',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 1,
      allowPause: true,
    );
    starts = <DownloadTask>[];
    pauses = <String>[];
    parentStatuses = <TaskStatus>[];
    records = <String, TaskRecord>{};
    coordinator = buildCoordinator();
  });

  tearDown(() async {
    await coordinator.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('multipart child uses only AnimeWitcher recovery, not native retries', () async {
    expect(await coordinator.start(parent, 32), isTrue);
    expect(starts, hasLength(1));
    expect(starts.single.retries, 0);
  });

  test('repeated system pauses recover the child without pausing the episode', () async {
    expect(await coordinator.start(parent, 32), isTrue);
    expect(starts, hasLength(1));
    final child = starts.first;

    coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.running));
    await Future<void>.delayed(Duration.zero);

    // The old implementation stopped the whole parent after the third pause.
    // Exercise well beyond that boundary and require the same child identity
    // to keep recovering automatically.
    for (var interruption = 0; interruption < 6; interruption++) {
      final expectedStarts = starts.length + 1;
      coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.paused));
      await waitUntil(() => starts.length >= expectedStarts);
      expect(starts.last.taskId, child.taskId);
      expect(coordinator.isActive(parent.taskId), isTrue);
      expect(parentStatuses.last, TaskStatus.running);
      expect(pauses, isEmpty);
    }

    expect(parentStatuses, isNot(contains(TaskStatus.waitingToRetry)));
    expect(parentStatuses, isNot(contains(TaskStatus.paused)));
  });

  test('transient connection failure retries only the affected child', () async {
    expect(await coordinator.start(parent, 32), isTrue);
    final child = starts.first;
    coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.running));
    await Future<void>.delayed(Duration.zero);

    coordinator.handleUpdate(
      TaskStatusUpdate(
        child,
        TaskStatus.failed,
        TaskConnectionException('socket reset'),
      ),
    );

    await waitUntil(() => starts.length >= 2);
    expect(starts.last.taskId, child.taskId);
    expect(coordinator.isActive(parent.taskId), isTrue);
    expect(parentStatuses.last, TaskStatus.running);
    expect(parentStatuses, isNot(contains(TaskStatus.waitingToRetry)));
    expect(parentStatuses, isNot(contains(TaskStatus.paused)));
    expect(pauses, isEmpty);
  });

  test('recovery backoff frees its slot and never bypasses the governor', () async {
    await coordinator.dispose();
    starts.clear();
    pauses.clear();
    parentStatuses.clear();
    records.clear();
    parent = ParallelDownloadTask(
      taskId: 'episode-two-connections',
      url: 'https://cdn.example.test/video-2.mp4',
      filename: 'video-2.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 2,
      allowPause: true,
    );
    coordinator = buildCoordinator(
      recoveryDelay: const Duration(milliseconds: 80),
      maxActiveConnections: 2,
    );

    const mib = 1024 * 1024;
    expect(await coordinator.start(parent, 2 * mib), isTrue);
    final first = starts.first;
    coordinator.handleUpdate(TaskStatusUpdate(first, TaskStatus.running));
    await waitUntil(() => starts.length == 2);
    final interrupted = starts[1];
    coordinator.handleUpdate(
      TaskStatusUpdate(interrupted, TaskStatus.running),
    );
    await waitUntil(() => coordinator.activeConnectionCount == 2);

    // A system interruption used to leave this child counted as an active
    // socket throughout backoff. That eventually parked every connection at
    // once. The slot must be released and immediately used by spare tail work.
    coordinator.handleUpdate(
      TaskStatusUpdate(interrupted, TaskStatus.paused),
    );
    await waitUntil(() => starts.length == 3);
    expect(starts[2].taskId, isNot(interrupted.taskId));
    expect(coordinator.activeConnectionCount, 2);
    expect(parentStatuses.last, TaskStatus.running);

    // When the interrupted range's timer expires, it must not call startPart
    // directly on top of the two active workers. It waits for the governor to
    // expose a real slot instead.
    final startsWhileFull = starts.length;
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(starts, hasLength(startsWhileFull));
    expect(coordinator.activeConnectionCount, 2);
    expect(parentStatuses, isNot(contains(TaskStatus.waitingToRetry)));
    expect(parentStatuses, isNot(contains(TaskStatus.paused)));
  });

  test('missing native worker during reconcile is recovered, not auto-paused', () async {
    expect(await coordinator.start(parent, 32), isTrue);
    final child = starts.first;
    coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.running));
    await Future<void>.delayed(Duration.zero);

    await coordinator.reconcile(() async => <String>{});

    await waitUntil(() => starts.length >= 2);
    expect(starts.last.taskId, child.taskId);
    expect(coordinator.isActive(parent.taskId), isTrue);
    expect(parentStatuses.last, TaskStatus.running);
    expect(parentStatuses, isNot(contains(TaskStatus.waitingToRetry)));
    expect(parentStatuses, isNot(contains(TaskStatus.paused)));
  });

  test('permanent HTTP 403 still parks safely instead of retrying forever', () async {
    expect(await coordinator.start(parent, 32), isTrue);
    final child = starts.first;
    coordinator.handleUpdate(TaskStatusUpdate(child, TaskStatus.running));
    await Future<void>.delayed(Duration.zero);

    coordinator.handleUpdate(
      TaskStatusUpdate(
        child,
        TaskStatus.failed,
        TaskHttpException('forbidden', 403),
      ),
    );

    await waitUntil(() => parentStatuses.contains(TaskStatus.paused));
    expect(coordinator.isActive(parent.taskId), isFalse);
    expect(starts, hasLength(1));
    expect(pauses, contains(child.taskId));
  });
}
