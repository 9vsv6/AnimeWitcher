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
  late List<String?> ifRanges;
  var responseMode = 'normal';
  var requestCount = 0;
  var transferAttempts = 0;

  setUp(() async {
    responseMode = 'normal';
    requestCount = 0;
    transferAttempts = 0;
    ranges = [];
    ifRanges = [];
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
      final ifRange = request.headers.value('if-range');
      ranges.add(requestedRange);
      ifRanges.add(ifRange);
      final response = request.response;

      final bounded = RegExp(r'^bytes=(\d+)-(\d+)$')
          .firstMatch(requestedRange ?? '');
      final openEnded = RegExp(r'^bytes=(\d+)-$')
          .firstMatch(requestedRange ?? '');
      final requestedStart =
          int.tryParse(bounded?[1] ?? openEnded?[1] ?? '') ?? 3;
      final requestedEnd = int.tryParse(bounded?[2] ?? '') ?? 9;
      final isProbe =
          bounded != null && requestedStart == 0 && requestedEnd == 2;

      if (isProbe) {
        response.statusCode = 206;
        response.headers.set('content-range', 'bytes 0-2/10');
        response.headers.set('etag', '"v1"');
        if (responseMode == 'prefix-mismatch') {
          response.add([9, 9, 9]);
        } else {
          response.add([0, 1, 2]);
        }
        await response.close();
        return;
      }

      transferAttempts++;
      if (responseMode == 'long-backoff' ||
          (responseMode == 'reconnect-retry' && transferAttempts == 2)) {
        response.statusCode = 503;
        response.headers.set(
          'retry-after',
          responseMode == 'long-backoff' ? '30' : '0',
        );
        await response.close();
        return;
      }
      if (responseMode == 'retry-status' && transferAttempts == 1) {
        response.statusCode = 503;
        response.headers.set('retry-after', '0');
        await response.close();
        return;
      }

      if (responseMode == 'changed-resource') {
        response.statusCode = 200;
        response.headers.set('etag', '"v2"');
        response.add(List<int>.generate(10, (i) => 50 + i));
        await response.close();
        return;
      }

      response.statusCode = responseMode == 'ignored' ? 200 : 206;
      final responseStart = responseMode == 'wrong-start'
          ? requestedStart - 1
          : requestedStart;
      response.headers.set(
        'content-range',
        'bytes $responseStart-$requestedEnd/10',
      );
      response.headers.set(
        'etag',
        responseMode == 'changed-etag-206' ? '"v2"' : '"v1"',
      );

      if (responseMode == 'stall') {
        response.add([requestedStart]);
        await response.flush();
        return;
      }

      if ((responseMode == 'truncate-once' ||
              responseMode == 'reconnect-retry') &&
          transferAttempts == 1) {
        response.add([3, 4]);
        await response.close();
        return;
      }

      if (responseMode == 'truncated') {
        final end = (requestedStart + 1).clamp(requestedStart, requestedEnd);
        response.add(
          List<int>.generate(
            end - requestedStart + 1,
            (i) => requestedStart + i,
          ),
        );
        await response.close();
        return;
      }

      response.add(
        List<int>.generate(
          requestedEnd - requestedStart + 1,
          (i) => requestedStart + i,
        ),
      );
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

  test('verifies prefix then appends with If-Range validator', () async {
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=0-2', 'bytes=3-']);
    expect(ifRanges, [null, '"v1"']);
    expect(await partial.readAsBytes(), List.generate(10, (i) => i));
  });

  test(
    'retries a transient HTTP response before starting the writer',
    () async {
      responseMode = 'retry-status';
      final finished = Completer<bool>();
      expect(await start(finished), isTrue);
      expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
      expect(ranges, ['bytes=0-2', 'bytes=3-', 'bytes=3-']);
      expect(ifRanges.skip(1), everyElement('"v1"'));
      expect(await partial.readAsBytes(), List.generate(10, (i) => i));
    },
  );

  test(
    'reconnects an interrupted body with the same If-Range validator',
    () async {
      responseMode = 'truncate-once';
      final finished = Completer<bool>();
      expect(await start(finished), isTrue);
      expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
      expect(ranges, ['bytes=0-2', 'bytes=3-', 'bytes=5-']);
      expect(ifRanges, [null, '"v1"', '"v1"']);
      expect(await partial.readAsBytes(), List.generate(10, (i) => i));
    },
  );

  test('a transient reconnect failure retries the durable offset', () async {
    responseMode = 'reconnect-retry';
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=0-2', 'bytes=3-', 'bytes=5-', 'bytes=5-']);
    expect(await partial.readAsBytes(), List.generate(10, (i) => i));
  });

  test('stop interrupts Retry-After while start is still pending', () async {
    responseMode = 'long-backoff';
    final starting = start(Completer<bool>());
    for (var i = 0; i < 200 && transferAttempts == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(transferAttempts, 1);
    await runner.stop('episode').timeout(const Duration(seconds: 2));
    expect(await starting, isFalse);
    expect(runner.isActive('episode'), isFalse);
    expect(await partial.readAsBytes(), [0, 1, 2]);
  });

  test('stop retains ownership until the final paused write settles', () async {
    responseMode = 'stall';
    final entered = Completer<void>();
    final release = Completer<void>();
    expect(
      await runner.start(
        id: 'episode',
        url: url,
        headers: {},
        file: partial,
        existingBytes: 3,
        expectedBytes: 10,
        onState: (_, _, _) async {},
        onPaused: (_, _) async {
          entered.complete();
          await release.future;
        },
      ),
      isTrue,
    );
    final stopping = runner.stop('episode');
    try {
      await entered.future.timeout(const Duration(seconds: 2));
      expect(runner.isActive('episode'), isTrue);
    } finally {
      release.complete();
      await stopping;
    }
    expect(runner.isActive('episode'), isFalse);
  });

  test(
    'refuses a changed resource before modifying the saved prefix',
    () async {
      responseMode = 'changed-resource';
      expect(await start(Completer<bool>()), isFalse);
      expect(ranges, ['bytes=0-2', 'bytes=3-']);
      expect(ifRanges.last, '"v1"');
      expect(await partial.readAsBytes(), [0, 1, 2]);
      expect(runner.isActive('episode'), isFalse);
    },
  );

  test('rejects a non-compliant 206 whose ETag changed', () async {
    responseMode = 'changed-etag-206';
    expect(await start(Completer<bool>()), isFalse);
    expect(ifRanges.last, '"v1"');
    expect(await partial.readAsBytes(), [0, 1, 2]);
  });

  test(
    'rejects a legacy partial whose saved prefix no longer matches',
    () async {
      responseMode = 'prefix-mismatch';
      expect(await start(Completer<bool>()), isFalse);
      expect(ranges, ['bytes=0-2']);
      expect(await partial.readAsBytes(), [0, 1, 2]);
    },
  );

  for (final mode in ['ignored', 'wrong-start']) {
    test('rejects $mode Range without modifying the saved prefix', () async {
      responseMode = mode;
      expect(await start(Completer<bool>()), isFalse);
      expect(await partial.readAsBytes(), [0, 1, 2]);
      expect(runner.isActive('episode'), isFalse);
    });
  }

  test(
    'bounded reconnects keep durable bytes when the body stays truncated',
    () async {
      responseMode = 'truncated';
      final finished = Completer<bool>();
      expect(await start(finished), isTrue);
      expect(
        await finished.future.timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(ranges.length, 2 + kDownloadRangeReconnectAttempts);
      expect(ifRanges.skip(1), everyElement('"v1"'));
      final bytes = await partial.readAsBytes();
      expect(bytes.take(3), [0, 1, 2]);
      expect(bytes.length, greaterThan(3));
      expect(bytes.length, lessThan(10));
    },
  );

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

  test('If-Range prefers strong ETag then Last-Modified', () {
    final strong = Headers.fromMap({
      'etag': ['"abc"'],
      'last-modified': ['Sun, 07 Sep 2026 12:00:00 GMT'],
    });
    expect(downloadIfRangeValidator(strong), '"abc"');

    final weak = Headers.fromMap({
      'etag': ['W/"abc"'],
      'last-modified': ['Sun, 07 Sep 2026 12:00:00 GMT'],
    });
    expect(downloadIfRangeValidator(weak), 'Sun, 07 Sep 2026 12:00:00 GMT');
  });
}
