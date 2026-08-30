import 'dart:io';
import 'dart:ui' as ui;

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/services/download_service.dart';
import 'package:animewitcher/core/utils/download_cleanup.dart';
import 'package:animewitcher/features/library/presentation/downloads_provider.dart';
import 'package:animewitcher/features/library/presentation/widgets/downloads_tab.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../support/test_fonts.dart';

MultimediaItem _blackTorch() {
  return MultimediaItem(
    title: 'Black Torch',
    url: 'https://animewitcher.test/black-torch',
    posterUrl: '',
    contentType: MultimediaContentType.anime,
  );
}

Episode _episode9() {
  return Episode(
    name: 'الحلقة 9',
    url: 'https://animewitcher.test/black-torch/9',
    episode: 9,
    serverName: 'الحلقة 9',
  );
}

DownloadTask _task({
  required String taskId,
  required String filename,
  String directory = 'AnimeWitcher/Downloads/Black Torch',
  String metaData = 'https://animewitcher.test/black-torch/9',
}) {
  return DownloadTask(
    taskId: taskId,
    url: 'https://cdn.test/black-torch-9.mp4',
    filename: filename,
    directory: directory,
    metaData: metaData,
  );
}

DownloadItem _item({
  required String taskId,
  required int timestamp,
  String filename = 'الحلقة 9.mp4',
  TaskStatus status = TaskStatus.complete,
  String metaData = 'https://animewitcher.test/black-torch/9',
}) {
  return DownloadItem(
    task: _task(taskId: taskId, filename: filename, metaData: metaData),
    status: status,
    progress: status == TaskStatus.complete ? 1.0 : 0.4,
    item: _blackTorch(),
    episode: _episode9(),
    timestamp: timestamp,
  );
}

class _StubDownloadsNotifier extends DownloadsNotifier {
  _StubDownloadsNotifier(this._items);

  final List<DownloadItem> _items;

  @override
  Future<List<DownloadItem>> build() async => _items;
}

