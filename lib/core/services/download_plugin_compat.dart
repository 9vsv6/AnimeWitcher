import 'package:background_downloader/background_downloader.dart';

/// Narrow compatibility seam for background_downloader capabilities that are
/// still not exposed by its 9.6 public API.
///
/// Production download logic must not access `downloaderForTesting` directly.
/// Raw ResumeData is required by AnimeWitcher's iOS continued-processing queue
/// and one-time legacy multipart migration. Synthetic parent notifications are
/// needed because custom multipart parents are intentionally not enqueued as a
/// native FileDownloader task. Clearing notification configurations also has no
/// public 9.6 API: configureNotification asserts that at least one notification
/// is present, so an explicitly all-off preference must use this seam.
class BackgroundDownloaderCompat {
  const BackgroundDownloaderCompat._();

  static Future<ResumeData?> resumeDataForTaskId(String taskId) async {
    // ignore: invalid_use_of_visible_for_testing_member
    return FileDownloader().downloaderForTesting.getResumeData(taskId);
  }

  static void updateSyntheticNotification(Task task, TaskStatus status) {
    // ignore: invalid_use_of_visible_for_testing_member
    FileDownloader().downloaderForTesting.updateNotification(task, status);
  }

  static void clearNotificationConfigs() {
    // background_downloader 9.6's public configureNotification APIs require at
    // least one non-null notification and therefore cannot represent "off".
    // Keep this unsupported operation isolated here instead of leaking the
    // testing-only downloader surface into DownloadService.
    // ignore: invalid_use_of_visible_for_testing_member
    FileDownloader().downloaderForTesting.notificationConfigs.clear();
  }
}
