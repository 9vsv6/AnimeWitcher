import 'dart:io';

import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native iOS bytes produce parent speed before a part becomes durable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'parallel-ios-speed-',
      );
      final records = <String, TaskRecord>{};
      final starts = <DownloadTask>[];
      final parentProgress = <TaskProgressUpdate>[];
      final parent = ParallelDownloadTask(
        taskId: 'episode',
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
        livePartIds: () async => <String>{},
        onUpdate: (update) {
          if (update is TaskProgressUpdate && update.task.taskId == parent.taskId) {
            parentProgress.add(update);
          }
        },
        onPartProgress: (_, _, _) {},
      );

      try {
        expect(await coordinator.start(parent, 100), isTrue);
        expect(starts, hasLength(1));
        final first = starts.single;

        await coordinator.handleNativeChunkUpdate(
          parentTaskId: parent.taskId,
          chunkTaskId: first.taskId,
          writtenBytes: 5,
          expectedBytes: 20,
        );
        await Future<void>.delayed(
          kParallelProgressCoalesceDelay + const Duration(milliseconds: 150),
        );

        await coordinator.handleNativeChunkUpdate(
          parentTaskId: parent.taskId,
          chunkTaskId: first.taskId,
          writtenBytes: 10,
          expectedBytes: 20,
        );
        await Future<void>.delayed(
          kParallelProgressCoalesceDelay + const Duration(milliseconds: 150),
        );

        expect(parentProgress, isNotEmpty);
        expect(parentProgress.last.progress, closeTo(.10, .001));
        expect(
          parentProgress.last.networkSpeed,
          greaterThan(0),
          reason:
              'URLSession bytes are credible transfer telemetry even before '
              'the child temp body is promoted to a durable .part file',
        );
      } finally {
        await coordinator.dispose();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}
