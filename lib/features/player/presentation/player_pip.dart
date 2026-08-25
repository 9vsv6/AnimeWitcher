import 'package:flutter/services.dart';

/// Official Android Picture-in-Picture helpers.
///
/// Android documents this as [Activity.enterPictureInPictureMode] with
/// [PictureInPictureParams] (API 26+), plus `setAutoEnterEnabled` on
/// Android 12 so Home / gesture navigation can enter PiP without a
/// flicker. See:
/// https://developer.android.com/develop/ui/views/picture-in-picture
class PlayerPip {
  static const channelName = 'dev.akash.skystream.player/pip';
  static const channel = MethodChannel(channelName);

  /// Android rejects PiP aspect ratios outside `1:2.39` … `2.39:1`.
  static const minAspectRatio = 1 / 2.39;
  static const maxAspectRatio = 2.39;

  /// The in-player PiP control is Android phone/tablet only. TV uses a
  /// different shell, and iOS system PiP needs an `AVPlayerLayer` which
  /// this media_kit / texture player does not host.
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
}
