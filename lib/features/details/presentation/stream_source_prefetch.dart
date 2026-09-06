/// Warms the next episode's source list while the current one is still
/// playing.
///
/// Picking "next" ran the whole chain from cold: ask the provider for the
/// episode's sources, wait, then show the picker. That wait lands at exactly
/// the moment a viewer has decided to keep watching. The list is cheap to
/// fetch and stable for the life of an episode page, so it can be fetched
/// early and handed over instantly.
///
/// Only the *list* is cached, never a resolved playback URL: those are signed
/// and short-lived, and serving a stale one would fail playback rather than
/// speed it up.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';

part 'stream_source_prefetch.g.dart';

class StreamSourcePrefetch {
  StreamSourcePrefetch();

  /// Long enough to cover the credits of an episode, short enough that a
  /// provider's own changes are picked up on the next session.
  static const Duration ttl = Duration(minutes: 10);

  /// One episode ahead is all that is ever needed; the cap is for safety.
  static const int maxEntries = 4;

  final Map<String, _Entry> _entries = <String, _Entry>{};

  /// Starts a fetch for [episodeUrl] and forgets the result if it fails.
  ///
  /// Fire and forget: a warm that errors must not surface anything, because
  /// nobody asked for it yet. The real request will report its own failure.
  void warm(AnimeWitcherProvider provider, String episodeUrl) {
    if (episodeUrl.trim().isEmpty) return;
    if (_live(episodeUrl) != null) return;
    unawaited(
      sources(provider, episodeUrl).catchError((_) {
        _entries.remove(episodeUrl);
        return const <StreamResult>[];
      }),
    );
  }

  /// The sources for [episodeUrl], from the warm fetch when one is in flight
  /// or already done.
  Future<List<StreamResult>> sources(
    AnimeWitcherProvider provider,
    String episodeUrl,
  ) {
    final live = _live(episodeUrl);
    if (live != null) return live.future;

    final future = provider.loadStreamSources(episodeUrl);
    _entries[episodeUrl] = _Entry(future, DateTime.now().add(ttl));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }

  /// Drops everything — a new anime's episodes have nothing to do with the
  /// last one's.
  void clear() => _entries.clear();

  _Entry? _live(String episodeUrl) {
    final entry = _entries[episodeUrl];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(episodeUrl);
      return null;
    }
    return entry;
  }
}

class _Entry {
  _Entry(this.future, this.expiresAt);

  final Future<List<StreamResult>> future;
  final DateTime expiresAt;
}

@Riverpod(keepAlive: true)
StreamSourcePrefetch streamSourcePrefetch(Ref ref) => StreamSourcePrefetch();
