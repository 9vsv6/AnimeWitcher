/// Hides the phone's own status bar while the app is open.
///
/// The app draws its own artwork to the top of the screen, and the clock,
/// battery and notification icons sit on top of it. This lets a viewer take
/// that strip back for the picture.
///
/// Desktop has no such bar, so this does nothing there.
library;

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
  if (enabled) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }
}
