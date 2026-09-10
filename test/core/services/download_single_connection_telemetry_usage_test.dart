import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS single downloads bridge URLSession bytes into Dart telemetry', () {
    final nativeQueue = File('ios/Runner/DownloadNativeWaitingQueue.swift')
        .readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final dartBridge = File(
      'lib/core/services/download_continued_processing_service.dart',
    ).readAsStringSync();
    final service = File('lib/core/services/download_service.dart')
        .readAsStringSync();

    expect(nativeQueue, contains('AnimeWitcherBackgroundDownloaderTaskUpdate'));
    expect(appDelegate, contains('invokeMethod("taskUpdate"'));
    expect(dartBridge, contains("call.method == 'taskUpdate'"));
    expect(service, contains('_handleNativeTaskUpdate'));
    expect(service, contains('DownloadTelemetryEstimator'));
  });

  test('metadata range probe preserves HEAD range evidence', () {
    final service = File('lib/core/services/download_service.dart')
        .readAsStringSync();
    expect(
      service,
      isNot(
        contains(
          '// A 206 response is stronger evidence than Accept-Ranges and also covers\n      // hosts that reject HEAD. Stream and cancel immediately so a bad server\n      // that ignores Range cannot buffer a whole episode into memory.\n      {\n        supportsRanges = false;',
        ),
      ),
    );
    expect(service, contains("'Accept-Encoding': 'identity'"));
  });
}
