import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces tiny range chunks before persisting progress', () {
    expect(
      shouldEmitDownloadRangeProgress(
        written: 128 * 1024,
        lastReportedWritten: 0,
        elapsed: const Duration(milliseconds: 100),
      ),
      isFalse,
    );
    expect(
      shouldEmitDownloadRangeProgress(
        written: kDownloadRangeProgressUpdateBytes,
        lastReportedWritten: 0,
        elapsed: const Duration(milliseconds: 1),
      ),
      isTrue,
    );
    expect(
      shouldEmitDownloadRangeProgress(
        written: 32 * 1024,
        lastReportedWritten: 0,
        elapsed: kDownloadRangeProgressUpdateInterval,
      ),
      isTrue,
    );
  });

  test('byte threshold is relative to the last emitted checkpoint', () {
    const previous = 8 * 1024 * 1024;
    expect(
      shouldEmitDownloadRangeProgress(
        written: previous + kDownloadRangeProgressUpdateBytes - 1,
        lastReportedWritten: previous,
        elapsed: const Duration(milliseconds: 50),
      ),
      isFalse,
    );
    expect(
      shouldEmitDownloadRangeProgress(
        written: previous + kDownloadRangeProgressUpdateBytes,
        lastReportedWritten: previous,
        elapsed: const Duration(milliseconds: 50),
      ),
      isTrue,
    );
  });
}