Widget _downloadsApp(List<DownloadItem> items) {
  return ProviderScope(
    overrides: [
      downloadsProvider.overrideWith(() => _StubDownloadsNotifier(items)),
    ],
    child: const MaterialApp(
      locale: Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DownloadsTab()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delete uses the task file path, not reconstructed labels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('aw_dl_path_');
      addTearDown(() => root.delete(recursive: true));

      final series = Directory(
        p.join(root.path, 'AnimeWitcher', 'Downloads', 'Black Torch'),
      );
      final season = Directory(p.join(series.path, 'Season 1'));
      await season.create(recursive: true);

      final taskFile = File(p.join(season.path, 'الحلقة 9 (1080p).mp4'));
      await taskFile.writeAsBytes(List<int>.filled(32, 1));
      final reconstructed = File(p.join(series.path, 'الحلقة 9.mp4'));
      await reconstructed.writeAsBytes(List<int>.filled(32, 2));

      var usedTaskPath = false;
      var usedRawPath = false;
      var usedLabels = false;
      final resolved = await resolveDownloadFileToDelete(
        fromTask: () async {
          usedTaskPath = true;
          return taskFile;
        },
        taskFilePath: () async {
          usedRawPath = true;
          return reconstructed.path;
        },
        fromLabels: () async {
          usedLabels = true;
          return reconstructed;
        },
      );

      expect(resolved!.path, taskFile.path);
      expect(usedTaskPath, isTrue);
      expect(usedRawPath, isFalse);
      expect(usedLabels, isFalse);

      await deleteDownloadedVideo(resolved);

      expect(await taskFile.exists(), isFalse);
      expect(await reconstructed.exists(), isTrue);
      expect(await series.exists(), isTrue);
    });
  });

  testWidgets('resolve falls back to task.filePath then reconstructed labels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('aw_dl_resolve_');
      addTearDown(() => root.delete(recursive: true));
      final series = Directory(
        p.join(root.path, 'AnimeWitcher', 'Downloads', 'Black Torch'),
      );
      await series.create(recursive: true);
      final pathFile = File(p.join(series.path, 'الحلقة 9 (1080p).mp4'));
      await pathFile.writeAsBytes(List<int>.filled(8, 1));
      final reconstructed = File(p.join(series.path, 'الحلقة 9.mp4'));
      await reconstructed.writeAsBytes(List<int>.filled(8, 2));

      var usedLabels = false;
      final fromPath = await resolveDownloadFileToDelete(
        fromTask: () async => null,
        taskFilePath: () async => pathFile.path,
        fromLabels: () async {
          usedLabels = true;
          return reconstructed;
        },
      );
      expect(fromPath!.path, pathFile.path);
      expect(usedLabels, isFalse);

      final fromLabels = await resolveDownloadFileToDelete(
        fromTask: () async => null,
        taskFilePath: () async => null,
        fromLabels: () async => reconstructed,
      );
      expect(fromLabels!.path, reconstructed.path);
    });
  });

  testWidgets(
    'deleting the last episode removes the series folder leftover files and all',
    (tester) async {
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('aw_dl_folder_');
        addTearDown(() => root.delete(recursive: true));

        final downloadsRoot = Directory(
          p.join(root.path, 'AnimeWitcher', 'Downloads'),
        );
        final series = Directory(p.join(downloadsRoot.path, 'Black Torch'));
        final season = Directory(p.join(series.path, 'Season 1'));
        await season.create(recursive: true);

        final video = File(p.join(season.path, 'الحلقة 9.mp4'));
        await video.writeAsBytes(List<int>.filled(32, 1));
        await File(
          p.join(season.path, '${p.basename(video.path)}.part'),
        ).writeAsBytes([1]);
        await File(
          p.join(season.path, '${p.basename(video.path)}.tmp'),
        ).writeAsBytes([1]);
        await File(
          p.join(season.path, '${p.basename(video.path)}.download'),
        ).writeAsBytes([1]);
        await File(p.join(season.path, 'thumb.jpg')).writeAsBytes([1]);
        await Directory(p.join(series.path, 'Season 2')).create();

        final otherSeries = Directory(p.join(downloadsRoot.path, 'Bleach'));
        await otherSeries.create();
        final otherVideo = File(p.join(otherSeries.path, 'الحلقة 1.mp4'));
        await otherVideo.writeAsBytes(List<int>.filled(32, 3));

        await deleteDownloadedVideo(video);

        expect(await video.exists(), isFalse);
        expect(await series.exists(), isFalse);
        expect(await downloadsRoot.exists(), isTrue);
        expect(await otherSeries.exists(), isTrue);
        expect(await otherVideo.exists(), isTrue);
      });
    },
  );

  testWidgets('delete also removes sibling .part .tmp .download temps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('aw_dl_temps_');
      addTearDown(() => root.delete(recursive: true));
      final series = Directory(
        p.join(root.path, 'AnimeWitcher', 'Downloads', 'Keep Me'),
      );
      await series.create(recursive: true);
      final video = File(p.join(series.path, 'keep.mp4'));
      await video.writeAsBytes(List<int>.filled(32, 1));
      final other = File(p.join(series.path, 'other.mp4'));
      await other.writeAsBytes(List<int>.filled(32, 2));
      final part = File(p.join(series.path, 'keep.mp4.part'));
      final tmp = File(p.join(series.path, 'keep.mp4.tmp'));
      final download = File(p.join(series.path, 'keep.mp4.download'));
      await part.writeAsBytes([1]);
      await tmp.writeAsBytes([1]);
      await download.writeAsBytes([1]);

      await deleteDownloadedVideo(video);

      expect(await video.exists(), isFalse);
      expect(await part.exists(), isFalse);
      expect(await tmp.exists(), isFalse);
      expect(await download.exists(), isFalse);
      expect(await other.exists(), isTrue);
      expect(await series.exists(), isTrue);
    });
  });

  testWidgets(
    'two complete records for the same episode collapse to one UI row',
    (tester) async {
      final older = _item(taskId: 'old-complete', timestamp: 100);
      final newer = _item(taskId: 'new-complete', timestamp: 200);
      expect(older.task.taskId, isNot(newer.task.taskId));
      expect(downloadTrackingUrl(older.task), downloadTrackingUrl(newer.task));
      expect(downloadsPointAtSameTarget(older, newer), isTrue);
      expect(collapseDuplicateDownloads([older, newer]).visible, hasLength(1));
      expect(
        collapseDuplicateDownloads([older, newer]).visible.single.id,
        'new-complete',
      );
      expect(
        collapseDuplicateDownloads([older, newer]).extraCompleteRecords,
        hasLength(1),
      );
      expect(
        collapseDuplicateDownloads([
          older,
          newer,
        ]).extraCompleteRecords.single.id,
        'old-complete',
      );

      await tester.pumpWidget(_downloadsApp([older, newer]));
      await tester.pump();

      expect(find.text('الحلقة 9'), findsOneWidget);
      expect(find.text('Black Torch'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    },
  );

  test('canonical identity is task metaData / episode.url, not taskId', () {
    final a = _item(taskId: 'task-a', timestamp: 1);
    final b = _item(taskId: 'task-b', timestamp: 2);
    expect(
      downloadTrackingUrl(a.task),
      'https://animewitcher.test/black-torch/9',
    );
    expect(downloadIdentityKey(a.item, a.episode), a.episode!.url);
    expect(downloadsPointAtSameTarget(a, b), isTrue);

    final other = DownloadItem(
      task: _task(
        taskId: 'task-c',
        filename: 'الحلقة 10.mp4',
        metaData: 'https://animewitcher.test/black-torch/10',
      ),
      status: TaskStatus.complete,
      progress: 1.0,
      item: _blackTorch(),
      episode: Episode(
        name: 'الحلقة 10',
        url: 'https://animewitcher.test/black-torch/10',
        episode: 10,
        serverName: 'الحلقة 10',
      ),
      timestamp: 3,
    );
    expect(downloadsPointAtSameTarget(a, other), isFalse);
  });

  test('complete records skip cancel; in-progress records cancel', () {
    expect(shouldCancelDownload(TaskStatus.complete), isFalse);
    expect(shouldCancelDownload(TaskStatus.running), isTrue);
    expect(shouldCancelDownload(TaskStatus.enqueued), isTrue);
    expect(shouldCancelDownload(TaskStatus.paused), isTrue);
  });

  test('startDownload reuses a complete record when the file exists', () {
    expect(
      decideCompleteDownloadAction(hasCompleteRecord: true, fileExists: true),
      CompleteDownloadAction.reuse,
    );
    expect(
      decideCompleteDownloadAction(hasCompleteRecord: true, fileExists: false),
      CompleteDownloadAction.dropAndEnqueue,
    );
    expect(
      decideCompleteDownloadAction(hasCompleteRecord: false, fileExists: false),
      CompleteDownloadAction.enqueue,
    );
  });

  testWidgets('waiting overflow keeps في الانتظار without restyling the row', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );

    await tester.runAsync(TestFonts.loadWalkthroughFonts);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final running = DownloadItem(
      task: _task(
        taskId: 'ep3',
        filename: 'الحلقة 3.mp4',
        metaData: 'https://animewitcher.test/black-torch/3',
      ),
      status: TaskStatus.running,
      progress: 0.18,
      item: _blackTorch(),
      episode: Episode(
        name: 'الحلقة 3',
        url: 'https://animewitcher.test/black-torch/3',
        episode: 3,
        serverName: 'الحلقة 3',
      ),
      timestamp: 30,
    );
    final waiting = DownloadItem(
      task: _task(
        taskId: 'ep4',
        filename: 'الحلقة 4.mp4',
        metaData: 'https://animewitcher.test/black-torch/4',
      ),
      status: TaskStatus.enqueued,
      progress: 0,
      item: _blackTorch(),
      episode: Episode(
        name: 'الحلقة 4',
        url: 'https://animewitcher.test/black-torch/4',
        episode: 4,
        serverName: 'الحلقة 4',
      ),
      timestamp: 40,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadsProvider.overrideWith(
            () => _StubDownloadsNotifier([waiting, running]),
          ),
          downloadProgressProvider.overrideWithValue({
            running.task.metaData: DownloadProgressData(
              taskId: 'ep3',
              progress: 0.18,
              networkSpeed: 0.127,
              timeRemaining: const Duration(minutes: 39, seconds: 44),
              status: TaskStatus.running,
              totalSize: 365400000,
            ),
            waiting.task.metaData: DownloadProgressData(
              taskId: 'ep4',
              progress: 0,
              networkSpeed: 0,
              timeRemaining: Duration.zero,
              status: TaskStatus.enqueued,
              totalSize: 462200000,
            ),
          }),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'NotoSansArabic',
            scaffoldBackgroundColor: Colors.black,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFEEC60A),
              surface: Color(0xFF1A1A1A),
              onSurface: Color(0xFFE5E7EB),
            ),
          ),
          home: const Scaffold(
            body: RepaintBoundary(
              key: ValueKey('downloads-waiting-row'),
              child: DownloadsTab(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('جارٍ التنزيل...'), findsOneWidget);
    expect(find.text('في الانتظار...'), findsOneWidget);
    expect(find.text('قيد الانتظار'), findsNothing);
    expect(find.text('متوقف مؤقتاً'), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    final artifacts = Directory('/opt/cursor/artifacts');
    if (!artifacts.existsSync()) return;

    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('downloads-waiting-row')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${artifacts.path}/downloads_waiting_in_app.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
