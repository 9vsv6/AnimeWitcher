// Tuning knobs for mid-playback recovery, in one place.
//
// The controller recovers from seeks/buffering outside the cache and from
// mid-playback errors with an escalating ladder: nudge the seek → re-open
// the same source → fail over to the next source, plus up to three seamless
// same-source reconnects.

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

  /// Pause long enough that a signed CDN URL should be re-extracted
  /// before play() hits a stale 403.
  static const Duration signedUrlRefreshAfter = Duration(minutes: 10);

  /// Whether another seamless reconnect may still be attempted after
  /// [attemptsMade] attempts have already been made (starts at 0).
  /// Single gate for every trigger — error listeners, the connectivity kick,
  /// and the foreground-return kick — so parallel paths cannot overspend the
  /// budget.
  static bool canReconnect(int attemptsMade) =>
      attemptsMade >= 0 && attemptsMade < maxMidPlaybackRetries;

  /// Delay after [attemptsMade] failed reconnects, before the next try.
  ///
  /// The first attempt is immediate (`attemptsMade == 0`). After failure 1
  /// wait 2 s, after failure 2 wait 4 s. Returns null when the budget is
  /// spent so the caller failsover instead of scheduling.
  static Duration? reconnectBackoff(int attemptsMade) {
    if (attemptsMade <= 0) return Duration.zero;
    if (attemptsMade >= maxMidPlaybackRetries) return null;
    return Duration(seconds: 1 << attemptsMade);
  }

  /// Maps how long playback has been stuck buffering to the action to take.
  ///
  /// The controller still fires each stage once via its own stage counter;
  /// this classifier is the named form of the 12/25/45 s thresholds.
  static BufferWatchdogStage watchdogStage(Duration stuckFor) {
    if (stuckFor >= failoverSourceAfter) return BufferWatchdogStage.failover;
    if (stuckFor >= reopenSourceAfter) return BufferWatchdogStage.reopenSource;
    if (stuckFor >= bufferNudgeAfter) return BufferWatchdogStage.reissueSeek;
    return BufferWatchdogStage.none;
  }

  /// Waiting time between reconnect attempts before failover, assuming
  /// every backoff elapses (2 s + 4 s). The first try is immediate.
  static Duration get worstCaseReconnectLadder {
    var total = Duration.zero;
    for (var attempt = 1; attempt < maxMidPlaybackRetries; attempt++) {
      total += reconnectBackoff(attempt) ?? Duration.zero;
    }
    return total;
  }

  /// HTTP 401/403/404/410 and similar "this URL is dead" errors should skip
  /// the reconnect ladder and fail over immediately.
  static bool isPermanentPlaybackError(Object error) {
    final text = error.toString().toLowerCase();
    if (RegExp(r'\b(401|403|404|410)\b').hasMatch(text)) return true;
    if (text.contains('unauthorized') ||
        text.contains('forbidden') ||
        text.contains('not found') ||
        text.contains('status code of 4')) {
      return true;
    }
    return false;
  }
}
