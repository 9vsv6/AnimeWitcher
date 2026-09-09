import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('download recovery state machine', () {
    test('completed is terminal even when stale flags remain', () {
      final plan = planDownloadRecovery(
        persisted: TaskStatus.complete,
        queueWaiting: true,
        userPaused: true,
        stillInNativeQueue: true,
        hasMetadata: true,
      );

      expect(plan.state, DownloadJobState.completed);
      expect(plan.action, DownloadRecoveryAction.ignore);
      expect(plan.shouldRequeue, isFalse);
    });

    test('explicit user pause wins over queue and native ownership', () {
      final plan = planDownloadRecovery(
        persisted: TaskStatus.running,
        queueWaiting: true,
        userPaused: true,
        stillInNativeQueue: true,
        hasMetadata: true,
      );

      expect(plan.state, DownloadJobState.pausedByUser);
      expect(plan.action, DownloadRecoveryAction.keepPaused);
      expect(plan.shouldRequeue, isFalse);
    });

    test('live native ownership prevents duplicate enqueue', () {
      final running = planDownloadRecovery(
        persisted: TaskStatus.failed,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
      );
      final enqueued = planDownloadRecovery(
        persisted: TaskStatus.enqueued,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
      );
      final retrying = planDownloadRecovery(
        persisted: TaskStatus.waitingToRetry,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
      );

      expect(running.state, DownloadJobState.running);
      expect(running.isNativeOwned, isTrue);
      expect(enqueued.state, DownloadJobState.starting);
      expect(enqueued.isNativeOwned, isTrue);
      expect(retrying.state, DownloadJobState.retryWaiting);
      expect(retrying.isNativeOwned, isTrue);
    });

    test('durable logical waiter is rebuilt after process death', () {
      final plan = planDownloadRecovery(
        persisted: TaskStatus.paused,
        queueWaiting: true,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
      );

      expect(plan.state, DownloadJobState.queued);
      expect(plan.action, DownloadRecoveryAction.requeue);
      expect(plan.shouldRequeue, isTrue);
    });

    test('running native statuses become interrupted when ownership is gone', () {
      for (final status in <TaskStatus>[
        TaskStatus.enqueued,
        TaskStatus.running,
        TaskStatus.waitingToRetry,
      ]) {
        final plan = planDownloadRecovery(
          persisted: status,
          queueWaiting: false,
          userPaused: false,
          stillInNativeQueue: false,
          hasMetadata: false,
        );

        expect(plan.state, DownloadJobState.interrupted, reason: '$status');
        expect(plan.action, DownloadRecoveryAction.requeue, reason: '$status');
      }
    });

    test('system pause and errors require durable AnimeWitcher metadata', () {
      for (final status in <TaskStatus>[
        TaskStatus.paused,
        TaskStatus.failed,
        TaskStatus.notFound,
      ]) {
        final recoverable = planDownloadRecovery(
          persisted: status,
          queueWaiting: false,
          userPaused: false,
          stillInNativeQueue: false,
          hasMetadata: true,
        );
        final orphaned = planDownloadRecovery(
          persisted: status,
          queueWaiting: false,
          userPaused: false,
          stillInNativeQueue: false,
          hasMetadata: false,
        );

        expect(
          recoverable.state,
          DownloadJobState.interrupted,
          reason: '$status with metadata',
        );
        expect(
          recoverable.action,
          DownloadRecoveryAction.requeue,
          reason: '$status with metadata',
        );
        expect(
          orphaned.state,
          DownloadJobState.orphaned,
          reason: '$status without metadata',
        );
        expect(
          orphaned.action,
          DownloadRecoveryAction.ignore,
          reason: '$status without metadata',
        );
      }
    });

    test('user delete cannot be resurrected but system cancel can recover', () {
      final deleted = planDownloadRecovery(
        persisted: TaskStatus.canceled,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: false,
      );
      final systemCanceled = planDownloadRecovery(
        persisted: TaskStatus.canceled,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
      );

      expect(deleted.state, DownloadJobState.canceled);
      expect(deleted.action, DownloadRecoveryAction.ignore);
      expect(systemCanceled.state, DownloadJobState.interrupted);
      expect(systemCanceled.action, DownloadRecoveryAction.requeue);
    });
  });

  group('download attempt fence', () {
    test('new generation rejects callbacks from the previous attempt', () {
      final fence = DownloadAttemptFence();
      final first = fence.begin('episode-1');

      expect(first.generation, 1);
      expect(fence.accepts(first), isTrue);

      final second = fence.begin('episode-1');
      expect(second.generation, 2);
      expect(fence.accepts(first), isFalse);
      expect(fence.accepts(second), isTrue);
    });

    test('invalidate fences old callbacks without launching another worker', () {
      final fence = DownloadAttemptFence();
      final running = fence.begin('episode-1');
      final invalidation = fence.invalidate('episode-1');

      expect(invalidation.generation, running.generation + 1);
      expect(fence.accepts(running), isFalse);
      expect(fence.accepts(invalidation), isTrue);
    });

    test('persisted generations continue monotonically after relaunch', () {
      final fence = DownloadAttemptFence(const {'episode-1': 7, 'episode-2': 2});

      final token = fence.begin('episode-1');
      expect(token.generation, 8);
      expect(fence.generationFor('episode-2'), 2);
      expect(fence.snapshot(), {'episode-1': 8, 'episode-2': 2});
    });

    test('attempts are isolated per logical episode', () {
      final fence = DownloadAttemptFence();
      final firstEpisode = fence.begin('episode-1');
      final secondEpisode = fence.begin('episode-2');
      final firstEpisodeRetry = fence.begin('episode-1');

      expect(fence.accepts(firstEpisode), isFalse);
      expect(fence.accepts(firstEpisodeRetry), isTrue);
      expect(fence.accepts(secondEpisode), isTrue);
    });

    test('empty task identifiers are rejected', () {
      final fence = DownloadAttemptFence();
      expect(() => fence.begin('   '), throwsArgumentError);
    });
  });
}
