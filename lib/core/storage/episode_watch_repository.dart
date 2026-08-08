import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entity/multimedia_item.dart';
import 'history_repository.dart';
import 'storage_service.dart';

final episodeWatchRevisionProvider =
    NotifierProvider<EpisodeWatchRevision, int>(EpisodeWatchRevision.new);

class EpisodeWatchRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final episodeWatchRepositoryProvider = Provider<EpisodeWatchRepository>((ref) {
  return EpisodeWatchRepository(
    ref.watch(storageServiceProvider),
    ref.watch(historyRepositoryProvider),
    () => ref.read(episodeWatchRevisionProvider.notifier).bump(),
  );
});

class EpisodeWatchRepository {
  EpisodeWatchRepository(
    this._storageService,
    this._historyRepository,
    this._notifyChanged,
  );

  final StorageService _storageService;
  final HistoryRepository _historyRepository;
  final void Function() _notifyChanged;

  static const String _storageKey = 'episode_watch_overrides_v1';

  Map<String, bool>? _cachedOverrides;

  String _canonicalMainUrl(String mainUrl) {
    final value = mainUrl.trim();
    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    // Search/home results can carry the original hit query while the details
    // page is reopened with the canonical AnimeWitcher route. Those URLs
    // identify the same anime, so query data must not affect watch state.
    final host = uri.host.toLowerCase();
    if ((host == 'animewitcher.com' || host == 'www.animewitcher.com') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'watch') {
      return uri.replace(query: '', fragment: '').toString();
    }
    return value;
  }

  String _stableEpisodeId(Episode episode) {
    final episodeUrl = episode.url.trim();
    if (episodeUrl.isNotEmpty) {
      // Episode URLs are the provider's actual episode identity. Using the
      // season/number pair here caused a watched episode to disappear when
      // AniZip enrichment changed the season value or when AnimeWitcher
      // returned a duplicate/renumbered document.
      return ['url', episodeUrl, episode.dubStatus.name].join(':');
    }

    return [
      'number',
      episode.season,
      episode.episode,
      episode.name,
      episode.dubStatus.name,
    ].join(':');
  }

  String _episodeKey(Episode episode) {
    // v2 intentionally keys a non-empty episode by its own stable URL rather
    // than by the transient parent item URL and mutable metadata fields.
    final identity = 'episode_watch_v2|${_stableEpisodeId(episode)}';
    return sha256.convert(utf8.encode(identity)).toString();
  }

  String _legacyEpisodeKey(String mainUrl, Episode episode) {
    final stableEpisodeId = episode.episode > 0
        ? [episode.season, episode.episode, episode.dubStatus.name].join(':')
        : [episode.url, episode.name, episode.dubStatus.name].join(':');

    return sha256
        .convert(
          utf8.encode('${_canonicalMainUrl(mainUrl)}|$stableEpisodeId'),
        )
        .toString();
  }

  Map<String, bool> _readOverrides() {
    final cached = _cachedOverrides;
    if (cached != null) {
      return cached;
    }

    final raw = _storageService.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return _cachedOverrides = <String, bool>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return _cachedOverrides = <String, bool>{};
      }

      return _cachedOverrides = decoded.map<String, bool>(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } catch (_) {
      return _cachedOverrides = <String, bool>{};
    }
  }

  Future<void> _persist(Map<String, bool> overrides) async {
    _cachedOverrides = overrides;
    await _storageService.setString(_storageKey, jsonEncode(overrides));
    _notifyChanged();
  }

  bool? getExplicitState(String mainUrl, Episode episode) {
    final overrides = _readOverrides();
    final current = overrides[_episodeKey(episode)];
    if (current != null) return current;

    // Read states written by v1 so existing users do not lose their watched
    // marks after upgrading. New writes use the URL-based v2 identity above.
    return overrides[_legacyEpisodeKey(mainUrl, episode)];
  }

  bool isWatched(String mainUrl, Episode episode) {
    final explicit = getExplicitState(mainUrl, episode);
    if (explicit != null) {
      return explicit;
    }

    final position = _historyRepository.getEpisodePosition(
      episode.url,
      mainUrl: mainUrl,
      season: episode.season,
      episode: episode.episode,
    );
    final duration = _historyRepository.getEpisodeDuration(
      episode.url,
      mainUrl: mainUrl,
      season: episode.season,
      episode: episode.episode,
    );

    return duration > 0 && position / duration >= 0.90;
  }

  Future<void> setWatched(String mainUrl, Episode episode, bool watched) async {
    final overrides = Map<String, bool>.from(_readOverrides());
    overrides[_episodeKey(episode)] = watched;
    await _persist(overrides);
  }

  Future<void> setManyWatched(
    String mainUrl,
    Iterable<Episode> episodes,
    bool watched,
  ) async {
    final overrides = Map<String, bool>.from(_readOverrides());

    for (final episode in episodes) {
      overrides[_episodeKey(episode)] = watched;
    }

    await _persist(overrides);
  }
}
