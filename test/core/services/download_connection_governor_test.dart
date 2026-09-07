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
  });
}
