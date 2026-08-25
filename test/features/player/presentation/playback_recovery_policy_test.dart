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
      expect(
        PlaybackRecoveryPolicy.watchdogStage(
          PlaybackRecoveryPolicy.bufferNudgeAfter,
        ),
        BufferWatchdogStage.reissueSeek,
      );
      expect(
        PlaybackRecoveryPolicy.watchdogStage(
          PlaybackRecoveryPolicy.reopenSourceAfter -
              const Duration(milliseconds: 1),
        ),
        BufferWatchdogStage.reissueSeek,
      );
      expect(
        PlaybackRecoveryPolicy.watchdogStage(
          PlaybackRecoveryPolicy.reopenSourceAfter,
        ),
        BufferWatchdogStage.reopenSource,
      );
      expect(
        PlaybackRecoveryPolicy.watchdogStage(
          PlaybackRecoveryPolicy.failoverSourceAfter -
              const Duration(milliseconds: 1),
        ),
        BufferWatchdogStage.reopenSource,
      );
      expect(
        PlaybackRecoveryPolicy.watchdogStage(
          PlaybackRecoveryPolicy.failoverSourceAfter,
        ),
        BufferWatchdogStage.failover,
      );
    });
  });

  group('reconnectBackoff', () {
    test('first try is immediate; later failures wait 2s then 4s', () {
      expect(PlaybackRecoveryPolicy.reconnectBackoff(0), Duration.zero);
      expect(
        PlaybackRecoveryPolicy.reconnectBackoff(1),
        const Duration(seconds: 2),
      );
      expect(
        PlaybackRecoveryPolicy.reconnectBackoff(2),
        const Duration(seconds: 4),
      );
      expect(PlaybackRecoveryPolicy.reconnectBackoff(3), isNull);
    });
  });

  group('canReconnect', () {
    test('allows up to the cap, then refuses', () {
      expect(PlaybackRecoveryPolicy.canReconnect(0), isTrue);
      expect(PlaybackRecoveryPolicy.canReconnect(2), isTrue);
      expect(PlaybackRecoveryPolicy.canReconnect(3), isFalse);
    });
  });

  group('worstCaseReconnectLadder', () {
    test('sums waiting time between the three attempts (2+4s)', () {
      expect(
        PlaybackRecoveryPolicy.worstCaseReconnectLadder,
        const Duration(seconds: 6),
      );
    });
  });

  group('isPermanentPlaybackError', () {
    test('treats 401/403/404 as dead URLs', () {
      expect(
        PlaybackRecoveryPolicy.isPermanentPlaybackError(
          Exception('HTTP 403 Forbidden'),
        ),
        isTrue,
      );
      expect(
        PlaybackRecoveryPolicy.isPermanentPlaybackError(
          Exception('status code of 404'),
        ),
        isTrue,
      );
      expect(
        PlaybackRecoveryPolicy.isPermanentPlaybackError(
          Exception('SocketException: Connection reset'),
        ),
        isFalse,
      );
    });
  });
}
