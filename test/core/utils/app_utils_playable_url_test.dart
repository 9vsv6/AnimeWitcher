import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/utils/app_utils.dart';

void main() {
  test('downloaded playback uses the requested local path without a lookup', () {
    const localPath = '/storage/emulated/0/AnimeWitcher/Downloads/ep.mp4';

    expect(AppUtils.isLocalFile(localPath), isTrue);
    expect(
      AppUtils.resolvePlayableUrl(
        requestedUrl: localPath,
        downloadedPath: '/other/reconstructed.mp4',
      ),
      AppUtils.normalizeUrl(localPath),
    );
  });

  test('episode URLs still prefer an on-disk download when one exists', () {
    const episodeUrl = 'https://animewitcher.com/watch/title/ep-3';
    const downloadedPath = '/data/user/0/app/files/ep-3.mp4';

    expect(
      AppUtils.resolvePlayableUrl(
        requestedUrl: episodeUrl,
        downloadedPath: downloadedPath,
      ),
      AppUtils.normalizeUrl(downloadedPath),
    );
  });

  test('streaming URLs stay remote when no download is present', () {
    const episodeUrl = 'https://animewitcher.com/watch/title/ep-3';

    expect(
      AppUtils.resolvePlayableUrl(
        requestedUrl: episodeUrl,
        downloadedPath: null,
      ),
      episodeUrl,
    );
  });
}
