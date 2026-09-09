import 'package:background_downloader/background_downloader.dart';

/// Narrow compatibility seam for background_downloader capabilities that are
/// still not exposed by its 9.6 public API.
///
/// Production download logic must not access `downloaderForTesting` directly.
/// Raw ResumeData is required by AnimeWitcher's iOS continued-processing queue
/// and one-time legacy multipart migration. Synthetic parent notifications are
/// needed because custom multipart parents are intentionally not enqueued as a
/// native FileDownloader task.
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
}
