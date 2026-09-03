import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import '../domain/entity/multimedia_item.dart';

/// Video extensions that count as remaining episode files.
const Set<String> kDownloadVideoExtensions = {
  '.mp4',
  '.mkv',
  '.webm',
  '.avi',
};

const String kAppDownloadsRootMarker = 'AnimeWitcher/Downloads';

const List<String> kDownloadTempSuffixes = ['.part', '.tmp', '.download'];

/// Canonical episode identity: [DownloadTask.metaData], which is set to
/// `episode.url` (not `taskId`).
String downloadTrackingUrl(Task task) {
  final meta = task.metaData.trim();
  if (meta.isNotEmpty) return meta;
  return task.url.trim();
}

/// Identity for one downloaded episode (or a movie with no episode).
///
/// Canonical key is `episode.url`, which is stored on the task as
/// [Task.metaData]. `taskId` is not an identity.
String downloadIdentityKey(MultimediaItem item, Episode? episode) {
  final episodeUrl = episode?.url.trim() ?? '';
  if (episodeUrl.isNotEmpty) return episodeUrl;
  return item.url.trim();
}

/// Directory + filename as stored on the task, independent of Unicode form.
String downloadTaskFileKey(Task task) {
  final directory = task.directory.replaceAll('\\', '/').trim();
  final filename = task.filename.trim();
  if (filename.isEmpty) return '';
  return '$directory|$filename';
}

bool metadataMatchesDownload({
  required MultimediaItem item,
  Episode? episode,
  required MultimediaItem candidateItem,
  Episode? candidateEpisode,
}) {
  return downloadIdentityKey(item, episode) ==
      downloadIdentityKey(candidateItem, candidateEpisode);
}

bool taskMatchesDownloadFile({
  required Task task,
  required String filename,
  required String directory,
}) {
  if (task.filename.trim().isEmpty) return false;
  if (task.filename.trim() != filename.trim()) return false;
  final a = task.directory.replaceAll('\\', '/').trim();
  final b = directory.replaceAll('\\', '/').trim();
  if (a == b) return true;
  if (a.isEmpty || b.isEmpty) return false;
  return p.normalize(a) == p.normalize(b) || a.endsWith(b) || b.endsWith(a);
}

bool shouldCancelDownload(TaskStatus status) {
  switch (status) {
    case TaskStatus.running:
    case TaskStatus.enqueued:
    case TaskStatus.paused:
    case TaskStatus.waitingToRetry:
      return true;
    case TaskStatus.complete:
    case TaskStatus.canceled:
    case TaskStatus.failed:
    case TaskStatus.notFound:
      return false;
  }
}

enum CompleteDownloadAction { reuse, dropAndEnqueue, enqueue }

/// How [DownloadService.startDownload] should treat an existing complete record.
CompleteDownloadAction decideCompleteDownloadAction({
  required bool hasCompleteRecord,
  required bool fileExists,
}) {
  if (!hasCompleteRecord) return CompleteDownloadAction.enqueue;
  if (fileExists) return CompleteDownloadAction.reuse;
  return CompleteDownloadAction.dropAndEnqueue;
}

/// Prefer the task's own path; fall back to label reconstruction.
///
/// Order: existing task file, then [File] from `task.filePath()` when that
/// path exists (or `exists()` throws), then reconstructed labels, then the
/// path [File] even if `exists()` was false so delete can still retry.
Future<File?> resolveDownloadFileToDelete({
  required Future<File?> Function() fromTask,
  required Future<String?> Function() taskFilePath,
  required Future<File?> Function() fromLabels,
}) async {
  final taskFile = await fromTask();
  if (taskFile != null) return taskFile;
  final path = await taskFilePath();
  File? pathFile;
  if (path != null && path.isNotEmpty) {
    pathFile = File(path);
    try {
      if (await pathFile.exists()) return pathFile;
    } catch (_) {
      return pathFile;
    }
  }
  final labels = await fromLabels();
  if (labels != null) return labels;
  return pathFile;
}

