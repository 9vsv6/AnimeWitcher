import 'dart:convert';
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
  late List<String> pauses;
  late List<TaskStatus> statuses;
  late PersistentParallelDownload coordinator;
  var acceptStarts = true;

  PersistentParallelDownload create({int maxActiveConnections = 16}) =>
      PersistentParallelDownload(
        startPart: (task, progress, size) async {
          starts.add(task);
          return acceptStarts;
        },
        pausePart: (task) async {
          pauses.add(task.taskId);
        },
        cancelParts: (ids) async {},
        saveRecord: (record) async {
          records[record.task.taskId] = record;
        },
        recordForId: (id) async => records[id],
        onUpdate: (update) {
          if (update is TaskStatusUpdate) statuses.add(update.status);
        },
        onPartProgress: (_, _, _) {},
        maxActiveConnections: maxActiveConnections,
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('parallel-recovery-');
    parent = ParallelDownloadTask(
      taskId: 'episode',
      url: 'https://example.com/video',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 5,
      allowPause: true,
    );
    records = {};
    starts = [];
    pauses = [];
    statuses = [];
    acceptStarts = true;
    coordinator = create();
  });

  tearDown(() async {
    // Drain response-gated pump/update microtasks before deleting the durable
    // checkpoint directory. This mirrors a ProviderScope shutdown and catches
    // scheduler work that would otherwise escape after test completion.
    await coordinator.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> waitUntil(bool Function() predicate) async {
    for (var i = 0; i < 200; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for async connection controller');
  }

  Future<void> markRunning(Iterable<DownloadTask> tasks) async {
    for (final task in tasks) {
      coordinator.handleUpdate(TaskStatusUpdate(task, TaskStatus.running));
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> expandFreshTo(int target) async {
    final acknowledged = <String>{};
    while (starts.length < target) {
      final before = starts.length;
      final batch = starts
          .where((task) => acknowledged.add(task.taskId))
          .toList(growable: false);
      expect(batch, isNotEmpty);
      await markRunning(batch);
      await waitUntil(() => starts.length > before || starts.length >= target);
    }
  }

  Future<void> completePart(DownloadTask task, List<int> bytes) async {
    final file = File(await task.filePath());
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    coordinator.handleUpdate(TaskStatusUpdate(task, TaskStatus.complete));
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'five parts cover each byte once and failed zero-byte start can retry',
    () async {
      acceptStarts = false;
      expect(await coordinator.start(parent, 23), isFalse);
      expect(statuses.last, TaskStatus.paused);
      expect(
        await File('${await parent.filePath()}.parts/manifest.json').exists(),
        isTrue,
      );
      starts.clear();
      acceptStarts = true;
      expect(await coordinator.start(parent, 23), isTrue);
      await expandFreshTo(5);
      expect(starts.map((task) => task.headers['Range']), [
        'bytes=0-3',
        'bytes=4-8',
        'bytes=9-12',
        'bytes=13-17',
        'bytes=18-22',
      ]);
      expect(starts.map((task) => task.taskId).toSet().length, 5);
    },
  );

  test(
    'pause and process recreation retain a complete part and resume only four',
    () async {
      expect(await coordinator.start(parent, 25), isTrue);
      await expandFreshTo(5);
      final original = List<DownloadTask>.from(starts);
      await completePart(original.first, [0, 1, 2, 3, 4]);
      await coordinator.pause(parent);
      expect(pauses, isNot(contains(original.first.taskId)));
      starts.clear();
      await coordinator.dispose();
      coordinator = create();
      expect(await coordinator.start(parent, 25), isTrue);
      await expandFreshTo(4);
      expect(
        starts.map((task) => task.taskId),
        original.skip(1).map((task) => task.taskId),
      );
      expect(await File(await original.first.filePath()).readAsBytes(), [
        0,
        1,
        2,
        3,
        4,
      ]);
    },
  );

  test(
    'a failed part pauses siblings without deleting completed bytes',
    () async {
      await coordinator.start(parent, 25);
      await expandFreshTo(5);
      final original = List<DownloadTask>.from(starts);
      await completePart(original.first, [0, 1, 2, 3, 4]);
      coordinator.handleUpdate(
        TaskStatusUpdate(original[1], TaskStatus.failed),
      );
      await coordinator.pause(parent);
      expect(await File(await original.first.filePath()).exists(), isTrue);
      expect(records[parent.taskId]!.status, TaskStatus.paused);
      starts.clear();
      expect(await coordinator.start(parent, 25), isTrue);
      await expandFreshTo(4);
      expect(starts.length, 4);
    },
  );

  test(
    'merges out-of-order completions in byte order before marking complete',
    () async {
      await coordinator.start(parent, 25);
      await expandFreshTo(5);
      final original = List<DownloadTask>.from(starts);
      for (var i = 4; i >= 0; i--) {
        await completePart(original[i], List.generate(5, (j) => i * 5 + j));
      }
      await waitUntil(
        () => statuses.contains(TaskStatus.complete),
      );
      await waitUntil(
        () => !File('${directory.path}/video.mp4.parts/manifest.json').existsSync(),
      );
      expect(
        await File(await parent.filePath()).readAsBytes(),
        List.generate(25, (i) => i),
      );
      expect(records[parent.taskId]!.status, TaskStatus.complete);
    },
  );

  test('a truncated completed part never marks the episode complete', () async {
    await coordinator.start(parent, 25);
    await completePart(starts.first, [0, 1]);
    await coordinator.pause(parent);
    expect(statuses, isNot(contains(TaskStatus.complete)));
    expect(await File(await parent.filePath()).exists(), isFalse);
  });

  test(
    'legacy checkpoint keeps complete children instead of resuming them',
    () async {
      final child = DownloadTask(
        taskId: 'legacy.0',
        url: parent.url,
        filename: 'legacy.part',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
      );
      await File(await child.filePath()).writeAsBytes([1, 2, 3]);
      await coordinator.importLegacy(
        parent,
        jsonEncode([
          {
            'task': child.toJson(),
            'fromByte': 0,
            'toByte': 2,
            'progress': 1,
            'status': TaskStatus.complete.index,
          },
        ]),
      );
      expect(await coordinator.start(parent, 3), isTrue);
      expect(starts, isEmpty);
      expect(await File(await parent.filePath()).readAsBytes(), [1, 2, 3]);
    },
  );

  test('recovers a durable temp manifest left by process termination', () async {
    expect(await coordinator.start(parent, 25), isTrue);
    await coordinator.pause(parent);
    await coordinator.dispose();

    final manifest = File('${await parent.filePath()}.parts/manifest.json');
    final temp = File('${manifest.path}.tmp');
    expect(await manifest.exists(), isTrue);
    await manifest.rename(temp.path);

    starts.clear();
    coordinator = create();
    expect(await coordinator.start(parent, 25), isTrue);
    expect(await manifest.exists(), isTrue);
    expect(await temp.exists(), isFalse);
    expect(starts.length, 1);
  });

  test(
    'adopts an already assembled target after a crash without redownloading',
    () async {
      expect(await coordinator.start(parent, 25), isTrue);
      await coordinator.pause(parent);
      await coordinator.dispose();

      final target = File(await parent.filePath());
      await target.writeAsBytes(List<int>.generate(25, (i) => i), flush: true);

      starts.clear();
      statuses.clear();
      coordinator = create();
      expect(await coordinator.start(parent, 25), isTrue);
      expect(starts, isEmpty);
      expect(statuses, contains(TaskStatus.complete));
      expect(records[parent.taskId]!.status, TaskStatus.complete);
      expect(
        await File('${target.path}.parts/manifest.json').exists(),
        isFalse,
      );
    },
  );

  test('sixteen connections expand only after each batch is ready', () async {
    parent = ParallelDownloadTask(
      taskId: 'episode-16',
      url: 'https://example.com/video16',
      filename: 'video16.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 16,
      allowPause: true,
    );

    expect(await coordinator.start(parent, 160), isTrue);
    expect(starts.length, 1);

    await markRunning(starts.take(1));
    await waitUntil(() => starts.length == 3);
    await markRunning(starts.skip(1).take(2));
    await waitUntil(() => starts.length == 7);
    await markRunning(starts.skip(3).take(4));
    await waitUntil(() => starts.length == 15);
    await markRunning(starts.skip(7).take(8));
    await waitUntil(() => starts.length == 16);

    expect(coordinator.activeConnectionCount, 16);
    expect(
      starts.map((task) => task.headers['Range']).last,
      'bytes=150-159',
    );
  });

  test('global budget never hands more than sixteen children to native IO', () async {
    final first = ParallelDownloadTask(
      taskId: 'first-16',
      url: 'https://example.com/first',
      filename: 'first.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 16,
      allowPause: true,
    );
    final second = ParallelDownloadTask(
      taskId: 'second-16',
      url: 'https://example.com/second',
      filename: 'second.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 16,
      allowPause: true,
    );

    expect(await coordinator.start(first, 160), isTrue);
    await expandFreshTo(16);
    expect(coordinator.activeConnectionCount, 16);

    final beforeSecond = starts.length;
    expect(await coordinator.start(second, 160), isTrue);
    expect(starts.length, beforeSecond);
    expect(coordinator.activeConnectionCount, 16);

    final firstPart = starts.firstWhere(
      (task) => task.taskId.startsWith('first-16.part.'),
    );
    await completePart(firstPart, List<int>.generate(10, (i) => i));
    await waitUntil(
      () => starts.any((task) => task.taskId.startsWith('second-16.part.')),
    );
    expect(coordinator.activeConnectionCount, 16);
    expect(
      starts.where((task) => task.taskId.startsWith('second-16.part.')).length,
      1,
    );
  });

  test(
    '429 during slow start falls back to last healthy level and teaches host',
    () async {
      final pressured = ParallelDownloadTask(
        taskId: 'pressured-16',
        url: 'https://cdn.example.com/episode-a',
        filename: 'pressured.mp4',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
        chunks: 16,
        allowPause: true,
      );

      expect(await coordinator.start(pressured, 160), isTrue);
      expect(starts.length, 1);
      await markRunning(starts.take(1));
      await waitUntil(() => starts.length == 3);
      await markRunning(starts.skip(1).take(2));
      await waitUntil(() => starts.length == 7);

      final fourthBatch = starts.skip(3).take(4).toList(growable: false);
      coordinator.handleUpdate(
        TaskStatusUpdate(
          fourthBatch.first,
          TaskStatus.waitingToRetry,
          TaskHttpException('rate limited', 429),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await markRunning(fourthBatch);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The 1 + 2 batch was healthy (3 total). The failing 4-connection batch
      // may keep retrying, but it must not unlock the 8-connection expansion.
      expect(starts.length, 7);

      // Drain below the learned cap. Only one replacement should start to keep
      // exactly three connections active for this host.
      for (var i = 0; i < 5; i++) {
        await completePart(starts[i], List<int>.filled(10, i));
      }
      await waitUntil(() => starts.length == 8);
      expect(coordinator.activeConnectionCount, 3);

      final sibling = ParallelDownloadTask(
        taskId: 'sibling-16',
        url: 'https://cdn.example.com/episode-b',
        filename: 'sibling.mp4',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
        chunks: 16,
        allowPause: true,
      );
      final beforeSibling = starts.length;
      expect(await coordinator.start(sibling, 160), isTrue);
      await waitUntil(() => starts.length == beforeSibling + 1);
      await markRunning(starts.skip(beforeSibling).take(1));
      await waitUntil(() => starts.length == beforeSibling + 3);
      await markRunning(starts.skip(beforeSibling + 1).take(2));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Host memory prevents the sibling from trying 7/15/16 again.
      expect(
        starts.where((task) => task.taskId.startsWith('sibling-16.part.')).length,
        3,
      );
    },
  );
}
