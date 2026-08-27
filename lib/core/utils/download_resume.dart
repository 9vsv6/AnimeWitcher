/// Resumes a paused download when resume data is available, otherwise starts
/// the same task again. Returns whether either operation was accepted.
Future<bool> resumeOrRestartDownload({
  required Future<bool> Function() canResume,
  required Future<bool> Function() resume,
  required Future<bool> Function() restart,
}) async {
  try {
    if (await canResume() && await resume()) {
      return true;
    }
  } catch (_) {
    // A stale task can throw while its resume metadata is being inspected.
  }

  try {
    return await restart();
  } catch (_) {
    return false;
  }
}
