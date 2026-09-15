import 'dart:io';

import 'package:animewitcher/core/utils/download_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('app download containment is segment-aware and traversal-safe', () {
    final root = p.join(
      Directory.systemTemp.path,
      'scope',
      'AnimeWitcher',
      'Downloads',
    );

    expect(pathIsInsideAppDownloads(p.join(root, 'Show', 'ep.mp4')), isTrue);
    expect(pathIsAppDownloadsRoot(root), isTrue);
    expect(
      pathIsInsideAppDownloads(
        p.join(
          Directory.systemTemp.path,
          'scope',
          'AnimeWitcher',
          'DownloadsBackup',
          'ep.mp4',
        ),
      ),
      isFalse,
    );
    expect(
      pathIsInsideAppDownloads(p.join(root, '..', 'Private', 'ep.mp4')),
      isFalse,
    );
  });

  test('series cleanup rejects an unconfigured lookalike app root', () async {
    final sandbox = await Directory.systemTemp.createTemp('aw-cleanup-root-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    final unconfiguredSeries = Directory(
      p.join(
        sandbox.path,
        'unconfigured',
        'AnimeWitcher',
        'Downloads',
        'Show',
      ),
    );
    await unconfiguredSeries.create(recursive: true);

    await deleteSeriesFolderIfNoVideosRemain(
      File(p.join(unconfiguredSeries.path, 'episode 01.mp4')),
    );

    expect(
      await unconfiguredSeries.exists(),
      isTrue,
      reason:
          'a matching AnimeWitcher/Downloads suffix is not proof that this is '
          'one of the configured app-owned roots',
    );
  });

  test('series cleanup never recursively deletes unknown user content', () async {
    final sandbox = await Directory.systemTemp.createTemp('aw-cleanup-safety-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final series = Directory(
      p.join(sandbox.path, 'AnimeWitcher', 'Downloads', 'Show'),
    );
    await series.create(recursive: true);
    final unknown = File(p.join(series.path, 'notes.txt'));
    await unknown.writeAsString('keep me');

    final deletedEpisode = File(
      p.join(series.path, 'Season 1', 'episode 01.mp4'),
    );
    await deleteSeriesFolderIfNoVideosRemain(deletedEpisode);

    expect(await unknown.exists(), isTrue);
    expect(await series.exists(), isTrue);
  });

  test(
    'series cleanup preserves recoverable partial and assembling evidence',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('aw-cleanup-owned-');
      addTearDown(() async {
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });
      final series = Directory(
        p.join(sandbox.path, 'AnimeWitcher', 'Downloads', 'Show'),
      );
      final season = Directory(p.join(series.path, 'Season 1'));
      await season.create(recursive: true);
      final partial = File(p.join(season.path, 'episode 01.mp4.part'));
      final assembling = File(p.join(season.path, 'episode 01.mp4.assembling'));
      final manifest = File(p.join(season.path, 'manifest.json.tmp'));
      await partial.writeAsBytes([1, 2, 3]);
      await assembling.writeAsBytes([4, 5, 6]);
      await manifest.writeAsString('{}');

      await deleteSeriesFolderIfNoVideosRemain(
        File(p.join(season.path, 'episode 01.mp4')),
      );

      expect(await partial.exists(), isTrue);
      expect(await assembling.exists(), isTrue);
      expect(await manifest.exists(), isTrue);
      expect(await series.exists(), isTrue);
    },
  );

  test('extensionless media-looking content is not treated as temp', () async {
    final sandbox = await Directory.systemTemp.createTemp('aw-cleanup-plain-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final series = Directory(
      p.join(sandbox.path, 'AnimeWitcher', 'Downloads', 'Show'),
    );
    await series.create(recursive: true);
    final extensionless = File(p.join(series.path, 'episode-final'));
    await extensionless.writeAsBytes([1, 2, 3, 4]);

    await deleteSeriesFolderIfNoVideosRemain(
      File(p.join(series.path, 'episode 01.mp4')),
    );

    expect(await extensionless.exists(), isTrue);
    expect(await series.exists(), isTrue);
  });

  test('series cleanup does not traverse a symlink escape', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp('aw-cleanup-link-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final downloads = Directory(
      p.join(sandbox.path, 'AnimeWitcher', 'Downloads'),
    );
    await downloads.create(recursive: true);
    final outside = Directory(p.join(sandbox.path, 'outside'));
    await outside.create();
    final unknown = File(p.join(outside.path, 'notes.txt'));
    await unknown.writeAsString('outside');
    final link = Link(p.join(downloads.path, 'Show'));
    await link.create(outside.path);

    await deleteSeriesFolderIfNoVideosRemain(
      File(p.join(link.path, 'Season 1', 'episode 01.mp4')),
    );

    expect(await link.exists(), isTrue);
    expect(await unknown.exists(), isTrue);
  });
}
