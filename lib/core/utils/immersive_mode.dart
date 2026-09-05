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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

bool get _isPhone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Applies [enabled] now.
///
/// `immersiveSticky` rather than `immersive` so a stray swipe brings the bar
/// back only for a moment instead of leaving it up for the rest of the
/// session.
void applyImmersiveFullScreen(bool enabled) {
  if (!_isPhone) return;
  unawaited(_apply(enabled));
}

Future<void> _apply(bool enabled) async {
  // Only `manual` reaches iOS. Every other mode is sent over the channel
  // Android implements, so asking iOS for immersiveSticky — or for
  // edge-to-edge on the way back out — does nothing, and the bar it hid by
  // some other route is never asked to return. On iOS the overlay list is
  // the whole mechanism: naming the top overlay shows the status bar,
  // omitting it hides it.
  if (Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: enabled ? const <SystemUiOverlay>[] : SystemUiOverlay.values,
    );
    return;
  }

  if (enabled) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return;
  }

  // Asking for the bars straight out of immersiveSticky leaves them hidden:
  // the sticky mode outlives the request, and the app is left full screen
  // with the switch turned off. Dropping to edge-to-edge first clears it, and
  // only then is it worth asking for the bars back.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  // Belt and braces: this is the call meant for putting overlays back that a
  // gesture temporarily dismissed, and it costs nothing when they are shown.
  SystemChrome.restoreSystemUIOverlays();
}
