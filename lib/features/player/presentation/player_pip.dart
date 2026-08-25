import 'package:flutter/services.dart';

/// Official Picture-in-Picture helpers.
///
/// Android: [Activity.enterPictureInPictureMode] with
/// [PictureInPictureParams] (API 26+), plus `setAutoEnterEnabled` on
/// Android 12. See:
/// https://developer.android.com/develop/ui/views/picture-in-picture
///
/// iOS: [AVPictureInPictureController] with an [AVPlayerLayer] in the
/// view hierarchy, `UIBackgroundModes=audio`, and an `.playback` audio
/// session. See:
/// https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller
class PlayerPip {
  static const channelName = 'com.animewitcher.app.player/pip';
  static const channel = MethodChannel(channelName);

  /// Android rejects PiP aspect ratios outside `1:2.39` … `2.39:1`.
  static const minAspectRatio = 1 / 2.39;
  static const maxAspectRatio = 2.39;

  /// Phone/tablet only. TV uses a different shell.
  static bool shouldShowButton({
    required bool showPip,
    required bool isAndroid,
    required bool isIos,
    required bool isTv,
    bool pipAvailable = true,
  }) {
    return showPip && (isAndroid || isIos) && !isTv && pipAvailable;
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
}
