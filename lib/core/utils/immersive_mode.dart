/// Hides the phone's own status bar while the app is open.
///
/// The app draws its own artwork to the top of the screen, and the clock,
/// battery and notification icons sit on top of it. This lets a viewer take
/// that strip back for the picture.
///
/// Desktop has no such bar, so this does nothing there.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show immutable, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which phone the request is for. The two answer different calls.
enum ImmersivePlatform { android, ios }

/// Stands in for the host platform, for tests.
///
/// Everything here is a no-op off a phone, so without this a test on a
/// desktop machine can only watch it decline to do anything.
@visibleForTesting
ImmersivePlatform? debugImmersivePlatformOverride;

ImmersivePlatform? get _platform {
  if (debugImmersivePlatformOverride != null) {
    return debugImmersivePlatformOverride;
  }
  if (kIsWeb) return null;
  if (Platform.isIOS) return ImmersivePlatform.ios;
  if (Platform.isAndroid) return ImmersivePlatform.android;
  return null;
}

/// One request to the system, as a mode and the overlays that go with it.
@immutable
class ImmersiveStep {
  const ImmersiveStep(this.mode, {this.overlays});

  final SystemUiMode mode;
  final List<SystemUiOverlay>? overlays;

  @override
  bool operator ==(Object other) =>
      other is ImmersiveStep &&
      other.mode == mode &&
      _sameOverlays(other.overlays, overlays);

  static bool _sameOverlays(
    List<SystemUiOverlay>? a,
    List<SystemUiOverlay>? b,
  ) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(overlays ?? const []));

  @override
  String toString() =>
      'ImmersiveStep($mode${overlays == null ? '' : ', $overlays'})';
}

/// What to ask the system for, in order.
///
/// The last step is the one that decides the outcome, so which call ends the
/// list matters more than which calls are in it:
///
///  * **iOS** understands only `manual`. Every other mode is sent over the
///    channel Android implements, so asking iOS for `immersiveSticky` — or
///    for edge-to-edge on the way back out — does nothing at all, and a bar
///    hidden by some other route is never asked to return. Naming the top
///    overlay shows the status bar; omitting it hides it.
///  * **Android** has two eras. Up to Android 14 the bars are governed by the
///    legacy overlay flags `manual` sets. From Android 15 the system enforces
///    edge-to-edge for an app targeting API 35, and from Android 16 it
///    ignores every mode except `edgeToEdge` outright — this app targets 36.
///    So the way back out asks both ways and ends on `edgeToEdge`, the one a
///    current phone honours; on an older phone the legacy call has already
///    done the work and the last step is a no-op.
///
/// Nothing here calls `restoreSystemUIOverlays`. That re-applies whatever
/// overlay state the embedder is holding, which after a spell of full screen
/// is the state being escaped from.
@visibleForTesting
List<ImmersiveStep> immersivePlan(bool enabled, ImmersivePlatform platform) {
  if (platform == ImmersivePlatform.ios) {
    return <ImmersiveStep>[
      ImmersiveStep(
        SystemUiMode.manual,
        overlays: enabled ? const <SystemUiOverlay>[] : SystemUiOverlay.values,
      ),
    ];
  }

  if (enabled) {
    return const <ImmersiveStep>[ImmersiveStep(SystemUiMode.immersiveSticky)];
  }

  return const <ImmersiveStep>[
    ImmersiveStep(SystemUiMode.manual, overlays: SystemUiOverlay.values),
    ImmersiveStep(SystemUiMode.edgeToEdge),
  ];
}

/// Applies [enabled] now.
void applyImmersiveFullScreen(bool enabled) {
  final platform = _platform;
  if (platform == null) return;
  unawaited(_apply(enabled, platform));
}

Future<void> _apply(bool enabled, ImmersivePlatform platform) async {
  for (final step in immersivePlan(enabled, platform)) {
    await SystemChrome.setEnabledSystemUIMode(
      step.mode,
      overlays: step.overlays,
    );
  }
}

/// How long to keep re-asserting the choice after asking for it.
///
/// Long enough to cover a rotation and the relayout that follows it, short
/// enough to be over before a viewer can ask for anything else.
@visibleForTesting
const Duration immersiveHoldWindow = Duration(seconds: 2);

_ImmersiveHold? _currentHold;

/// Applies [enabled] and holds it through the window changing shape.
///
/// Leaving the player also puts the orientation back, and a window that
/// reconfigures for a new orientation comes back with the system bars in
/// their default state — undoing a full-screen request made in the same
/// breath. That is why turning the setting on and then closing an episode
/// handed the status bar back: the request was made and then wiped, a few
/// milliseconds apart.
///
/// So the choice is asked for again on every change of window metrics for a
/// short while afterwards, and then let go of.
void holdImmersiveFullScreen(bool enabled) {
  applyImmersiveFullScreen(enabled);
  if (_platform == null) return;

  _currentHold?.stop();
  _currentHold = _ImmersiveHold(enabled)..start();
}

/// Drops any hold in progress, so the next request is the last word.
@visibleForTesting
void cancelImmersiveHold() {
  _currentHold?.stop();
  _currentHold = null;
}

class _ImmersiveHold with WidgetsBindingObserver {
  _ImmersiveHold(this.enabled);

  final bool enabled;
  Timer? _timeout;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timeout = Timer(immersiveHoldWindow, stop);
  }

  @override
  void didChangeMetrics() {
    applyImmersiveFullScreen(enabled);
  }

  void stop() {
    _timeout?.cancel();
    _timeout = null;
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_currentHold, this)) _currentHold = null;
  }
}
