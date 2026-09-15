import 'dart:io';

import 'package:animewitcher/core/services/download_continued_processing_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.animewitcher.app/download_continued_processing',
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOS runtime liveness returns only native URLSession task ids', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'liveNativeTaskIds') {
            return <String>['live-1', 'live-2'];
          }
          return null;
        });

    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      forceAvailableForTesting: true,
    );
    try {
      expect(await service.liveNativeTaskIds(), <String>{'live-1', 'live-2'});
    } finally {
      await service.dispose();
    }
  });

  test('unknown native URLSession returns null instead of proving absence', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      forceAvailableForTesting: true,
    );
    try {
      expect(await service.liveNativeTaskIds(), isNull);
    } finally {
      await service.dispose();
    }
  });

  test('DownloadService filters plugin paused rows through the iOS runtime oracle', () {
    final source = File('lib/core/services/download_service.dart').readAsStringSync();
    expect(source, contains('final nativeIds = await _continuedProcessing.liveNativeTaskIds();'));
    expect(source, contains('nativeIds.contains(task.taskId)'));
    expect(
      source,
      contains("throw StateError('iOS native runtime liveness unavailable')"),
      reason: 'unknown native ownership must fail closed instead of launching a second writer',
    );
  });

  test('iOS bridge exposes actual URLSession task ids independent of persisted rows', () {
    final waitingQueue = File('ios/Runner/DownloadNativeWaitingQueue.swift')
        .readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(waitingQueue, contains('static func liveTaskIds('));
    expect(waitingQueue, contains('session.getAllTasks { tasks in'));
    expect(appDelegate, contains('call.method == "liveNativeTaskIds"'));
    expect(appDelegate, contains('DownloadNativeWaitingQueue.liveTaskIds'));
  });
}
