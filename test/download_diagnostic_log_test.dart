import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/services/download_diagnostic_log.dart';

void main() {
  late Directory directory;
  late DownloadDiagnosticLog log;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('download-log-test');
    log = DownloadDiagnosticLog(() async => Directory('${directory.path}/log'));
  });
  tearDown(() async {
    await log.configure(false);
    await directory.delete(recursive: true);
  });
  test('disabled by default; flushes ordered events and preserves files when disabled', () async {
    log.record('ignored');
    expect(await log.listFiles(), isEmpty);
    await log.configure(true);
    log.record('start', {'taskId': 'episode-1'});
    log.record('progress', {'bytes': 12, 'total': 100});
    await log.configure(false);
    log.record('ignored');
    final rows = (await (await log.listFiles()).single.readAsLines())
        .map((s) => jsonDecode(s) as Map)
        .toList();
    expect(rows.map((r) => r['event']), [
      'logging.enabled',
      'start',
      'progress',
      'logging.disabled',
    ]);
    expect(
      rows.map((r) => r['sequence']).toList(),
      orderedEquals([1, 2, 3, 4]),
    );
    expect(rows[2]['bytes'], 12);
  });
  test(
    'does not retain URLs, headers, exception messages or arbitrary fields',
    () async {
      await log.configure(true);
      log.record('error', {
        'url': 'https://user:secret@host/file?token=secret',
        'headers': 'Bearer secret',
        'message': 'secret',
        'errorType': 'DioException',
        'taskId': 'https://host/secret',
        'progress': double.nan,
      });
      await log.flush();
      final contents = await (await log.listFiles()).single.readAsString();
      expect(contents, isNot(contains('secret')));
      expect(contents, contains('DioException'));
    },
  );
  test(
    'rotates and retains the newest files including beyond ten rotations',
    () async {
      log = DownloadDiagnosticLog(
        () async => Directory('${directory.path}/log'),
        maxBytes: 220,
        maxFiles: 3,
      );
      await log.configure(true);
      for (var i = 0; i < 20; i++) {
        log.record('progress', {'bytes': i});
        await log.flush();
      }
      final files = await log.listFiles();
      expect(files.length, 3);
      expect(await files.first.readAsString(), contains('"bytes":19'));
    },
  );
  test(
    'disk errors do not escape; writer retries after storage is restored',
    () async {
      await log.configure(true);
      await log.flush();
      final folder = Directory('${directory.path}/log');
      await folder.delete(recursive: true);
      await File(folder.path).writeAsString('blocked');
      log.record('disk.error');
      await log.flush();
      expect(log.lastError, isNotNull);
      await File(folder.path).delete();
      log.record('recovered');
      await log.flush();
      expect(
        await (await log.listFiles()).single.readAsString(),
        contains('recovered'),
      );
    },
  );
  test('bounded queue reports dropped events', () async {
    log = DownloadDiagnosticLog(
      () async => Directory('${directory.path}/log'),
      maxPending: 1,
    );
    await log.configure(true);
    log.record('dropped');
    await log.flush();
    log.record('next');
    await log.flush();
    expect(
      await (await log.listFiles()).single.readAsString(),
      contains('"droppedEvents":1'),
    );
  });
}
