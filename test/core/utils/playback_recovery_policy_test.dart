import 'package:flutter_test/flutter_test.dart';

import 'package:skystream/features/player/presentation/playback_recovery_policy.dart';

void main() {
  group('watchdogStage', () {
    test('does nothing before the first threshold', () {
      expect(
        PlaybackRecoveryPolicy.watchdogStage(const Duration(seconds: 11)),
        BufferWatchdogStage.none,
      );
    });

    test('escalates at each threshold boundary', () {
      const p = PlaybackRecoveryPolicy;
      expect(p.watchdogStage(p.bufferNudgeAfter),
          BufferWatchdogStage.reissueSeek);
      expect(
        p.watchdogStage(p.reopenSourceAfter - const Duration(milliseconds: 1)),
        BufferWatchdogStage.reissueSeek,
      );
      expect(p.watchdogStage(p.reopenSourceAfter),
          BufferWatchdogStage.reopenSource);
      expect(
        p.watchdogStage(p.failoverSourceAfter - const Duration(minutes: 1)),
        BufferWatchdogStage.reopenSource,
      );
      expect(p.watchdogStage(p.failoverSourceAfter),
          BufferWatchdogStage.failover);
      expect(
        p.watchdogStage(p.failoverSourceAfter * 2),
        BufferWatchdogStage.failover,
      );
    });
  });

  group('reconnectBackoff', () {
    test('doubles per attempt: 2s, 4s, 8s', () {
      expect(PlaybackRecoveryPolicy.reconnectBackoff(1),
          const Duration(seconds: 2));
      expect(PlaybackRecoveryPolicy.reconnectBackoff(2),
          const Duration(seconds: 4));
      expect(PlaybackRecoveryPolicy.reconnectBackoff(3),
          const Duration(seconds: 8));
    });

    test('clamps out-of-range attempts', () {
      expect(PlaybackRecoveryPolicy.reconnectBackoff(0),
          const Duration(seconds: 2));
      expect(PlaybackRecoveryPolicy.reconnectBackoff(-3),
          const Duration(seconds: 2));
      expect(PlaybackRecoveryPolicy.reconnectBackoff(99),
          const Duration(seconds: 8));
    });
  });

  group('canReconnect', () {
    test('allows up to the cap, then refuses', () {
      expect(PlaybackRecoveryPolicy.canReconnect(0), isTrue);
      expect(PlaybackRecoveryPolicy.canReconnect(2), isTrue);
      expect(PlaybackRecoveryPolicy.canReconnect(3), isFalse);
      expect(PlaybackRecoveryPolicy.canReconnect(4), isFalse);
    });
  });

  group('worstCaseReconnectLadder', () {
    test('sums the full ladder (2+4+8s)', () {
      expect(
        PlaybackRecoveryPolicy.worstCaseReconnectLadder,
        const Duration(seconds: 14),
      );
    });
  });
}
