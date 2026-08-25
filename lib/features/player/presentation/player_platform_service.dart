import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'player_pip.dart';

class PlayerPlatformService {
  PlayerPlatformService({MethodChannel? pipChannel, bool? nativePip})
    : _pipChannel = pipChannel ?? PlayerPip.channel,
      _nativePip = nativePip;

  final MethodChannel _pipChannel;
  final bool? _nativePip;

  bool get _usesNativePip {
    if (_nativePip != null) return _nativePip;
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (e) {
      if (kDebugMode) debugPrint('PlayerPlatformService.nativePip: $e');
      return false;
    }
  }

  Map<String, dynamic> _pipPayload({
    required bool isPlaying,
    bool? active,
    bool? enabled,
    int? width,
    int? height,
    String? url,
    Map<String, String>? headers,
    int? positionMs,
  }) {
    final aspect = PlayerPip.clampAspectRatio(width ?? 16, height ?? 9);
    return <String, dynamic>{
      'isPlaying': isPlaying,
      'width': aspect.$1,
      'height': aspect.$2,
      'active': ?active,
      'enabled': ?enabled,
      'url': ?url,
      'positionMs': ?positionMs,
      'headers': ?headers,
    };
  }

  /// Enters system Picture-in-Picture (Android Activity PiP or iOS
  /// `AVPictureInPictureController`). Returns `false` when unavailable.
  Future<bool> enterPip({
    required bool isPlaying,
    int? width,
    int? height,
    String? url,
    Map<String, String>? headers,
    int? positionMs,
  }) async {
    if (!_usesNativePip) return false;
    try {
      final result = await _pipChannel.invokeMethod<bool>(
        'enterPip',
        _pipPayload(
          isPlaying: isPlaying,
          width: width,
          height: height,
          url: url,
          headers: headers,
          positionMs: positionMs,
        ),
      );
      return result ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('PIP Error: $e');
      return false;
    }
  }

  /// Keeps native PiP params in sync (auto-enter, aspect, session).
  /// Call while the player is open and with [active] false on dispose.
  Future<void> updatePipSession({
    required bool active,
    required bool enabled,
    required bool isPlaying,
    int? width,
    int? height,
  }) async {
    if (!_usesNativePip) return;
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
    if (!_usesNativePip) return false;
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
