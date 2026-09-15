import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/services/persistent_parallel_download.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ParallelDownloadTask parent;
  late PersistentParallelDownload coordinator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('parallel-discovery-');
    parent = ParallelDownloadTask(
      taskId: 'manifest-discovery-parent',
      url: 'https://example.test/episode.mp4',
      filename: 'episode.mp4',
      directory: root.path,
      baseDirectory: BaseDirectory.root,
      chunks: 2,
      allowPause: true,
      metaData: 'https://animewitcher.test/episode/7',
    );
    coordinator = PersistentParallelDownload(
      startPart: (_, _, _) async => true,
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (_) async {},
      recordForId: (_) async => null,
      onUpdate: (_) {},
      onPartProgress: (_, _, _) {},
      livePartIds: () async => <String>{},
      diskProgressPollInterval: const Duration(seconds: 30),
    );
    expect(await coordinator.start(parent, 20), isTrue);
  });

  tearDown(() async {
    await coordinator.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> manifestFile() async =>
      File('${await parent.filePath()}.parts/manifest.json');

  test('discovers a v6 manifest as recoverable logical parent evidence', () async {
    final evidence = await discoverParallelManifestRecoveryEvidence(<Directory>[
      root,
    ]);

    expect(evidence, hasLength(1));
    final found = evidence.single;
    expect(found.schemaVersion, kParallelManifestSchemaVersion);
    expect(found.parentTaskId, parent.taskId);
    expect(found.parentTask, isNotNull);
    expect(found.parentTask!.taskId, parent.taskId);
    expect(found.parentTask!.metaData, parent.metaData);
    expect(found.expectedBytes, 20);
    expect(found.childTasks, hasLength(2));
  });

  test('recovery evidence exposes persisted generation provenance', () async {
    // Freeze the coordinator before editing the durable checkpoint so no
    // in-flight persist can replace this synthetic generation fixture.
    await coordinator.dispose();

    final manifest = await manifestFile();
    final snapshot =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    snapshot['generation'] = 7;
    await manifest.writeAsString(jsonEncode(snapshot), flush: true);

    final evidence = await discoverParallelManifestRecoveryEvidence(<Directory>[
      root,
    ]);

    expect(evidence, hasLength(1));
    expect(evidence.single.generation, 7);
  });

  test('rejects a manifest whose child path escapes its owned parts directory', () async {
    await coordinator.dispose();

    final manifest = await manifestFile();
    final snapshot =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final parts = snapshot['parts'] as List<dynamic>;
    final firstPart = Map<String, dynamic>.from(parts.first as Map);
    final firstTask = Map<String, dynamic>.from(firstPart['task'] as Map);
    // Keep the expected child taskId but point its file at a sibling directory.
    // A taskId prefix is identity evidence, not filesystem ownership proof.
    firstTask['directory'] = root.path;
    firstPart['task'] = firstTask;
    parts[0] = firstPart;
    snapshot['parts'] = parts;
    await manifest.writeAsString(jsonEncode(snapshot), flush: true);

    final evidence = await discoverParallelManifestRecoveryEvidence(<Directory>[
      root,
    ]);

    expect(evidence, isEmpty);
  });

  test('legacy manifest remains explicit unresolved evidence, not guessed parent', () async {
    // Freeze the coordinator before rewriting its durable checkpoint. Otherwise
    // an in-flight progress persist may legitimately replace this synthetic v5
    // fixture with a fresh v6 checkpoint while discovery is running.
    await coordinator.dispose();

    final manifest = await manifestFile();
    final temp = File('${manifest.path}.tmp');
    if (await temp.exists()) await temp.delete();
    final snapshot =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    snapshot['schemaVersion'] = 5;
    snapshot.remove('parentTask');
    await manifest.writeAsString(jsonEncode(snapshot), flush: true);

    final evidence = await discoverParallelManifestRecoveryEvidence(<Directory>[
      root,
    ]);

    expect(evidence, hasLength(1));
    final found = evidence.single;
    expect(found.schemaVersion, 5);
    expect(found.parentTaskId, parent.taskId);
    expect(found.parentTask, isNull);
    expect(found.childTasks, hasLength(2));
    expect(
      found.childTasks.every(
        (task) => task.taskId.startsWith('${parent.taskId}.part.'),
      ),
      isTrue,
    );
  });
}
