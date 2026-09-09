from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)

path = Path('lib/core/services/download_service.dart')
text = path.read_text()
text = replace_one(
    text,
    "import 'download_url_refresh.dart';\nimport 'download_transport.dart';",
    "import 'download_url_refresh.dart';\nimport 'download_plugin_compat.dart';\nimport 'download_transport.dart';",
    'compat import',
)
text = replace_one(
    text,
    "        // ignore: invalid_use_of_visible_for_testing_member\n        FileDownloader().downloaderForTesting.updateNotification(\n          update.task,\n          update.status,\n        );",
    "        BackgroundDownloaderCompat.updateSyntheticNotification(\n          update.task,\n          update.status,\n        );",
    'synthetic notification compat',
)
text = replace_one(
    text,
    "    // ignore: invalid_use_of_visible_for_testing_member\n    FileDownloader().downloaderForTesting.notificationConfigs.clear();\n    if (shouldClearDownloadNotificationConfigs(prefs)) return;",
    """    // Clear any legacy default config through the public API so internal
    // multipart children never inherit a user-visible notification.
    FileDownloader().configureNotification(progressBar: false);
    if (shouldClearDownloadNotificationConfigs(prefs)) {
      FileDownloader().configureNotificationForGroup(
        kLogicalDownloadGroup,
        progressBar: false,
      );
      return;
    }""",
    'public notification reset',
)
text = replace_one(
    text,
    """      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final resume = await FileDownloader().downloaderForTesting
            .getResumeData(id);
        if (resume != null && resume.data.isNotEmpty) {
          waiters[i] = {...waiters[i], 'resumeDataBase64': resume.data};
        }
      } catch (_) {}""",
    """      try {
        final resume = await BackgroundDownloaderCompat.resumeDataForTaskId(id);
        if (resume != null && resume.data.isNotEmpty) {
          waiters[i] = {...waiters[i], 'resumeDataBase64': resume.data};
        }
      } catch (_) {}""",
    'snapshot resume compat',
)
old_config = """  String? _notificationConfigJson(DownloadTask task) {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final config = FileDownloader().downloaderForTesting
          .notificationConfigForTask(task);
      if (config == null) return null;
      return jsonEncode(config.toJson());
    } catch (_) {
      return null;
    }
  }
"""
new_config = """  String? _notificationConfigJson(DownloadTask task) {
    try {
      final prefs = _ref
          .read(storageServiceProvider)
          .getDownloadNotificationPrefs();
      if (shouldClearDownloadNotificationConfigs(prefs)) return null;
      const title = '{displayName}';
      final config = TaskNotificationConfig(
        taskOrGroup: task,
        running: downloadNotificationIfEnabled(
          enabled: prefs.running,
          title: title,
          body: Platform.isIOS
              ? kDownloadRunningNotificationBodyIos
              : kDownloadRunningNotificationBodyAndroid,
        ),
        complete: downloadNotificationIfEnabled(
          enabled: prefs.complete,
          title: title,
          body: kDownloadCompleteNotificationBody,
        ),
        error: downloadNotificationIfEnabled(
          enabled: prefs.error,
          title: title,
          body: kDownloadParkedNotificationBody,
        ),
        paused: downloadNotificationIfEnabled(
          enabled: prefs.paused,
          title: title,
          body: kDownloadParkedNotificationBody,
        ),
        canceled: downloadNotificationIfEnabled(
          enabled: prefs.canceled,
          title: title,
          body: kDownloadCanceledNotificationBody,
        ),
        progressBar: !Platform.isIOS && prefs.running,
      );
      return jsonEncode(config.toJson());
    } catch (_) {
      return null;
    }
  }
"""
text = replace_one(text, old_config, new_config, 'public notification json')
text = replace_one(
    text,
    """      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final resume = await FileDownloader().downloaderForTesting
            .getResumeData(task.taskId);
        if (resume != null && resume.data.isNotEmpty) {
          payload['resumeDataBase64'] = resume.data;
        }
      } catch (_) {}""",
    """      try {
        final resume = await BackgroundDownloaderCompat.resumeDataForTaskId(
          task.taskId,
        );
        if (resume != null && resume.data.isNotEmpty) {
          payload['resumeDataBase64'] = resume.data;
        }
      } catch (_) {}""",
    'waiter resume compat',
)
text = replace_one(
    text,
    """      // ignore: invalid_use_of_visible_for_testing_member
      final data = await FileDownloader().downloaderForTesting.getResumeData(
        task.taskId,
      );""",
    """      final data = await BackgroundDownloaderCompat.resumeDataForTaskId(
        task.taskId,
      );""",
    'legacy multipart resume compat',
)
text = replace_one(
    text,
    """      canResume: () async {
        // Unlike taskCanResume, a stored-data lookup cannot wait forever for
        // a response from a task that died before its first network callback.
        // ignore: invalid_use_of_visible_for_testing_member
        return await FileDownloader().downloaderForTesting.getResumeData(
              task.taskId,
            ) !=
            null;
      },""",
    """      canResume: () async {
        try {
          return await FileDownloader()
              .taskCanResume(task)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          return false;
        }
      },""",
    'public normal resumability',
)
text = replace_one(
    text,
    """    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final resume = await FileDownloader().downloaderForTesting.getResumeData(
        task.taskId,
      );
      if (resume != null && await FileDownloader().resume(task)) return true;
    } catch (_) {
      // A stale native checkpoint must not prevent the disk-prefix fallback.
    }""",
    """    try {
      final canResume = await FileDownloader()
          .taskCanResume(task)
          .timeout(const Duration(seconds: 3));
      if (canResume && await FileDownloader().resume(task)) return true;
    } catch (_) {
      // A stale native checkpoint must not prevent the disk-prefix fallback.
    }""",
    'public child resumability',
)
path.write_text(text)

# Architectural guard: production service may not regress to internal plugin API.
test = Path('test/core/services/download_internal_api_usage_test.dart')
test.write_text("""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DownloadService never accesses downloaderForTesting directly', () {
    final service = File('lib/core/services/download_service.dart').readAsStringSync();
    expect(service, isNot(contains('downloaderForTesting')));
  });

  test('internal plugin access stays isolated in one compatibility seam', () {
    final compat = File('lib/core/services/download_plugin_compat.dart')
        .readAsStringSync();
    expect(RegExp('downloaderForTesting').allMatches(compat).length, 2);
  });
}
""")
print('background downloader public API cleanup applied')
