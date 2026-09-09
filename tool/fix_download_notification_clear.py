from pathlib import Path

path = Path('lib/core/services/download_service.dart')
text = path.read_text()
old = """    // Clear any legacy default config through the public API so internal
    // multipart children never inherit a user-visible notification.
    FileDownloader().configureNotification(progressBar: false);
    if (shouldClearDownloadNotificationConfigs(prefs)) {
      FileDownloader().configureNotificationForGroup(
        kLogicalDownloadGroup,
        progressBar: false,
      );
      return;
    }
"""
new = """    // background_downloader 9.6 cannot clear notification configs through
    // its public configureNotification API because an empty config asserts.
    // Keep that unsupported operation inside the compatibility seam.
    BackgroundDownloaderCompat.clearNotificationConfigs();
    if (shouldClearDownloadNotificationConfigs(prefs)) return;
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'notification clear block: expected 1 match, found {count}')
path.write_text(text.replace(old, new, 1))
print('notification clear patch applied')
