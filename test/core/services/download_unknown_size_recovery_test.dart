import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late File file;
  late Dio dio;
  late String url;
  var rangeCapable = true;
  var slowFirstBody = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aw-unknown-size-');
    file = File('${directory.path}/episode.part');
    await file.writeAsBytes(<int>[]);
    dio = Dio();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://${server.address.host}:${server.port}/episode';
    rangeCapable = true;
    slowFirstBody = false;

    unawaited(() async {
      await for (final request in server) {
        try {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (!rangeCapable || range == null) {
            request.response.statusCode = HttpStatus.ok;
            request.response.add(List<int>.generate(10, (i) => i));
            await request.response.close();
            continue;
          }
          final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
          final start = int.parse(match[1]!);
          final requestedEnd = match[2]!.isEmpty ? 9 : int.parse(match[2]!);
          final end = requestedEnd.clamp(start, 9);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/10',
          );
          request.response.headers.set(HttpHeaders.etagHeader, '"unknown-v1"');
          // Intentionally do not set Content-Length: HttpServer will stream the
          // body chunked while Content-Range discovers the resource total.
          if (slowFirstBody && start == 0 && end == 9) {
            request.response.add(<int>[0, 1, 2, 3]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 250));
            request.response.add(<int>[4, 5, 6, 7, 8, 9]);
          } else {
            request.response.add(
              List<int>.generate(end - start + 1, (i) => start + i),
            );
          }
          await request.response.close();
        } catch (_) {
          try {
            await request.response.close();
          } catch (_) {}
        }
      }
    }());
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'unknown total resumes from a verified prefix and discovers total',
    () async {
      await file.writeAsBytes(<int>[0, 1, 2]);
      final runner = DownloadRangeTransfer(dio);
      final complete = Completer<(int, int)>();

      expect(
        await runner.start(
          id: 'episode',
          url: url,
          headers: const {},
          file: file,
          existingBytes: 3,
          expectedBytes: -1,
          onState: (written, total, done) async {
            if (done && !complete.isCompleted)
              complete.complete((written, total));
          },
          onPaused: (_, _) async {},
        ),
        isTrue,
      );

      expect(await complete.future.timeout(const Duration(seconds: 5)), (
        10,
        10,
      ));
      expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
    },
  );

  test(
    'ignored Range never appends an unverified unknown-size prefix',
    () async {
      await file.writeAsBytes(<int>[0, 1, 2]);
      rangeCapable = false;
      final runner = DownloadRangeTransfer(dio);

      expect(
        await runner.start(
          id: 'episode',
          url: url,
          headers: const {},
          file: file,
          existingBytes: 3,
          expectedBytes: -1,
          onState: (_, _, _) async {},
          onPaused: (_, _) async {},
        ),
        isFalse,
      );
      expect(await file.readAsBytes(), <int>[0, 1, 2]);
    },
  );

  test(
    'same prefix can recover later when the origin starts honoring Range',
    () async {
      await file.writeAsBytes(<int>[0, 1, 2]);
      final runner = DownloadRangeTransfer(dio);
      rangeCapable = false;
      expect(
        await runner.start(
          id: 'episode',
          url: url,
          headers: const {},
          file: file,
          existingBytes: 3,
          expectedBytes: -1,
          onState: (_, _, _) async {},
          onPaused: (_, _) async {},
        ),
        isFalse,
      );

      rangeCapable = true;
      final complete = Completer<void>();
      expect(
        await runner.start(
          id: 'episode',
          url: url,
          headers: const {},
          file: file,
          existingBytes: 3,
          expectedBytes: -1,
          onState: (_, _, done) async {
            if (done && !complete.isCompleted) complete.complete();
          },
          onPaused: (_, _) async {},
        ),
        isTrue,
      );
      await complete.future.timeout(const Duration(seconds: 5));
      expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
    },
  );

  test(
    'process-style relaunch resumes only exact durable unknown-size bytes',
    () async {
      // Process death has no orderly callback to await. The only trustworthy
      // evidence after relaunch is the exact file length left on disk.
      await file.writeAsBytes(<int>[0, 1, 2, 3, 4]);
      final relaunched = DownloadRangeTransfer(dio);
      final complete = Completer<(int, int)>();

      expect(
        await relaunched.start(
          id: 'episode',
          url: url,
          headers: const {},
          file: file,
          existingBytes: 5,
          expectedBytes: -1,
          onState: (written, total, done) async {
            if (done && !complete.isCompleted)
              complete.complete((written, total));
          },
          onPaused: (_, _) async {},
        ),
        isTrue,
      );

      expect(await complete.future.timeout(const Duration(seconds: 5)), (
        10,
        10,
      ));
      expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
    },
  );
}
