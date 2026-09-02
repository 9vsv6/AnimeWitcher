import 'dart:io';

import 'package:path/path.dart' as p;

import 'download_cleanup.dart';

/// How an interrupted download should be continued.
enum DownloadResumeStrategy {
  /// OS/plugin resume data is present — continue the same native task.
  nativeResume,

  /// A leftover dest/temp file has bytes that should be appended to.
  partialFile,

  /// Legacy sentinel kept for compatibility. Existing downloads never select
  /// this automatically; only a brand-new download may start from byte 0.
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

/// Prefer native resume data, then leftover bytes. Restart from 0 only when
/// there is nothing to keep — never when pause/fail/kill left progress.
DownloadResumeStrategy chooseDownloadResumeStrategy({
  required bool canNativeResume,
  required int existingPartialBytes,
  required int expectedBytes,
  double savedProgress = 0,
}) {
  if (canNativeResume) return DownloadResumeStrategy.nativeResume;
  if (shouldResumeFromPartialBytes(
    existingPartialBytes: existingPartialBytes,
    expectedBytes: expectedBytes,
  )) {
    return DownloadResumeStrategy.partialFile;
  }
  // Even with no discoverable bytes, an existing download must remain
  // resumable/paused rather than silently becoming a fresh transfer.
  return DownloadResumeStrategy.partialFile;
}

/// Fresh GET from byte 0 is allowed only when nothing has been saved.
/// Pause, fail, kill, and unpause must never take this path.
bool shouldRestartDownloadFromZero({
  required int existingPartialBytes,
  required int expectedBytes,
  double savedProgress = 0,
}) {
  // Existing rows are never allowed to restart automatically. The only
  // byte-zero path is explicit user deletion followed by a new download.
  return false;
}

/// Unpause / retry / overlay ticks must not flash 0% over saved bytes.
double keepLastKnownDownloadProgress({
  required double incoming,
  double? lastKnown,
}) {
  if (incoming > 0 && incoming <= 1) return incoming;
  final last = lastKnown ?? 0;
  if (last > 0 && last <= 1 && incoming <= 0) return last;
  if (incoming < 0) return last > 0 ? last : 0;
  return incoming.clamp(0.0, 1.0);
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

/// Resumes a paused/failed/killed download. Never starts over from byte 0
/// when resume data, a partial file, or saved progress exists.
Future<bool> resumeOrRestartDownload({
  required Future<bool> Function() canResume,
  required Future<bool> Function() resume,
  Future<bool> Function()? resumeFromPartial,
  required Future<bool> Function() restart,
  double savedProgress = 0,
  int existingPartialBytes = 0,
  int expectedBytes = -1,
}) async {
  try {
    if (await canResume() && await resume()) {
      return true;
    }
  } catch (_) {
    // A stale native resume blob must never trigger a fresh byte-zero GET.
  }

  if (resumeFromPartial != null) {
    try {
      if (await resumeFromPartial()) {
        return true;
      }
    } catch (_) {
      // Keep the preserved bytes untouched if the host rejects Range or the
      // partial file cannot be resumed right now.
    }
  }

  // Existing downloads never restart automatically, even when the saved
  // progress is 0 or resume metadata is missing. `restart` is intentionally
  // not called; a fresh transfer is created only after explicit user deletion
  // followed by a new startDownload action.
  return false;
}
