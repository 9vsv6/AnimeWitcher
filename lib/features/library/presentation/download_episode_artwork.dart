import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/domain/entity/multimedia_item.dart';

const String _downloadEpisodeArtworkDirectory = 'download_episode_artwork';
final Map<String, Future<File?>> _artworkWrites = <String, Future<File?>>{};

Future<File?> downloadedEpisodeArtworkFile(String taskId) async {
  if (kIsWeb || taskId.isEmpty) return null;
  final support = await getApplicationSupportDirectory();
  final key = sha1.convert(taskId.codeUnits).toString();
  return File(p.join(support.path, _downloadEpisodeArtworkDirectory, '$key.img'));
}

Future<File?> existingDownloadedEpisodeArtwork(String taskId) async {
  final file = await downloadedEpisodeArtworkFile(taskId);
  if (file == null) return null;
  try {
    return await file.exists() && await file.length() > 0 ? file : null;
  } catch (_) {
    return null;
  }
}

Future<File?> _persistDownloadedEpisodeArtwork(
  String taskId,
  String url,
) async {
  final target = await downloadedEpisodeArtworkFile(taskId);
  if (target == null) return null;
  final temp = File('${target.path}.tmp');
  try {
    await target.parent.create(recursive: true);
    final cached = await DefaultCacheManager()
        .getSingleFile(url)
        .timeout(const Duration(seconds: 20));
    if (!await cached.exists() || await cached.length() <= 0) return null;

    if (await temp.exists()) await temp.delete();
    await cached.copy(temp.path);
    if (!await temp.exists() || await temp.length() <= 0) return null;
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
    return target;
  } catch (_) {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}
    return null;
  }
}

/// Copies an episode still out of the temporary image cache into application
/// support storage. Completed downloads therefore keep their episode artwork
/// even after the normal image cache is cleared or the device is offline.
Future<File?> ensureDownloadedEpisodeArtwork({
  required String taskId,
  required Episode? episode,
}) async {
  final url = episode?.posterUrl?.trim() ?? '';
  if (kIsWeb || taskId.isEmpty || url.isEmpty) return null;

  final existing = await existingDownloadedEpisodeArtwork(taskId);
  if (existing != null) return existing;

  final inFlight = _artworkWrites[taskId];
  if (inFlight != null) return inFlight;

  final operation = _persistDownloadedEpisodeArtwork(taskId, url);
  _artworkWrites[taskId] = operation;
  try {
    return await operation;
  } finally {
    if (identical(_artworkWrites[taskId], operation)) {
      _artworkWrites.remove(taskId);
    }
  }
}

Future<void> deleteDownloadedEpisodeArtwork(String taskId) async {
  _artworkWrites.remove(taskId);
  final file = await downloadedEpisodeArtworkFile(taskId);
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
  } catch (_) {}
}
