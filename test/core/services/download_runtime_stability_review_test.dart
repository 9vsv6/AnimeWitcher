import 'dart:io';

import 'package:animewitcher/core/services/download_concurrency.dart';
import 'package:animewitcher/core/services/download_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runtime download stability review', () {
    test('sub-second callback bursts are not reported as download speed', () {
      final estimator = DownloadTelemetryEstimator();
      final start = DateTime(2026, 9, 9, 12);
      estimator.observe(
        taskId: 'episode',
        transferredBytes: 0,
        expectedBytes: 20 * 1000 * 1000,
        now: start,
      );
      final burst = estimator.observe(
        taskId: 'episode',
        transferredBytes: 2 * 1000 * 1000,
        expectedBytes: 20 * 1000 * 1000,
        now: start.add(const Duration(milliseconds: 200)),
      );
      expect(burst.speedBytesPerSecond, 0);

      final stable = estimator.observe(
        taskId: 'episode',
        transferredBytes: 4 * 1000 * 1000,
        expectedBytes: 20 * 1000 * 1000,
        now: start.add(const Duration(seconds: 2)),
      );
      expect(stable.speedBytesPerSecond, closeTo(2 * 1000 * 1000, 1));
    });

    test('engine ownership keeps a session alive through a DB/UI gap', () {
      expect(
        downloadSessionHasRemainingWork(
          runningCount: 0,
          waitingCount: 0,
          activeEngineCount: 1,
        ),
        isTrue,
      );
      expect(
        downloadSessionHasRemainingWork(
          runningCount: 0,
          waitingCount: 0,
          activeEngineCount: 0,
        ),
        isFalse,
      );
    });

    test('iOS system task uses rolling speed and does not finish on a gap', () {
      final swift = File('ios/Runner/DownloadNativeWaitingQueue.swift')
          .readAsStringSync();
      expect(swift, contains('speedWindowInterval: CFTimeInterval = 4.0'));
      expect(swift, contains('chunkBridgeInterval: CFTimeInterval = 1.0'));
      expect(swift, contains('taskBridgeInterval: CFTimeInterval = 1.0'));
      expect(swift, contains('if bridgedToDart && !isAppInForeground()'));
      expect(swift, contains('elapsed >= speedMinimumWindow'));
      expect(swift, contains('speedStaleInterval: CFTimeInterval = 3.0'));
      expect(swift, contains('let hasKnownOutstandingEpisode'));
      expect(swift, contains('let batchStillOutstanding'));
      expect(swift, isNot(contains('lastWrites: [String: WriteSample]')));
    });

    test('multipart coordinator errors recover instead of pausing parent', () {
      final source = File('lib/core/services/persistent_parallel_download.dart')
          .readAsStringSync();
      expect(source, contains('void _scheduleCoordinatorRecovery'));
      expect(
        source,
        contains('Coordinator bookkeeping is not a user-visible pause.'),
      );
      expect(source, contains('DownloadTelemetryEstimator _speedTelemetry'));
      expect(
        source,
        contains('kParallelProgressCoalesceDelay = Duration(seconds: 1)'),
      );
      expect(source, contains('kParallelProgressPersistInterval'));
      expect(source, contains('final nativeBridgeFresh ='));
      expect(source, contains('_scheduleProgressPersist(session)'));
    });

    test('continued-processing speed zero explicitly clears stale speed', () {
      final swift = File('ios/Runner/DownloadContinuedProcessingManager.swift')
          .readAsStringSync();
      expect(swift, contains('speedBytesPerSecond >= 0'));
    });

    test(
      'multipart progress callback cannot feed native ingress back into itself',
      () {
        final source = File('lib/core/services/download_service.dart')
            .readAsStringSync();
        final start = source.indexOf(
          'onPartProgress: (parent, child, progress) {',
        );
        final end = source.indexOf('onHostPressure:', start);
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        final callback = source.substring(start, end);
        expect(callback, contains('_publishChunkProgress('));
        expect(callback, isNot(contains('_handleNativeChunkUpdate(')));
        expect(source, contains('void _publishChunkProgress({'));
      },
    );

    test(
      'continued-processing metric updates are coalesced to one per second',
      () {
        final source = File(
          'lib/core/services/download_continued_processing_service.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('_updateSampleInterval = Duration(seconds: 1)'),
        );
        expect(source, contains('Future<void> _queueUpdate('));
        expect(source, contains('_pendingUpdate = arguments'));
        expect(source, contains('_cancelPendingUpdate();'));
      },
    );
  });
}
