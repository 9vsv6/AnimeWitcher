import 'dart:async';

import '../../../core/discord/discord_presence.dart';

/// Keeps the Discord status in step with the player while it is open.
///
/// It looks at the player every few seconds and sends an update only when
/// something a viewer would see changed: another episode, play or pause, or
/// a seek (the time bar's start moving by more than [seekTolerance]). Normal
/// playback needs no updates — Discord runs the bar from the timestamps.
class DiscordPresenceDriver {
  DiscordPresenceDriver({
    required this.snapshot,
    required this.presence,
    required this.arabic,
    this.interval = const Duration(seconds: 3),
    this.seekTolerance = const Duration(seconds: 4),
    int Function()? nowMillis,
  }) : _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DiscordWatchSnapshot? Function() snapshot;
  final DiscordPresence presence;
  final bool arabic;
  final Duration interval;
  final Duration seekTolerance;
  final int Function() _nowMillis;

  Timer? _timer;
  String? _lastIdentity;
  int? _lastStartMs;

  void start() {
    _timer?.cancel();
    tick();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// One look at the player; public so tests can step it.
  void tick() {
    final current = snapshot();
    if (current == null) return;
    final now = _nowMillis();
    final activity = discordActivityFor(current, arabic: arabic, nowMs: now);
    final identity = [
      current.title,
      current.season,
      current.episode,
      current.isPlaying,
      current.posterUrl,
    ].join('|');
    final startMs = current.isPlaying ? now - current.positionMs : null;
    final seeked =
        startMs != null &&
        _lastStartMs != null &&
        (startMs - _lastStartMs!).abs() > seekTolerance.inMilliseconds;
    if (identity == _lastIdentity && !seeked) return;
    _lastIdentity = identity;
    _lastStartMs = startMs;
    presence.update(activity);
  }

  /// Leaving the player clears the status.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastIdentity = null;
    _lastStartMs = null;
    presence.clear();
  }
}
