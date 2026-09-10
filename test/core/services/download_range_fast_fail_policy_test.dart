import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the tolerant timeout until a host has a successful baseline', () {
    expect(
      downloadRangeFastFailTimeout(null),
      kDownloadRangeDefaultResponseTimeout,
    );
    expect(
      downloadRangeFastFailTimeout(Duration.zero),
      kDownloadRangeDefaultResponseTimeout,
    );
  });

  test('uses a three-second floor for normally fast origins', () {
    expect(
      downloadRangeFastFailTimeout(const Duration(milliseconds: 400)),
      kDownloadRangeMinFastFailTimeout,
    );
    expect(
      downloadRangeFastFailTimeout(const Duration(seconds: 2)),
      kDownloadRangeMinFastFailTimeout,
    );
  });

  test(
    'adds a fifty-percent safety margin to slower successful connections',
    () {
      expect(
        downloadRangeFastFailTimeout(const Duration(seconds: 4)),
        const Duration(seconds: 6),
      );
      expect(
        downloadRangeFastFailTimeout(const Duration(seconds: 10)),
        const Duration(seconds: 15),
      );
    },
  );

  test('only validated HTTP 206 ranges train the fast-fail baseline', () {
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 503,
        requestedRange: 'bytes=100-199',
        contentRange: null,
      ),
      isFalse,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 206,
        requestedRange: 'bytes=100-199',
        contentRange: 'bytes 100-199/1000',
      ),
      isTrue,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 206,
        requestedRange: 'bytes=100-199',
        contentRange: 'bytes 101-200/1000',
      ),
      isFalse,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 200,
        requestedRange: 'bytes=100-',
        contentRange: null,
      ),
      isFalse,
    );
  });

  test(
    'never becomes less tolerant than the previous thirty-second ceiling',
    () {
      expect(
        downloadRangeFastFailTimeout(const Duration(seconds: 25)),
        kDownloadRangeMaxFastFailTimeout,
      );
      expect(
        downloadRangeFastFailTimeout(const Duration(minutes: 2)),
        kDownloadRangeMaxFastFailTimeout,
      );
    },
  );
}
