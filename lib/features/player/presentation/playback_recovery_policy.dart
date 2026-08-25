// Tuning knobs for mid-playback recovery, in one place.
//
// `player_controller.dart` recovers from seeks/buffering outside the cache
// and from mid-playback errors with an escalating ladder: nudge the seek →
// re-open the same source → fail over to the next source, plus up to three
// seamless same-source reconnects with exponential backoff. The constants
// below are the values currently shipped in the controller; centralizing
// them documents intent and gives the ladder a single source of truth. See
// docs/stream-links-and-player-audit.md findings A1/A2/B1/B2.
//
// Known production bug this makes trivial to fix: the controller's watchdog
// leaves its periodic timer armed after the terminal stage. Callers adopting
// [PlaybackRecoveryPolicy.watchdogStage] should stop polling once it reports
// [BufferWatchdogStage.failover].

/// What the buffer watchdog wants the controller to do at a given moment.
enum BufferWatchdogStage {
  /// Not stuck long enough to act.
  none,

  /// Stuck ~12 s: re-issue the seek at the same position and kick play().
  reissueSeek,

  /// Stuck ~25 s: re-open the SAME source at the same position.
  reopenSource,

  /// Stuck ~45 s: give up on this source and try the next one.
  /// Terminal — the periodic check must be cancelled after reporting this.
  failover,
}

/// Named thresholds and budgets for the player's recovery ladder.
class PlaybackRecoveryPolicy {
  PlaybackRecoveryPolicy._();

  /// Stuck-buffering age before the seek is re-issued.
  static const Duration bufferNudgeAfter = Duration(seconds: 12);

  /// Stuck-buffering age before the same source is reopened in place.
  static const Duration reopenSourceAfter = Duration(seconds: 25);

  /// Stuck-buffering age before failing over to the next source.
  static const Duration failoverSourceAfter = Duration(seconds: 45);

  /// Seamless same-source reconnects allowed for mid-playback errors.
  static const int maxMidPlaybackRetries = 3;

  /// Backoff before reconnect attempt [attempt] (1-based): 2 s, 4 s, 8 s.
  /// Attempts beyond the cap clamp to the last delay so callers can schedule
  /// without range checks.
  static Duration reconnectBackoff(int attempt) => Duration(
        seconds: 1 << attempt.clamp(1, maxMidPlaybackRetries),
      );

  /// Whether another seamless reconnect may still be attempted after
  /// [attemptsMade] attempts have already been made (starts at 0).
  /// Single gate for every trigger — error listeners, the connectivity kick,
  /// and the foreground-return kick — so parallel paths cannot overspend the
  /// budget.
  static bool canReconnect(int attemptsMade) =>
      attemptsMade >= 0 && attemptsMade < maxMidPlaybackRetries;

  /// Maps how long playback has been stuck buffering to the action to take.
  static BufferWatchdogStage watchdogStage(Duration stuckFor) {
    if (stuckFor >= failoverSourceAfter) return BufferWatchdogStage.failover;
    if (stuckFor >= reopenSourceAfter) return BufferWatchdogStage.reopenSource;
    if (stuckFor >= bufferNudgeAfter) return BufferWatchdogStage.reissueSeek;
    return BufferWatchdogStage.none;
  }

  /// Total worst-case time the reconnect ladder spends waiting between
  /// attempts before failover, assuming every backoff elapses.
  static Duration get worstCaseReconnectLadder {
    var total = Duration.zero;
    for (var attempt = 1; attempt <= maxMidPlaybackRetries; attempt++) {
      total += reconnectBackoff(attempt);
    }
    return total;
  }
}
