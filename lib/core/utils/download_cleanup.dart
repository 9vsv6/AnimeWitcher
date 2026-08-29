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

/// Identity for one downloaded episode (or a movie with no episode).
///
/// Prefers [Episode.url] when present; otherwise item URL + episode number +
/// server name. Used to collapse duplicate FileDownloader rows that point at
/// the same episode.
String downloadIdentityKey(MultimediaItem item, Episode? episode) {
  final itemUrl = item.url.trim();
  if (episode == null) return itemUrl;
  final episodeUrl = episode.url.trim();
  if (episodeUrl.isNotEmpty) {
    return '$itemUrl|epurl:$episodeUrl';
  }
  return '$itemUrl|ep:${episode.episode}|srv:${episode.serverName}';
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

/// Prefer the task's own path; fall back to label reconstruction.
Future<File?> resolveDownloadFileToDelete({
  required Future<File?> Function() fromTask,
  required Future<File?> Function() fromLabels,
}) async {
  final taskFile = await fromTask();
  if (taskFile != null) return taskFile;
  return fromLabels();
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

/// Delete [file] then remove the series folder when it has no videos left.
Future<bool> deleteDownloadedVideo(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
    await deleteSeriesFolderIfNoVideosRemain(file);
    return true;
  } catch (_) {
    return false;
  }
}
