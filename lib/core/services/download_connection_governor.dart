import 'package:background_downloader/background_downloader.dart';

import 'download_parallel.dart';

/// Wait before cautiously testing one connection above a learned host ceiling.
/// The learned value is intentionally process-local, so this is a short-lived
/// recovery policy rather than permanent CDN profiling.
const Duration kDownloadHostProbeCooldown = Duration(minutes: 2);

/// A probe that survives this long without another host-pressure signal is
/// considered stable and becomes the new learned ceiling on the next transfer.
const Duration kDownloadHostProbeStabilityWindow = Duration(seconds: 45);

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
///
/// A host ceiling is not allowed to stay artificially low forever. After a
/// cooldown, exactly one transfer is allowed to probe one connection above the
/// learned value. Other sibling transfers keep the old safe ceiling while that
/// probe is settling. If no new host-pressure signal arrives during the
/// stability window, the probe is promoted on the next transfer. Any pressure
/// immediately discards the probe and restarts the cooldown.
class DownloadConnectionGovernor {
  DownloadConnectionGovernor({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, int> _learnedHostCeilings = <String, int>{};
  final Map<String, int> _learnedTransferCeilings = <String, int>{};
  final Map<String, _HostProbeState> _hostProbeStates =
      <String, _HostProbeState>{};

  /// Restore safe host ceilings learned during earlier app sessions.
  /// Existing in-process pressure always wins by keeping the lower ceiling.
  void seedHostCeilings(Map<String, int> ceilings) {
    final nextProbe = _now().add(kDownloadHostProbeCooldown);
    for (final entry in ceilings.entries) {
      final key = downloadOriginKey(entry.key);
      if (key.trim().isEmpty) continue;
      final safe = _safeCeiling(entry.value);
      final current = _learnedHostCeilings[key];
      _learnedHostCeilings[key] = current == null || safe < current
          ? safe
          : current;
      _hostProbeStates.putIfAbsent(
        key,
        () => _HostProbeState(nextProbeAt: nextProbe),
      );
    }
  }

  int connectionCeilingFor(String url, {required int requested}) {
    final safeRequested = requested
        .clamp(kDownloadPartsMin, kDownloadGlobalConnectionBudget)
        .toInt();
    final transfer = _learnedTransferCeilings[url];
    final transferBound = transfer != null && transfer < safeRequested
        ? transfer
        : safeRequested;
    final host = _hostCeilingFor(
      url,
      requested: safeRequested,
      effectiveRequested: transferBound,
    );

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

    // A fresh pressure signal invalidates any optimistic probe, even when the
    // computed fallback equals the already-learned ceiling.
    _hostProbeStates[key] = _HostProbeState(
      nextProbeAt: _now().add(kDownloadHostProbeCooldown),
    );
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

  int? _hostCeilingFor(
    String url, {
    required int requested,
    required int effectiveRequested,
  }) {
    final key = downloadOriginKey(url);
    var learned = _learnedHostCeilings[key];
    if (learned == null) return null;

    final now = _now();
    final state = _hostProbeStates.putIfAbsent(
      key,
      () => _HostProbeState(
        nextProbeAt: now.add(kDownloadHostProbeCooldown),
      ),
    );

    final probeCeiling = state.probeCeiling;
    final probeStartedAt = state.probeStartedAt;
    if (probeCeiling != null &&
        probeStartedAt != null &&
        !now.isBefore(
          probeStartedAt.add(kDownloadHostProbeStabilityWindow),
        )) {
      if (probeCeiling > learned) {
        learned = _safeCeiling(probeCeiling);
        _learnedHostCeilings[key] = learned;
      }
      state
        ..probeCeiling = null
        ..probeStartedAt = null
        ..nextProbeAt = now.add(kDownloadHostProbeCooldown);
    }

    // Only one transfer gets the extra connection. A URL-specific transient
    // cap can also block a host probe; do not mark a probe as in-flight when
    // that transfer could not actually exercise it.
    if (state.probeCeiling == null &&
        learned < effectiveRequested &&
        !now.isBefore(state.nextProbeAt)) {
      final candidate = learned + 1;
      final probe = candidate < effectiveRequested
          ? candidate
          : effectiveRequested;
      if (probe > learned) {
        state
          ..probeCeiling = probe
          ..probeStartedAt = now;
        return probe < requested ? probe : requested;
      }
    }

    return learned < requested ? learned : requested;
  }

  int _safeCeiling(int value) => value
      .clamp(kDownloadPartsMin, kDownloadGlobalConnectionBudget)
      .toInt();
}

class _HostProbeState {
  _HostProbeState({required this.nextProbeAt});

  DateTime nextProbeAt;
  int? probeCeiling;
  DateTime? probeStartedAt;
}
