import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/services/download_parallel.dart';
import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late ParallelDownloadTask parent;
  late List<DownloadTask> starts;
  late List<double> startProgresses;
  late List<double> chunkProgresses;
  late Map<String, TaskRecord> records;
  late PersistentParallelDownload coordinator;

  Future<void> waitUntil(bool Function() predicate) async {
    for (var i = 0; i < 500; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for multipart progress');
  }

  PersistentParallelDownload buildCoordinator({
    Duration recoveryDelay = const Duration(milliseconds: 10),
  }) {
    return PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        startProgresses.add(progress);
        return true;
      },
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (record) async {
        records[record.task.taskId] = record;
      },
      recordForId: (id) async => records[id],
      onUpdate: (_) {},
      onPartProgress: (_, __, progress) {
        chunkProgresses.add(progress);
      },
      livePartIds: () async => <String>{},
      recoveryDelay: recoveryDelay,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('parallel-phantom-progress-');
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
    startProgresses = <double>[];
    chunkProgresses = <double>[];
    records = <String, TaskRecord>{};
    coordinator = buildCoordinator();
  });

  tearDown(() async {
    await coordinator.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('native 0.999 sentinel never adds phantom bytes across recovery', () async {
    expect(await coordinator.start(parent, 100), isTrue);
    expect(starts, hasLength(1));
    final child = starts.single;
    var current = child;

    coordinator.handleUpdate(
      TaskProgressUpdate(
        current,
        0.60,
        100,
        1,
        const Duration(seconds: 1),
      ),
    );
    await waitUntil(
      () => (records[parent.taskId]?.progress ?? 0) >= 0.599,
    );
    expect(records[parent.taskId]!.progress, closeTo(0.60, 0.0001));

    // background_downloader uses 0.999 as an end-of-transfer sentinel while
    // the final status is still pending. There is deliberately no child file,
    // so this is not proof that another 39.9 bytes exist.
    coordinator.handleUpdate(
      TaskProgressUpdate(
        current,
        0.999,
        100,
        0,
        const Duration(seconds: -1),
      ),
    );
    await Future<void>.delayed(kParallelProgressCoalesceDelay * 2);

    expect(records[parent.taskId]!.progress, closeTo(0.60, 0.0001));
    expect(chunkProgresses.last, closeTo(0.60, 0.0001));

    // Reproduce the user's stop/restart cycle. The raw 0.999 remains useful as
    // a resume hint, but restarting the child must not credit a whole Range.
    coordinator.handleUpdate(TaskStatusUpdate(current, TaskStatus.paused));
    await waitUntil(() => starts.length >= 2);
    current = starts.last;
    expect(current.taskId, child.taskId);
    expect(startProgresses.last, closeTo(0.999, 0.0001));
    expect(records[parent.taskId]!.progress, closeTo(0.60, 0.0001));

    // The recovered enqueue owns a new attempt token. Native progress from the
    // original task object is intentionally stale and fenced out, so continue
    // the scenario with the task instance that the coordinator just launched.
    coordinator.handleUpdate(TaskStatusUpdate(current, TaskStatus.running));
    await Future<void>.delayed(Duration.zero);
    coordinator.handleUpdate(
      TaskProgressUpdate(
        current,
        0.62,
        100,
        1,
        const Duration(seconds: 1),
      ),
    );
    await waitUntil(
      () => (records[parent.taskId]?.progress ?? 0) >= 0.619,
    );
    expect(records[parent.taskId]!.progress, closeTo(0.62, 0.0001));

    coordinator.handleUpdate(
      TaskProgressUpdate(
        current,
        0.999,
        100,
        0,
        const Duration(seconds: -1),
      ),
    );
    await Future<void>.delayed(kParallelProgressCoalesceDelay * 2);

    expect(records[parent.taskId]!.progress, closeTo(0.62, 0.0001));
    expect(chunkProgresses.last, closeTo(0.62, 0.0001));
  });

  test('legacy manifest drops three fake 0.999 ranges from parent progress', () async {
    await coordinator.dispose();
    starts.clear();
    startProgresses.clear();
    chunkProgresses.clear();
    records.clear();

    parent = ParallelDownloadTask(
      taskId: 'legacy-phantom',
      url: 'https://pixeldrain.example/file',
      filename: 'legacy.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 16,
      allowPause: true,
    );

    final targetPath = await parent.filePath();
    final partsDirectory = Directory('$targetPath.parts');
    await partsDirectory.create(recursive: true);
    final manifestParts = <Map<String, dynamic>>[];
    const normalProgress = <double>[
      0.7301098664481405,
      0.6188718456833693,
      0.6073949070330358,
      0.6120708844509606,
    ];

    for (var index = 0; index < 32; index++) {
      final from = index * 4;
      final to = from + 3;
      final child = DownloadTask(
        taskId: '${parent.taskId}.part.$index',
        url: parent.url,
        filename: '$index.part',
        directory: partsDirectory.path,
        baseDirectory: BaseDirectory.root,
        headers: <String, String>{
          'Range': 'bytes=$from-$to',
          'Accept-Encoding': 'identity',
        },
        updates: Updates.statusAndProgress,
        retries: 0,
        allowPause: true,
        group: kPersistentDownloadChunkGroup,
        metaData: jsonEncode(<String, String>{'parentTaskId': parent.taskId}),
      );
      final progress = index < normalProgress.length
          ? normalProgress[index]
          : (index >= 4 && index <= 6 ? 0.999 : 0.0);
      manifestParts.add(<String, dynamic>{
        'task': child.toJson(),
        'from': from,
        'to': to,
        'progress': progress,
        'complete': false,
      });
    }

    await File('$targetPath.parts/manifest.json').writeAsString(
      jsonEncode(<String, dynamic>{'parts': manifestParts}),
      flush: true,
    );

    final fakeAggregate =
        (normalProgress.fold<double>(0, (sum, value) => sum + value) +
            3 * 0.999) /
        32;
    final credibleAggregate =
        normalProgress.fold<double>(0, (sum, value) => sum + value) / 32;
    records[parent.taskId] = TaskRecord(
      parent,
      TaskStatus.paused,
      fakeAggregate,
      128,
    );

    coordinator = buildCoordinator();
    expect(await coordinator.restore(parent), isTrue);

    // The three sentinel ranges contribute zero unless real on-disk bytes are
    // available. This is the ~3 x 18.56 MB phantom jump from the uploaded
    // 593.9 MB / 32-range manifest, scaled down to four-byte test ranges.
    expect(
      records[parent.taskId]!.progress,
      closeTo(credibleAggregate, 0.0000001),
    );
    expect(records[parent.taskId]!.progress, lessThan(fakeAggregate));
    expect(
      coordinator.progressFor(parent.taskId),
      closeTo(credibleAggregate, 0.0000001),
    );

    final repaired = jsonDecode(
      await File('$targetPath.parts/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    final repairedParts = repaired['parts'] as List<dynamic>;
    for (var index = 4; index <= 6; index++) {
      final part = Map<String, dynamic>.from(repairedParts[index] as Map);
      expect(part['progress'], 0.999);
      expect(part['credibleProgress'], 0.0);
      expect(part['complete'], isFalse);
    }
  });
}
