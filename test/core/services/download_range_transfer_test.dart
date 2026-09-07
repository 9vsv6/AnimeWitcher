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

  setUp(() async {
    responseMode = 'normal';
    ranges = [];
    directory = await Directory.systemTemp.createTemp('range-recovery-');
    partial = File('${directory.path}/video.part');
    await partial.writeAsBytes([0, 1, 2]);
    dio = Dio();
    runner = DownloadRangeTransfer(dio);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/video';
    server.listen((request) async {
      ranges.add(request.headers.value('range'));
      final response = request.response;
      response.statusCode = responseMode == 'ignored' ? 200 : 206;
      response.headers.set(
        'content-range',
        responseMode == 'wrong-start' ? 'bytes 2-9/10' : 'bytes 3-9/10',
      );
      if (responseMode == 'stall') {
        response.add([3]);
        await response.flush();
        return;
      }
      response.add(
        responseMode == 'truncated' ? [3, 4] : [3, 4, 5, 6, 7, 8, 9],
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

  test('appends exactly the requested remaining bytes', () async {
    final finished = Completer<bool>();
    expect(await start(finished), isTrue);
    expect(await finished.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(ranges, ['bytes=3-']);
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

  test(
    'truncated response stays paused with bytes available for next resume',
    () async {
      responseMode = 'truncated';
      final finished = Completer<bool>();
      expect(await start(finished), isTrue);
      expect(
        await finished.future.timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(await partial.readAsBytes(), [0, 1, 2, 3, 4]);
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
}
