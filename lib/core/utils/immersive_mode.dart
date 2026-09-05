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

import 'package:flutter/foundation.dart' show immutable, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

bool get _isPhone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Which phone the request is for. The two answer different calls.
enum ImmersivePlatform { android, ios }

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
  if (!_isPhone) return;
  unawaited(
    _apply(
      enabled,
      Platform.isIOS ? ImmersivePlatform.ios : ImmersivePlatform.android,
    ),
  );
}

Future<void> _apply(bool enabled, ImmersivePlatform platform) async {
  for (final step in immersivePlan(enabled, platform)) {
    await SystemChrome.setEnabledSystemUIMode(
      step.mode,
      overlays: step.overlays,
    );
  }
}
