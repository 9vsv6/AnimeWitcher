import 'dart:io';

import 'package:path/path.dart' as p;

import 'download_cleanup.dart';

/// How an interrupted download should be continued.
enum DownloadResumeStrategy {
  /// OS/plugin resume data is present — continue the same native task.
  nativeResume,

  /// A leftover dest/temp file has bytes that should be appended to.
  partialFile,

  /// Nothing to keep; start the transfer from byte 0.
  restartFromZero,
}

/// True when [existingPartialBytes] is a usable prefix of the download.
bool shouldResumeFromPartialBytes({
  required int existingPartialBytes,
  required int expectedBytes,
}) {
  if (existingPartialBytes <= 0) return false;
  if (expectedBytes > 0 && existingPartialBytes >= expectedBytes) {
    return false;
  }
  return true;
}

/// Prefer native resume data, then leftover bytes, then a full restart.
DownloadResumeStrategy chooseDownloadResumeStrategy({
  required bool canNativeResume,
  required int existingPartialBytes,
  required int expectedBytes,
}) {
  if (canNativeResume) return DownloadResumeStrategy.nativeResume;
  if (shouldResumeFromPartialBytes(
    existingPartialBytes: existingPartialBytes,
    expectedBytes: expectedBytes,
  )) {
    return DownloadResumeStrategy.partialFile;
  }
  return DownloadResumeStrategy.restartFromZero;
}

/// Continue a download that was killed mid-transfer. User-paused rows stay
/// paused, and tasks still owned by the native queue are left alone.
bool shouldAutoResumeInterruptedDownload({
  required bool wasRunningOrFailed,
  required bool userPaused,
  required bool stillInNativeQueue,
  bool queueWaiting = false,
}) {
  if (stillInNativeQueue || userPaused || queueWaiting) return false;
  return wasRunningOrFailed;
}

/// HTTP headers that continue a download from [existingBytes].
Map<String, String> rangeResumeHeaders({
  required Map<String, String> existing,
  required int existingBytes,
}) {
  final headers = <String, String>{};
  for (final entry in existing.entries) {
    if (entry.key.toLowerCase() == 'range') continue;
    headers[entry.key] = entry.value;
  }
  headers['Range'] = 'bytes=$existingBytes-';
  return headers;
}

/// The dest file or a sibling `.part` / `.tmp` / `.download` with the most bytes.
Future<File?> findPartialDownloadFile({
  required String destinationPath,
  List<String> tempSuffixes = kDownloadTempSuffixes,
}) async {
  File? best;
  var bestBytes = 0;

  Future<void> consider(File file) async {
    try {
      if (!await file.exists()) return;
      final bytes = await file.length();
      if (bytes <= bestBytes) return;
      best = file;
      bestBytes = bytes;
    } catch (_) {}
  }

  final dest = File(destinationPath);
  await consider(dest);
  final dir = dest.parent;
  final name = p.basename(destinationPath);
  for (final suffix in tempSuffixes) {
    await consider(File(p.join(dir.path, '$name$suffix')));
  }
  return best;
}

/// Appends [chunks] onto [dest] without rewriting the existing prefix.
Future<int> appendDownloadChunks({
  required File dest,
  required Stream<List<int>> chunks,
  required int existingBytes,
  void Function(int written)? onBytes,
}) async {
  await dest.parent.create(recursive: true);
  final raf = await dest.open(mode: FileMode.append);
  var written = existingBytes;
  try {
    await for (final chunk in chunks) {
      await raf.writeFrom(chunk);
      written += chunk.length;
      onBytes?.call(written);
    }
  } finally {
    await raf.close();
  }
  return written;
}

/// Resumes a paused download when resume data is available, otherwise starts
/// the same task again. Returns whether either operation was accepted.
Future<bool> resumeOrRestartDownload({
  required Future<bool> Function() canResume,
  required Future<bool> Function() resume,
  Future<bool> Function()? resumeFromPartial,
  required Future<bool> Function() restart,
}) async {
  try {
    if (await canResume() && await resume()) {
      return true;
    }
  } catch (_) {
    // A stale task can throw while its resume metadata is being inspected.
  }

  if (resumeFromPartial != null) {
    try {
      if (await resumeFromPartial()) {
        return true;
      }
    } catch (_) {
      // Leftover bytes can be unreadable or the host can reject Range.
    }
  }

  try {
    return await restart();
  } catch (_) {
    return false;
  }
}
