import 'dart:async';
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

  PersistentParallelDownload create() => PersistentParallelDownload(
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
    onPartProgress: (_, __, ___) {},
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
    await directory.delete(recursive: true);
  });

  Future<void> completePart(DownloadTask task, List<int> bytes) async {
    final file = File(await task.filePath());
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    coordinator.handleUpdate(TaskStatusUpdate(task, TaskStatus.complete));
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
      final original = List<DownloadTask>.from(starts);
      await completePart(original.first, [0, 1, 2, 3, 4]);
      await coordinator.pause(
        parent,
      ); // drains the completion before persisting pause
      expect(pauses, isNot(contains(original.first.taskId)));
      starts.clear();
      coordinator = create(); // same durable directory, new process state
      expect(await coordinator.start(parent, 25), isTrue);
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
      expect(starts.length, 4);
    },
  );

  test(
    'merges out-of-order completions in byte order before marking complete',
    () async {
      await coordinator.start(parent, 25);
      final original = List<DownloadTask>.from(starts);
      for (var i = 4; i >= 0; i--) {
        await completePart(original[i], List.generate(5, (j) => i * 5 + j));
      }
      await Future.doWhile(() async {
        if (statuses.contains(TaskStatus.complete) &&
            !await File('${await parent.filePath()}.parts/manifest.json')
                .exists())
          return false;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return true;
      }).timeout(const Duration(seconds: 5));
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
}
