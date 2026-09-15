import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/services/download_continued_processing_service.dart';

const _channel = MethodChannel(
  'com.animewitcher.app/download_continued_processing',
);

Map<String, Object> _queueArgs() => <String, Object>{
  'maxConcurrent': 2,
  'waiters': <Map<String, Object>>[],
  'transferringTaskIds': <String>[],
  'pausedTaskIds': <String>[],
};

Future<int?> _persist(DownloadContinuedProcessingService service) {
  final args = _queueArgs();
  return service.persistNativeQueue(
    maxConcurrent: args['maxConcurrent']! as int,
    waiters: args['waiters']! as List<Map<String, Object>>,
    transferringTaskIds: args['transferringTaskIds']! as List<String>,
    pausedTaskIds: args['pausedTaskIds']! as List<String>,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('DM-26 unavailable hooks retain checkpoint acknowledgement and recover', () async {
    var available = false;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'persistNativeQueue') return null;
          calls++;
          return <String, Object>{
            'acceptedVersion': (call.arguments as Map)['snapshotVersion'] as int,
            'nativePromotionAvailable': available,
          };
        });
    final service = DownloadContinuedProcessingService(
      onSystemCancel: (_) async {},
      forceAvailableForTesting: true,
    );
    addTearDown(service.dispose);

    expect(await _persist(service), isNotNull);
    expect(service.nativePromotionAvailable, isFalse);
    expect(calls, 1, reason: 'unavailable capability is not a lost durable ACK');
    available = true;
    expect(await _persist(service), isNotNull);
    expect(service.nativePromotionAvailable, isTrue);
    expect(calls, 2);
  });

  test(
    'DM-15 retries a lost acknowledgement with the exact same version',
    () async {
      final seenVersions = <int>[];
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method != 'persistNativeQueue') return null;
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            final version = args['snapshotVersion']! as int;
            seenVersions.add(version);
            calls++;
            if (calls == 1) {
              throw PlatformException(code: 'ACK_LOST');
            }
            return <String, Object>{'acceptedVersion': version};
          });

      final service = DownloadContinuedProcessingService(
        onSystemCancel: (_) async {},
        forceAvailableForTesting: true,
      );
      addTearDown(service.dispose);

      final accepted = await _persist(service);

      expect(accepted, isNotNull);
      expect(seenVersions, hasLength(2));
      expect(seenVersions[1], seenVersions[0]);
    },
  );

  test(
    'DM-15 never upgrades a stale payload above native durable version',
    () async {
      final seenVersions = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method != 'persistNativeQueue') return null;
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            final version = args['snapshotVersion']! as int;
            seenVersions.add(version);
            return <String, Object>{'acceptedVersion': version + 100};
          });

      final service = DownloadContinuedProcessingService(
        onSystemCancel: (_) async {},
        forceAvailableForTesting: true,
      );
      addTearDown(service.dispose);

      final accepted = await _persist(service);

      expect(accepted, isNull);
      expect(seenVersions, hasLength(1));
    },
  );
}
