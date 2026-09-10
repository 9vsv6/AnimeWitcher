import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('startup ownership reconciliation matrix', () {
    test('native ownership beats stale failed plugin status', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.failed,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
        authoritativeState: DownloadJobState.running,
      );
      expect(plan.action, DownloadRecoveryAction.keepNative);
      expect(plan.state, DownloadJobState.running);
    });

    test('running DB row without a native owner becomes interrupted', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.running,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
        authoritativeState: DownloadJobState.running,
      );
      expect(plan.action, DownloadRecoveryAction.requeue);
      expect(plan.state, DownloadJobState.interrupted);
    });

    test('durable user pause beats a still-live native worker', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.running,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
        authoritativeState: DownloadJobState.pausedByUser,
        authoritativeUserPaused: true,
      );
      expect(plan.action, DownloadRecoveryAction.keepPaused);
      expect(plan.state, DownloadJobState.pausedByUser);
    });

    test('durable FIFO waiter survives stale plugin pause state', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.paused,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
        authoritativeState: DownloadJobState.queued,
        authoritativeQueueWaiting: true,
      );
      expect(plan.action, DownloadRecoveryAction.requeue);
      expect(plan.state, DownloadJobState.queued);
    });

    test(
      'terminal logical state cannot be resurrected by native ownership',
      () {
        for (final state in <DownloadJobState>[
          DownloadJobState.completed,
          DownloadJobState.canceled,
          DownloadJobState.orphaned,
        ]) {
          final plan = planDownloadRecoveryWithJobAuthority(
            persisted: TaskStatus.running,
            queueWaiting: false,
            userPaused: false,
            stillInNativeQueue: true,
            hasMetadata: true,
            authoritativeState: state,
          );
          expect(plan.action, DownloadRecoveryAction.ignore, reason: '$state');
          expect(plan.state, state);
        }
      },
    );
  });

  group('durable byte truth ordering', () {
    test('verified final file has highest authority', () {
      final selected = selectDownloadRecoveryBytes(
        verifiedFinalFileBytes: 100,
        exactDiskBytes: 80,
        currentGenerationJobBytes: 70,
        multipartManifestBytes: 60,
      );
      expect(selected.bytes, 100);
      expect(selected.source, DownloadRecoveryByteSource.verifiedFinalFile);
    });

    test('exact visible bytes beat logical snapshots', () {
      final selected = selectDownloadRecoveryBytes(
        exactDiskBytes: 80,
        currentGenerationJobBytes: 90,
        multipartManifestBytes: 95,
      );
      expect(selected.bytes, 80);
      expect(selected.source, DownloadRecoveryByteSource.exactDisk);
    });

    test('JobStore is used when exact bytes are not visible', () {
      final selected = selectDownloadRecoveryBytes(
        currentGenerationJobBytes: 70,
        multipartManifestBytes: 60,
      );
      expect(selected.bytes, 70);
      expect(selected.source, DownloadRecoveryByteSource.jobStore);
    });

    test('decimal plugin progress is not a recovery byte input', () {
      final selected = selectDownloadRecoveryBytes();
      expect(selected.bytes, 0);
      expect(selected.source, DownloadRecoveryByteSource.none);
    });
  });
}
