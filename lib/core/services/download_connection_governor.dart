import 'package:background_downloader/background_downloader.dart';

import 'download_parallel.dart';

/// How strongly a child transfer failure should influence connection growth.
enum DownloadConnectionPressure {
  /// Not a signal that parallelism is stressing the origin/network.
  none,

  /// Back off this transfer, but do not teach every transfer for the host.
  transient,

  /// The origin is explicitly overloaded/rate-limiting; remember a safer cap.
  host,
}

/// Classifies retry/failure updates that should stop Gopeed-style slow start.
///
/// `background_downloader` exposes HTTP errors as [TaskHttpException] and
/// connection/socket failures as [TaskConnectionException]. 429 and the common
/// overload/gateway statuses are strong host-level signals. Other 5xx and
/// connection failures still back off the current episode, but are not cached
/// for sibling/future episodes because they may be unrelated to concurrency.
DownloadConnectionPressure downloadConnectionPressureFor(
  TaskStatusUpdate update,
) {
  if (update.status != TaskStatus.waitingToRetry &&
      update.status != TaskStatus.failed) {
    return DownloadConnectionPressure.none;
  }

  final exception = update.exception;
  final statusCode = update.responseStatusCode ??
      (exception is TaskHttpException ? exception.httpResponseCode : null);

  if (statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504 ||
      statusCode == 509) {
    return DownloadConnectionPressure.host;
  }

  if (statusCode != null && statusCode >= 500 && statusCode <= 599) {
    return DownloadConnectionPressure.transient;
  }
  if (exception is TaskConnectionException) {
    return DownloadConnectionPressure.transient;
  }
  return DownloadConnectionPressure.none;
}

String downloadOriginKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://$host$port';
}

/// Session-lifetime memory of safe connection ceilings.
///
/// Host ceilings are shared by sibling/future transfers after an explicit
/// overload signal. Transient failures only teach the exact transfer URL, so a
/// flaky connection cannot unnecessarily throttle every episode on the CDN.
/// Both memories intentionally reset when the app process restarts; a later
/// confidence/probing phase can make upward recovery more sophisticated.
class DownloadConnectionGovernor {
  final Map<String, int> _learnedHostCeilings = <String, int>{};
  final Map<String, int> _learnedTransferCeilings = <String, int>{};

  int connectionCeilingFor(String url, {required int requested}) {
    final safeRequested = requested
        .clamp(kDownloadPartsMin, kDownloadGlobalConnectionBudget)
        .toInt();
    final host = _learnedHostCeilings[downloadOriginKey(url)];
    final transfer = _learnedTransferCeilings[url];
    var ceiling = safeRequested;
    if (host != null && host < ceiling) ceiling = host;
    if (transfer != null && transfer < ceiling) ceiling = transfer;
    return ceiling;
  }

  int learnHostCeiling(String url, int ceiling) {
    final safe = _safeCeiling(ceiling);
    final key = downloadOriginKey(url);
    final previous = _learnedHostCeilings[key];
    final learned = previous == null || safe < previous ? safe : previous;
    _learnedHostCeilings[key] = learned;
    return learned;
  }

  int learnTransferCeiling(String url, int ceiling) {
    final safe = _safeCeiling(ceiling);
    final previous = _learnedTransferCeilings[url];
    final learned = previous == null || safe < previous ? safe : previous;
    _learnedTransferCeilings[url] = learned;
    return learned;
  }

  int? learnedHostCeilingFor(String url) =>
      _learnedHostCeilings[downloadOriginKey(url)];

  int? learnedTransferCeilingFor(String url) => _learnedTransferCeilings[url];

  bool sameOrigin(String first, String second) =>
      downloadOriginKey(first) == downloadOriginKey(second);

  int _safeCeiling(int value) => value
      .clamp(kDownloadPartsMin, kDownloadGlobalConnectionBudget)
      .toInt();
}
