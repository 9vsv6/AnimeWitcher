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

  test('start reports native rejection so caller can retry later', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') return false;
          return true;
        });
    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      forceAvailableForTesting: true,
    );

    try {
      expect(
        await service.start(taskId: 'episode', displayName: 'Episode 1'),
        isFalse,
      );
    } finally {
      await service.dispose();
    }
  });

  test('start reports native acceptance for an installed iOS task', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') {
            return 'com.animewitcher.app.download.session';
          }
          return true;
        });
    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      forceAvailableForTesting: true,
    );

    try {
      expect(
        await service.start(taskId: 'episode', displayName: 'Episode 1'),
        isTrue,
      );
    } finally {
      await service.dispose();
    }
  });

  test('native update rejection invalidates the cached iOS session', () async {
    var lost = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') {
            return 'com.animewitcher.app.download.session';
          }
          if (call.method == 'update') return false;
          return true;
        });
    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      onSessionLost: () => lost++,
      forceAvailableForTesting: true,
    );

    try {
      expect(
        await service.start(taskId: 'episode', displayName: 'Episode 1'),
        isTrue,
      );
      await service.update(
        taskId: 'episode',
        progress: .25,
        totalBytes: 100,
        transferredBytes: 25,
      );
      expect(lost, 1);
    } finally {
      await service.dispose();
    }
  });
}