bool pathIsInsideAppDownloads(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains(kAppDownloadsRootMarker);
}

bool pathIsAppDownloadsRoot(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.endsWith(kAppDownloadsRootMarker) ||
      normalized.endsWith('$kAppDownloadsRootMarker/');
}

/// The `<title>` directory under `AnimeWitcher/Downloads`, or null when the
/// file is not inside that tree (never returns the Downloads root itself).
Directory? seriesFolderForDownloadedFile(File file) {
  if (!pathIsInsideAppDownloads(file.path)) return null;
  var dir = file.parent;
  while (true) {
    if (pathIsAppDownloadsRoot(dir.path)) return null;
    if (!pathIsInsideAppDownloads(dir.path)) return null;
    if (pathIsAppDownloadsRoot(dir.parent.path)) return dir;
    if (dir.parent.path == dir.path) return null;
    dir = dir.parent;
  }
}

bool isDownloadVideoFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.startsWith('.')) return false;
  return kDownloadVideoExtensions.any(lower.endsWith);
}

Future<bool> directoryContainsVideoFiles(Directory directory) async {
  if (!await directory.exists()) return false;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    if (!isDownloadVideoFileName(p.basename(entity.path))) continue;
    try {
      if (await entity.length() > 0) return true;
    } catch (_) {
      continue;
    }
  }
  return false;
}

Future<void> _deleteEmptyAncestorsUpTo(
  Directory start,
  Directory stopAt,
) async {
  var dir = start;
  final stop = stopAt.path.replaceAll('\\', '/');
  while (true) {
    final current = dir.path.replaceAll('\\', '/');
    if (current == stop) return;
    if (!current.startsWith(stop)) return;
    if (!await dir.exists()) {
      dir = dir.parent;
      continue;
    }
    final children = await dir.list(followLinks: false).toList();
    if (children.isNotEmpty) return;
    await dir.delete();
    if (dir.parent.path == dir.path) return;
    dir = dir.parent;
  }
}

/// After a video is gone: wipe the series folder when no videos remain.
///
/// Leftover `.part` files, thumbs, and empty Season dirs must not keep
/// `AnimeWitcher/Downloads/<AnimeTitle>`. Never deletes the Downloads root.
Future<void> deleteSeriesFolderIfNoVideosRemain(File deletedFile) async {
  final seriesDir = seriesFolderForDownloadedFile(deletedFile);
  if (seriesDir == null) return;
  if (!await seriesDir.exists()) return;

  if (await directoryContainsVideoFiles(seriesDir)) {
    await _deleteEmptyAncestorsUpTo(deletedFile.parent, seriesDir);
    return;
  }

  await seriesDir.delete(recursive: true);
}

Future<void> deleteSiblingTempFiles(File file) async {
  final dir = file.parent;
  final name = p.basename(file.path);
  for (final suffix in kDownloadTempSuffixes) {
    final temp = File(p.join(dir.path, '$name$suffix'));
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}
  }
}

/// Retry `file.delete()` — Android public Downloads can fail once on
/// permission or a still-open handle, then succeed.
Future<bool> deleteFileWithRetry(File file, {int attempts = 3}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      if (!await file.exists()) return true;
      await file.delete();
      if (!await file.exists()) return true;
    } catch (_) {}
    if (i < attempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 40 * (i + 1)));
    }
  }
  try {
    return !await file.exists();
  } catch (_) {
    return false;
  }
}

/// Delete [file] (any status), sibling temps, then the series folder when
/// no videos remain.
Future<bool> deleteDownloadedVideo(File file) async {
  try {
    await deleteSiblingTempFiles(file);
    final deleted = await deleteFileWithRetry(file);
    await deleteSeriesFolderIfNoVideosRemain(file);
    return deleted;
  } catch (_) {
    return false;
  }
}
