import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitUntil(bool Function() predicate) async {
    for (var i = 0; i < 200; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for multipart coordinator');
  }

  test(
    'native iOS live bytes drive aggregate speed before part finalization',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ios-speed-regression-',
      );
      final records = <String, TaskRecord>{};
      final starts = <DownloadTask>[];
      final updates = <TaskUpdate>[];
      final parent = ParallelDownloadTask(
        taskId: 'speed-parent',
        url: 'https://example.com/video',
        filename: 'video.mp4',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
        chunks: 5,
        allowPause: true,
      );
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
        onUpdate: updates.add,
        onPartProgress: (_, _, _) {},
        livePartIds: () async => <String>{},
        diskProgressPollInterval: const Duration(hours: 1),
      );

      try {
        expect(await coordinator.start(parent, 100), isTrue);
        expect(starts, hasLength(1));
        final first = starts.single;

        await coordinator.handleNativeChunkUpdate(
          parentTaskId: parent.taskId,
          chunkTaskId: first.taskId,
          writtenBytes: 10,
          expectedBytes: 20,
          speedBytesPerSecond: 500000,
        );

        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final aggregate = updates.whereType<TaskProgressUpdate>().last;
        expect(aggregate.progress, greaterThan(0));
        expect(
          aggregate.networkSpeed,
          greaterThan(0),
          reason: 'live URLSession bytes must not display 0 MB/s while progress advances',
        );
      } finally {
        await coordinator.dispose();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );

  test(
    'restored multipart owners that disappear are recovered without callbacks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ios-restart-regression-',
      );
      final records = <String, TaskRecord>{};
      final parent = ParallelDownloadTask(
        taskId: 'restart-parent',
        url: 'https://example.com/video',
        filename: 'video.mp4',
        directory: directory.path,
        baseDirectory: BaseDirectory.root,
        chunks: 5,
        allowPause: true,
      );
      var liveIds = <String>{};
      var starts = <DownloadTask>[];

      PersistentParallelDownload createCoordinator() =>
          PersistentParallelDownload(
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
            livePartIds: () async => liveIds,
            recoveryDelay: const Duration(milliseconds: 10),
            pendingStartLeaseDelay: const Duration(milliseconds: 20),
            diskProgressPollInterval: const Duration(hours: 1),
            maxActiveConnections: 5,
          );

      var coordinator = createCoordinator();
      try {
        expect(await coordinator.start(parent, 25), isTrue);
        final acknowledged = <String>{};
        while (starts.length < 5) {
          final before = starts.length;
          final batch = starts
              .where((task) => acknowledged.add(task.taskId))
              .toList(growable: false);
          expect(batch, isNotEmpty);
          for (final task in batch) {
            coordinator.handleUpdate(
              TaskStatusUpdate(task, TaskStatus.running),
            );
          }
          await waitUntil(() => starts.length > before || starts.length >= 5);
        }
        final finalBatch = starts
            .where((task) => acknowledged.add(task.taskId))
            .toList(growable: false);
        for (final task in finalBatch) {
          coordinator.handleUpdate(TaskStatusUpdate(task, TaskStatus.running));
        }
        await Future<void>.delayed(Duration.zero);

        final originalIds = starts.map((task) => task.taskId).toSet();
        liveIds = Set<String>.from(originalIds);
        await coordinator.dispose();

        starts = <DownloadTask>[];
        coordinator = createCoordinator();
        expect(await coordinator.start(parent, 25), isTrue);
        expect(
          starts,
          isEmpty,
          reason: 'the restored URLSession owners are initially adopted, not duplicated',
        );

        liveIds = <String>{};
        await waitUntil(() => starts.isNotEmpty);
        expect(
          originalIds,
          contains(starts.first.taskId),
          reason: 'once ownership disappears the same immutable child identity must resume',
        );
      } finally {
        await coordinator.dispose();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}
