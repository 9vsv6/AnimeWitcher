import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sends download state to the native iOS ActivityKit implementation.
class DownloadLiveActivityService {
  static const MethodChannel _channel = MethodChannel(
    'dev.akash.skystream/download_live_activity',
  );

  final Map<String, DateTime> _lastUpdateAt = {};
  final Map<String, double> _lastProgress = {};
  final Map<String, String> _lastStatus = {};

  bool get _isAvailable => !kIsWeb && Platform.isIOS;

  Future<void> start({
    required String taskId,
    required String animeTitle,
    required String episodeTitle,
  }) async {
    if (!_isAvailable) return;

    await _invoke('start', <String, Object>{
      'taskId': taskId,
      'animeTitle': animeTitle,
      'episodeTitle': episodeTitle,
    });
  }

  Future<void> update({
    required String taskId,
    required double progress,
    required double speedMBps,
    required String status,
    bool force = false,
  }) async {
    if (!_isAvailable) return;

    final normalizedProgress = progress.clamp(0.0, 1.0);
    final normalizedSpeed = speedMBps.isFinite && speedMBps > 0
        ? speedMBps
        : 0.0;
    final now = DateTime.now();
    final previousAt = _lastUpdateAt[taskId];
    final previousProgress = _lastProgress[taskId] ?? -1.0;
    final previousStatus = _lastStatus[taskId];

    final progressChanged =
        (normalizedProgress - previousProgress).abs() >= 0.01;
    final statusChanged = previousStatus != status;
    final enoughTimePassed =
        previousAt == null ||
        now.difference(previousAt) >= const Duration(milliseconds: 900);

    if (!force && !progressChanged && !statusChanged && !enoughTimePassed) {
      return;
    }

    _lastUpdateAt[taskId] = now;
    _lastProgress[taskId] = normalizedProgress;
    _lastStatus[taskId] = status;

    await _invoke('update', <String, Object>{
      'taskId': taskId,
      'progress': normalizedProgress,
      'speedMBps': normalizedSpeed,
      'status': status,
    });
  }

  Future<void> end({
    required String taskId,
    required String status,
    double? progress,
  }) async {
    if (!_isAvailable) return;

    final finalProgress =
        progress?.clamp(0.0, 1.0) ??
        _lastProgress[taskId] ??
        (status == 'completed' ? 1.0 : 0.0);

    await _invoke('end', <String, Object>{
      'taskId': taskId,
      'progress': finalProgress,
      'speedMBps': 0.0,
      'status': status,
    });

    _lastUpdateAt.remove(taskId);
    _lastProgress.remove(taskId);
    _lastStatus.remove(taskId);
  }

  Future<void> _invoke(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // The current platform/build does not include ActivityKit.
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DownloadLiveActivity] $method failed: '
          '${error.code} ${error.message}',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[DownloadLiveActivity] $method failed: $error');
      }
    }
  }
}
