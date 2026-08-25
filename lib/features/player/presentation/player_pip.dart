import 'package:flutter/services.dart';

/// Official Picture-in-Picture helpers.
///
/// Android: [Activity.enterPictureInPictureMode] with
/// [PictureInPictureParams] (API 26+), plus `setAutoEnterEnabled` on
/// Android 12. See:
/// https://developer.android.com/develop/ui/views/picture-in-picture
///
/// iOS is not supported: Apple PiP requires a native `AVPlayerLayer`, which
/// is a second video surface on top of the Flutter player.
class PlayerPip {
  static const channelName = 'com.animewitcher.app.player/pip';
  static const channel = MethodChannel(channelName);

  /// Android rejects PiP aspect ratios outside `1:2.39` … `2.39:1`.
  static const minAspectRatio = 1 / 2.39;
  static const maxAspectRatio = 2.39;

  /// Android phone/tablet only. TV uses a different shell. iOS has no PiP.
  static bool shouldShowButton({
    required bool showPip,
    required bool isAndroid,
    required bool isTv,
    bool pipAvailable = true,
  }) {
    return showPip && isAndroid && !isTv && pipAvailable;
  }

  /// Clamp a video size into the ratio window Android accepts.
  static (int, int) clampAspectRatio(int width, int height) {
    final safeW = width > 0 ? width : 16;
    final safeH = height > 0 ? height : 9;
    final ratio = safeW / safeH;
    if (ratio < minAspectRatio) return (100, 239);
    if (ratio > maxAspectRatio) return (239, 100);
    return (safeW, safeH);
  }

  /// Android sends a bool.
  static PlayerPipMode modeFromNative(dynamic arguments) {
    return PlayerPipMode(active: arguments == true);
  }
}

class PlayerPipMode {
  const PlayerPipMode({required this.active});

  final bool active;
}
