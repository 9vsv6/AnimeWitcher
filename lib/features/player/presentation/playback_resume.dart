import 'dart:async';

/// Hold playback until a saved resume position has been seeked.
///
/// Opening the stream and then seeking a second later flashes the start of
/// the episode. Callers look up the saved position first, open paused, seek,
/// and only then reveal video / start playback.
class PlaybackResume {
  PlaybackResume._();

  /// Ignore tiny saved offsets so a 1-second tap does not hold startup.
  static const int minPositionMs = 2000;

  /// Consider the engine "at" the resume point once it is this close.
  /// HLS often lands on the nearest keyframe, so this is wider than a
  /// frame-accurate seek.
  static const int settleToleranceMs = 5000;

  /// How long to wait for the engine to report the seeked position.
  static const Duration seekSettleTimeout = Duration(seconds: 8);

  /// How long downloaded and streaming playback may wait for a cloud bookmark.
  /// Offline, Firestore/Auth can sit until connect timeout or longer; two
  /// seconds is enough when the server is reachable and fails fast when not.
  static const Duration cloudResumeTimeout = Duration(seconds: 2);

  static bool shouldHoldUntilSeeked(int savedPositionMs) =>
      savedPositionMs >= minPositionMs;

  /// A usable local bookmark can start immediately. Otherwise downloaded and
  /// streaming playback both wait up to [cloudResumeTimeout] for the cloud.
  static bool shouldAwaitCloudResume(int localPositionMs) =>
      !shouldHoldUntilSeeked(localPositionMs);

  /// Returns the local bookmark, or a cloud bookmark when it arrives quickly.
  ///
  /// Downloaded files and remote streams share the same 2s ceiling. A hanging
  /// [cloudPositionMs] fails open to [localPositionMs] so startup never waits
  /// on Auth/Firestore timeouts.
  static Future<int> resolveStartupPosition({
    required int localPositionMs,
    required Future<int> Function() cloudPositionMs,
    Duration cloudTimeout = cloudResumeTimeout,
  }) async {
    if (!shouldAwaitCloudResume(localPositionMs)) {
      return localPositionMs;
    }
    try {
      return await cloudPositionMs().timeout(cloudTimeout);
    } on TimeoutException {
      return localPositionMs;
    } catch (_) {
      return localPositionMs;
    }
  }

  static bool isNear({
    required int currentMs,
    required int targetMs,
    int toleranceMs = settleToleranceMs,
  }) {
    return (currentMs - targetMs).abs() <= toleranceMs;
  }

  /// Keep the startup overlay up while a resume seek is still outstanding
  /// and the playhead is still at the beginning of the file.
  static bool canRevealVideo({
    required int? pendingResumeMs,
    required bool applyingResume,
    required int currentMs,
  }) {
    if (applyingResume) return false;
    if (pendingResumeMs != null && pendingResumeMs >= minPositionMs) {
      return isNear(currentMs: currentMs, targetMs: pendingResumeMs);
    }
    return currentMs > 0;
  }
}
