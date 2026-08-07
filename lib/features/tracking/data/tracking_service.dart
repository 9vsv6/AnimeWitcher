import '../../../core/domain/entity/multimedia_item.dart';
import '../domain/sync_progress_item.dart';

abstract class TrackingService {
  String get name;
  String get idPrefix; // e.g. "mal", "anilist"
  String get mainUrl;

  // Auth
  Future<bool> login({
    Future<void> Function(String url, String code)? onDeviceCodeGenerated,
    Future<void> Function(String url)? onWebViewRequested,
    bool Function()? isCancelled,
  });
  Future<void> logout();
  Future<bool> get isLoggedIn;

  // Search & ID resolution
  Future<List<MultimediaItem>> search(String query);

  /// Fetches tracker IDs associated with this item when available.
  Future<Map<String, String>> syncIds(MultimediaItem item);

  // Tracking actions
  Future<bool> markWatched(
    MultimediaItem item,
    Episode? episode, {
    Map<String, String>? resolvedIds,
  });
  Future<bool> scrobbleStart(
    MultimediaItem item,
    Episode? episode,
    double progress, {
    Map<String, String>? resolvedIds,
  });
  Future<bool> scrobblePause(
    MultimediaItem item,
    Episode? episode,
    double progress, {
    Map<String, String>? resolvedIds,
  });
  Future<bool> scrobbleStop(
    MultimediaItem item,
    Episode? episode,
    double progress, {
    Map<String, String>? resolvedIds,
  });
  Future<bool> addToPlanToWatch(
    MultimediaItem item, {
    Map<String, String>? resolvedIds,
  });

  /// Pull playback progress for syncing across devices
  Future<List<SyncProgressItem>> pullPlaybackProgress();

  /// Remove a playback progress item by its tracking-specific ID
  Future<bool> removePlaybackProgress(String id) async => false;
}
