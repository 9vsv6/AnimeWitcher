import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late File partial;
  late DownloadRangeTransfer runner;
  late Dio dio;
  late String url;
  late List<String?> ranges;
  var responseMode = 'normal';
  var requestCount = 0;

  setUp(() async {
    responseMode = 'normal';
    requestCount = 0;
    ranges = [];
    directory = await Directory.systemTemp.createTemp('range-recovery-');
    partial = File('${directory.path}/video.part');
    await partial.writeAsBytes([0, 1, 2]);
    dio = Dio();
    runner = DownloadRangeTransfer(dio);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/video';
    server.listen((request) async {
      requestCount++;
      final requestedRange = request.headers.value('range');
      ranges.add(requestedRange);
      final response = request.response;

      if (responseMode == 'retry-status' && requestCount == 1) {
        response.statusCode = 503;
        response.headers.set('retry-after', '0');
        await response.close();
        return;
      }

      final requestedStart = int.tryParse(
            RegExp(r'^bytes=(\d+)-').firstMatch(requestedRange ?? '')?[1] ?? '',
          ) ??
          3;
      response.statusCode = responseMode == 'ignored' ? 200 : 206;
      final responseStart = responseMode == 'wrong-start'
          ? requestedStart - 1
          : requestedStart;
      response.headers.set('content-range', 'bytes $responseStart-9/10');

      if (responseMode == 'stall') {
        response.add([requestedStart]);
        await response.flush();
        return;
      }

      if (responseMode == 'truncate-once' && requestCount == 1) {
        response.add([3, 4]);
        await response.close();
        return;
      }

      if (responseMode == 'truncated') {
        final end = (requestedStart + 1).clamp(requestedStart, 9);
        response.add(List<int>.generate(end - requestedStart + 1, (i) => requestedStart + i));
        await response.close();
        return;
      }

      response.add(List<int>.generate(10 - requestedStart, (i) => requestedStart + i));
      await response.close();
    });
  });

  tearDown(() async {
    await runner.stop('episode');
    runner.dispose();
    dio.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<bool> start(Completer<bool> finished) => runner.start(
    id: 'episode',
    url: url,
    headers: {},
    file: partial,
    existingBytes: 3,
    expectedBytes: 10,
    onState: (written, total, complete) async {
      if (complete && !finished.isCompleted) finished.complete(true);
    },
    onPaused: (written, total) async {
      if (!finished.isCompleted) finished.complete(false);
    },
  );

  test('appends exactly the requested remaining bytes', () async {
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=3-']);
    expect(await partial.readAsBytes(), List.generate(10, (i) => i));
  });

  test('retries a transient HTTP response before starting the writer', () async {
    responseMode = 'retry-status';
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=3-', 'bytes=3-']);
    expect(await partial.readAsBytes(), List.generate(10, (i) => i));
  });

  test('reconnects an interrupted body from the last durable byte', () async {
    responseMode = 'truncate-once';
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=3-', 'bytes=5-']);
    expect(await partial.readAsBytes(), List.generate(10, (i) => i));
  });

  for (final mode in ['ignored', 'wrong-start']) {
    test('rejects $mode Range without modifying the saved prefix', () async {
      responseMode = mode;
      expect(await start(Completer<bool>()), isFalse);
      expect(await partial.readAsBytes(), [0, 1, 2]);
      expect(runner.isActive('episode'), isFalse);
    });
  }

  test('bounded reconnects keep durable bytes when the body stays truncated', () async {
    responseMode = 'truncated';
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(
      await finished.future.timeout(const Duration(seconds: 5)),
      isFalse,
    );
    expect(ranges.length, 1 + kDownloadRangeReconnectAttempts);
    final bytes = await partial.readAsBytes();
    expect(bytes.take(3), [0, 1, 2]);
    expect(bytes.length, greaterThan(3));
    expect(bytes.length, lessThan(10));
  });

  test('stop cancels a stalled body and joins its writer promptly', () async {
    responseMode = 'stall';
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    await runner.stop('episode').timeout(const Duration(seconds: 2));
    expect(await finished.future, isFalse);
    expect(runner.isActive('episode'), isFalse);
    expect((await partial.readAsBytes()).take(3), [0, 1, 2]);
  });

  test('retry policy only includes temporary HTTP failures', () {
    for (final status in [408, 425, 429, 500, 502, 503, 504, 599]) {
      expect(isRetryableDownloadHttpStatus(status), isTrue, reason: '$status');
    }
    for (final status in [200, 206, 400, 401, 403, 404, 416]) {
      expect(isRetryableDownloadHttpStatus(status), isFalse, reason: '$status');
    }
  });
}
