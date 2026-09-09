import 'package:animewitcher/core/services/download_transport.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal DownloadTask routes through native single transport', () {
    final task = DownloadTask(
      taskId: 'single-1',
      url: 'https://example.test/episode.mp4',
      filename: 'episode.mp4',
    );
    expect(isNativeSingleDownloadTask(task), isTrue);
  });

  test('ParallelDownloadTask stays owned by multipart engine', () {
    final task = ParallelDownloadTask(
      taskId: 'parallel-1',
      url: 'https://example.test/episode.mp4',
      filename: 'episode.mp4',
      chunks: 4,
    );
    expect(isNativeSingleDownloadTask(task), isFalse);
  });

  test('anime transfers request user initiated and large file hints', () {
    final hints = animeDownloadTransferHints(expectedBytes: 900 * 1024 * 1024);
    expect(hints, contains(TransferHint.userInitiated));
    expect(hints, contains(TransferHint.largeFile));
    expect(hints, isNot(contains(TransferHint.smallFile)));
  });
}
