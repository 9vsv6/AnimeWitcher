import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'player_pip.dart';

class PlayerPlatformService {
  PlayerPlatformService({MethodChannel? pipChannel, bool? androidPip})
    : _pipChannel = pipChannel ?? PlayerPip.channel,
      _androidPip = androidPip;

  final MethodChannel _pipChannel;
  final bool? _androidPip;

  bool get _usesAndroidPip {
    if (_androidPip != null) return _androidPip;
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (e) {
      if (kDebugMode) debugPrint('PlayerPlatformService.androidPip: $e');
      return false;
    }
  }

  Map<String, Object> _pipPayload({
    required bool isPlaying,
    bool? active,
    bool? enabled,
    int? width,
    int? height,
  }) {
    final aspect = PlayerPip.clampAspectRatio(width ?? 16, height ?? 9);
    return {
      'isPlaying': isPlaying,
      'width': aspect.$1,
      'height': aspect.$2,
      'active': ?active,
      'enabled': ?enabled,
    };
  }

  /// Enters system Picture-in-Picture via the Android Activity API.
  /// Returns `false` when PiP is unavailable or the OS rejects the request.
  Future<bool> enterPip({
    required bool isPlaying,
    int? width,
    int? height,
  }) async {
    if (!_usesAndroidPip) return false;
    try {
      final result = await _pipChannel.invokeMethod<bool>(
        'enterPip',
        _pipPayload(isPlaying: isPlaying, width: width, height: height),
      );
      return result ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('PIP Error: $e');
      return false;
    }
  }

  /// Keeps Android `PictureInPictureParams` in sync (auto-enter, aspect,
  /// RemoteActions). Call while the player is open and with [active] false
  /// on dispose so Home does not PiP from other screens.
  Future<void> updatePipSession({
    required bool active,
    required bool enabled,
    required bool isPlaying,
    int? width,
    int? height,
  }) async {
    if (!_usesAndroidPip) return;
    try {
      await _pipChannel.invokeMethod<void>(
        'updatePip',
        _pipPayload(
          isPlaying: isPlaying,
          active: active,
          enabled: enabled,
          width: width,
          height: height,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PIP session error: $e');
    }
  }

  Future<bool> isPipAvailable() async {
    if (!_usesAndroidPip) return false;
    try {
      final result = await _pipChannel.invokeMethod<bool>('isPipAvailable');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('PIP availability error: $e');
      return false;
    }
  }

  void toggleOrientation(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void updateOrientation(int? width, int? height) {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return;
    } catch (e) {
      if (kDebugMode) debugPrint('PlayerPlatformService.updateOrientation: $e');
    }

    if (width != null && height != null && width > 0 && height > 0) {
      if (width >= height) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  Future<bool> toggleFullscreen() async {
    if (Platform.isAndroid || Platform.isIOS) return false;
    try {
      final isFull = await windowManager.isFullScreen();
      if (!isFull) {
        await windowManager.setFullScreen(true);
        return true;
      } else {
        await windowManager.setFullScreen(false);
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PlayerPlatformService.toggleFullscreen: $e');
    }
    return false;
  }
}
