import 'package:animewitcher/core/services/download_connection_governor.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DownloadTask task([String url = 'https://cdn.example.com/video']) =>
      DownloadTask(url: url);

  group('download connection pressure', () {
    test('treats 429 and overload gateway responses as host pressure', () {
      for (final code in <int>[408, 425, 429, 502, 503, 504, 509]) {
        final update = TaskStatusUpdate(
          task(),
          TaskStatus.waitingToRetry,
          TaskHttpException('pressure', code),
        );
        expect(
          downloadConnectionPressureFor(update),
          DownloadConnectionPressure.host,
          reason: 'HTTP $code should teach the host ceiling',
        );
      }
    });

    test('generic 5xx and socket failures only back off this transfer', () {
      expect(
        downloadConnectionPressureFor(
          TaskStatusUpdate(
            task(),
            TaskStatus.waitingToRetry,
            TaskHttpException('server error', 500),
          ),
        ),
        DownloadConnectionPressure.transient,
      );
      expect(
        downloadConnectionPressureFor(
          TaskStatusUpdate(
            task(),
            TaskStatus.waitingToRetry,
            TaskConnectionException('socket reset'),
          ),
        ),
        DownloadConnectionPressure.transient,
      );
    });

    test('does not back off normal statuses or permanent client errors', () {
      expect(
        downloadConnectionPressureFor(
          TaskStatusUpdate(task(), TaskStatus.running),
        ),
        DownloadConnectionPressure.none,
      );
      expect(
        downloadConnectionPressureFor(
          TaskStatusUpdate(
            task(),
            TaskStatus.failed,
            TaskHttpException('forbidden', 403),
          ),
        ),
        DownloadConnectionPressure.none,
      );
    });
  });

  group('download connection governor', () {
    test('host pressure is shared while transient pressure stays URL-local', () {
      final governor = DownloadConnectionGovernor();
      const first = 'https://cdn.example.com/a.mp4';
      const second = 'https://cdn.example.com/b.mp4';
      const other = 'https://other.example.com/c.mp4';

      expect(governor.connectionCeilingFor(first, requested: 16), 16);
      expect(governor.learnTransferCeiling(first, 8), 8);
      expect(governor.connectionCeilingFor(first, requested: 16), 8);
      expect(governor.connectionCeilingFor(second, requested: 16), 16);

      expect(governor.learnHostCeiling(first, 4), 4);
      expect(governor.connectionCeilingFor(first, requested: 16), 4);
      expect(governor.connectionCeilingFor(second, requested: 16), 4);
      expect(governor.connectionCeilingFor(other, requested: 16), 16);
    });

    test('learned ceilings only move downward and respect requested count', () {
      final governor = DownloadConnectionGovernor();
      const url = 'https://cdn.example.com/a.mp4';

      governor.learnHostCeiling(url, 6);
      governor.learnHostCeiling(url, 10);
      expect(governor.learnedHostCeilingFor(url), 6);
      expect(governor.connectionCeilingFor(url, requested: 3), 3);
    });

    test('only one transfer probes one connection above the learned host cap', () {
      var now = DateTime.utc(2026, 9, 7, 12);
      final governor = DownloadConnectionGovernor(now: () => now);
      const first = 'https://cdn.example.com/a.mp4';
      const second = 'https://cdn.example.com/b.mp4';

      governor.learnHostCeiling(first, 4);
      now = now.add(kDownloadHostProbeCooldown);

      expect(governor.connectionCeilingFor(first, requested: 16), 5);
      expect(governor.connectionCeilingFor(second, requested: 16), 4);
      expect(governor.learnedHostCeilingFor(first), 4);
    });

    test('a stable probe is promoted, then waits before probing again', () {
      var now = DateTime.utc(2026, 9, 7, 12);
      final governor = DownloadConnectionGovernor(now: () => now);
      const first = 'https://cdn.example.com/a.mp4';
      const second = 'https://cdn.example.com/b.mp4';

      governor.learnHostCeiling(first, 4);
      now = now.add(kDownloadHostProbeCooldown);
      expect(governor.connectionCeilingFor(first, requested: 16), 5);

      now = now.add(kDownloadHostProbeStabilityWindow);
      expect(governor.connectionCeilingFor(second, requested: 16), 5);
      expect(governor.learnedHostCeilingFor(first), 5);

      // Promotion starts a fresh cooldown instead of immediately jumping to 6.
      expect(governor.connectionCeilingFor(first, requested: 16), 5);
      now = now.add(kDownloadHostProbeCooldown);
      expect(governor.connectionCeilingFor(first, requested: 16), 6);
    });

    test('new host pressure rejects an in-flight probe and restarts cooldown', () {
      var now = DateTime.utc(2026, 9, 7, 12);
      final governor = DownloadConnectionGovernor(now: () => now);
      const url = 'https://cdn.example.com/a.mp4';

      governor.learnHostCeiling(url, 4);
      now = now.add(kDownloadHostProbeCooldown);
      expect(governor.connectionCeilingFor(url, requested: 16), 5);

      // The probe hit pressure. Even though the fallback is the same learned
      // value, it must invalidate the optimistic +1 trial.
      expect(governor.learnHostCeiling(url, 4), 4);
      now = now.add(kDownloadHostProbeStabilityWindow);
      expect(governor.connectionCeilingFor(url, requested: 16), 4);

      now = now.add(
        kDownloadHostProbeCooldown - kDownloadHostProbeStabilityWindow,
      );
      expect(governor.connectionCeilingFor(url, requested: 16), 5);
    });

    test('a URL-local cap cannot accidentally consume the shared host probe', () {
      var now = DateTime.utc(2026, 9, 7, 12);
      final governor = DownloadConnectionGovernor(now: () => now);
      const capped = 'https://cdn.example.com/a.mp4';
      const sibling = 'https://cdn.example.com/b.mp4';

      governor.learnHostCeiling(capped, 4);
      governor.learnTransferCeiling(capped, 2);
      now = now.add(kDownloadHostProbeCooldown);

      expect(governor.connectionCeilingFor(capped, requested: 16), 2);
      // The capped URL could not exercise connection 5, so another sibling is
      // still allowed to claim the single shared probe.
      expect(governor.connectionCeilingFor(sibling, requested: 16), 5);
    });
  });
}
