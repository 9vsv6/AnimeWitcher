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

  test('adds a fifty-percent safety margin to slower successful connections', () {
    expect(
      downloadRangeFastFailTimeout(const Duration(seconds: 4)),
      const Duration(seconds: 6),
    );
    expect(
      downloadRangeFastFailTimeout(const Duration(seconds: 10)),
      const Duration(seconds: 15),
    );
  });

  test('never becomes less tolerant than the previous thirty-second ceiling', () {
    expect(
      downloadRangeFastFailTimeout(const Duration(seconds: 25)),
      kDownloadRangeMaxFastFailTimeout,
    );
    expect(
      downloadRangeFastFailTimeout(const Duration(minutes: 2)),
      kDownloadRangeMaxFastFailTimeout,
    );
  });
}
