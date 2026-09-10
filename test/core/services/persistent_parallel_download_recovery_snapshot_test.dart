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

  test(
    'manifest persists identity, generation, sequence, and attempt token',
    () async {
      expect(await coordinator.start(parent, 20), isTrue);
      expect(starts, hasLength(1));

      final manifest = await manifestFile();
      final json =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      expect(json['schemaVersion'], kParallelManifestSchemaVersion);
      expect(json['parentTaskId'], parent.taskId);
      expect(json['totalBytes'], 20);
      expect((json['generation'] as num).toInt(), greaterThanOrEqualTo(1));
      expect((json['checkpointSequence'] as num).toInt(), greaterThan(0));
      expect(
        ((json['parts'] as List).single as Map)['attemptGeneration'],
        attemptGeneration(starts.single),
      );
    },
  );

  test(
    'newer tmp checkpoint wins over an older valid primary manifest',
    () async {
      expect(await coordinator.start(parent, 20), isTrue);
      expect(await coordinator.pause(parent), isTrue);
      await coordinator.dispose();

      final manifest = await manifestFile();
      final primary =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final primaryPart =
          (primary['parts'] as List).single as Map<String, dynamic>;
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

      final promoted =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      expect(promoted['checkpointSequence'], 101);
      expect(await temp.exists(), isFalse);
    },
  );

  test('restore rejects a snapshot that belongs to another parent', () async {
    expect(await coordinator.start(parent, 20), isTrue);
    expect(await coordinator.pause(parent), isTrue);
    await coordinator.dispose();

    final manifest = await manifestFile();
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
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
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final parts = json['parts'] as List;
    final second = parts[1] as Map<String, dynamic>;
    second['from'] = (second['from'] as int) + 1;
    await manifest.writeAsString(jsonEncode(json), flush: true);

    coordinator = create();
    expect(await coordinator.restore(parent), isFalse);
  });

  test(
    'stale plugin running callback cannot cancel scheduled recovery',
    () async {
      expect(await coordinator.start(parent, 20), isTrue);
      final firstAttempt = starts.single;
      final firstGeneration = attemptGeneration(firstAttempt);

      coordinator.handleUpdate(
        TaskStatusUpdate(firstAttempt, TaskStatus.paused),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      coordinator.handleUpdate(
        TaskStatusUpdate(firstAttempt, TaskStatus.running),
      );

      await waitUntil(() => starts.length >= 2);
      final recovered = starts.last;
      expect(recovered.taskId, firstAttempt.taskId);
      expect(attemptGeneration(recovered), greaterThan(firstGeneration));
      expect(coordinator.isActive(parent.taskId), isTrue);
    },
  );

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
