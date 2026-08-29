import 'dart:io';

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/utils/download_cleanup.dart';
import 'package:animewitcher/features/library/presentation/downloads_provider.dart';
import 'package:animewitcher/features/library/presentation/widgets/downloads_tab.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
}) {
  return DownloadTask(
    taskId: taskId,
    url: 'https://cdn.test/black-torch-9.mp4',
    filename: filename,
    directory: directory,
    metaData: 'https://animewitcher.test/black-torch/9',
  );
}

DownloadItem _item({
  required String taskId,
  required int timestamp,
  String filename = 'الحلقة 9.mp4',
  TaskStatus status = TaskStatus.complete,
}) {
  return DownloadItem(
    task: _task(taskId: taskId, filename: filename),
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
      var usedLabels = false;
      final resolved = await resolveDownloadFileToDelete(
        fromTask: () async {
          usedTaskPath = true;
          return taskFile;
        },
        fromLabels: () async {
          usedLabels = true;
          return reconstructed;
        },
      );

      expect(resolved!.path, taskFile.path);
      expect(usedTaskPath, isTrue);
      expect(usedLabels, isFalse);

      await deleteDownloadedVideo(resolved);

      expect(await taskFile.exists(), isFalse);
      expect(await reconstructed.exists(), isTrue);
      expect(await series.exists(), isTrue);
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
        await File(p.join(season.path, 'thumb.jpg')).writeAsBytes([1]);
        await File(p.join(series.path, 'episode.part')).writeAsBytes([1]);
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

  testWidgets(
    'two complete records for the same episode collapse to one UI row',
    (tester) async {
      final older = _item(taskId: 'old-complete', timestamp: 100);
      final newer = _item(taskId: 'new-complete', timestamp: 200);
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
        collapseDuplicateDownloads([older, newer]).extraCompleteRecords.single.id,
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

  testWidgets('resolveDownloadFileToDelete falls back to reconstructed labels', (
    tester,
  ) async {
    final reconstructed = File(
      p.join(
        Directory.systemTemp.path,
        'AnimeWitcher',
        'Downloads',
        'Black Torch',
        'الحلقة 9.mp4',
      ),
    );
    final resolved = await resolveDownloadFileToDelete(
      fromTask: () async => null,
      fromLabels: () async => reconstructed,
    );
    expect(resolved!.path, reconstructed.path);
  });
}
