import '../domain/entity/multimedia_item.dart';

/// Stable identity for one logical media download.
///
/// This key deliberately excludes executor-attempt details such as taskId,
/// signed delivery URLs, target filenames, localized labels and poster data.
/// Those values may change while the same logical episode is retried/adopted.
class DownloadLogicalIdentity {
  const DownloadLogicalIdentity._({
    required this.key,
    required this.contentKey,
    required this.contentAliases,
    required this.season,
    required this.episode,
    required this.dubStatus,
  });

  final String key;
  final String contentKey;

  /// Stable catalog aliases known for this media snapshot.
  ///
  /// [contentKey] remains the first/legacy preferred alias so persisted v1 keys
  /// do not churn when this feature lands. Additional aliases let a later,
  /// richer media snapshot (for example MAL + AniList instead of AniList only)
  /// adopt the already persisted logical episode instead of starting a second
  /// execution row.
  final Set<String> contentAliases;
  final int season;
  final int episode;
  final DubStatus dubStatus;

  factory DownloadLogicalIdentity.fromMedia({
    required MultimediaItem item,
    Episode? episode,
  }) {
    final aliases = _contentAliases(item);
    final contentKey = aliases.first;
    final episodeDub = episode?.dubStatus ?? DubStatus.none;
    final dubStatus = episodeDub != DubStatus.none
        ? episodeDub
        : (item.isDubbed ? DubStatus.dubbed : DubStatus.none);
    final season = episode?.season ?? 0;
    final episodeNumber = episode?.episode ?? 0;
    final key = <String>[
      'download:v1',
      contentKey,
      's$season',
      'e$episodeNumber',
      'dub:${dubStatus.name}',
    ].join('|');

    return DownloadLogicalIdentity._(
      key: key,
      contentKey: contentKey,
      contentAliases: Set<String>.unmodifiable(aliases),
      season: season,
      episode: episodeNumber,
      dubStatus: dubStatus,
    );
  }

  /// Returns true when [persistedKey] represents this exact episode and its
  /// content component is one of the stable aliases in the current snapshot.
  ///
  /// This intentionally requires season, episode and dub status to match before
  /// considering aliases. An enriched metadata snapshot can therefore adopt an
  /// older AniList/MAL/TMDb/IMDb identity without ever collapsing two episodes.
  bool matchesPersistedKey(String persistedKey) {
    final persisted = persistedKey.trim();
    if (persisted.isEmpty) return false;
    if (persisted == key) return true;

    final parsed = _ParsedLogicalDownloadKey.tryParse(persisted);
    if (parsed == null ||
        parsed.season != season ||
        parsed.episode != episode ||
        parsed.dubStatus != dubStatus.name) {
      return false;
    }
    return contentAliases.contains(parsed.contentKey);
  }

  static List<String> _contentAliases(MultimediaItem item) {
    final aliases = <String>[];
    final seen = <String>{};

    void add(String value) {
      if (value.isNotEmpty && seen.add(value)) aliases.add(value);
    }

    final sync = item.syncData;
    if (sync != null && sync.isNotEmpty) {
      const stableSyncKeys = <String>[
        'malId',
        'mal_id',
        'anilistId',
        'anilist_id',
        'kitsuId',
        'kitsu_id',
      ];
      for (final key in stableSyncKeys) {
        final value = sync[key]?.trim();
        if (value != null && value.isNotEmpty) {
          // Preserve the exact legacy key spelling used by v1 identities.
          add('sync:${key.toLowerCase()}:${Uri.encodeComponent(value)}');
        }
      }
    }

    if (item.tmdbId != null) {
      add('tmdb:${item.tmdbId}');
    }
    final imdbId = item.imdbId?.trim().toLowerCase();
    if (imdbId != null && imdbId.isNotEmpty) {
      add('imdb:${Uri.encodeComponent(imdbId)}');
    }

    final canonicalUrl = _canonicalCatalogUrl(item.url);
    if (canonicalUrl.isNotEmpty) {
      add('url:${Uri.encodeComponent(canonicalUrl)}');
    }

    if (aliases.isNotEmpty) return aliases;

    // Last-resort migration identity for providers that supplied neither a
    // stable external ID nor a catalog URL. This is intentionally namespaced
    // as weak evidence so callers can replace it when stronger identity is
    // discovered later; it must never be confused with an execution URL.
    final provider = (item.provider ?? item.source ?? 'unknown')
        .trim()
        .toLowerCase();
    final title = item.title.trim().toLowerCase();
    add('weak:${Uri.encodeComponent(provider)}:${Uri.encodeComponent(title)}');
    return aliases;
  }

  static String _canonicalCatalogUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    if (!uri.hasScheme || uri.host.isEmpty) {
      final withoutFragment = trimmed.split('#').first;
      return withoutFragment.split('?').first.replaceFirst(RegExp(r'/+$'), '');
    }

    var path = uri.path.isEmpty ? '/' : uri.path;
    if (path.length > 1) {
      path = path.replaceFirst(RegExp(r'/+$'), '');
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final includePort =
        uri.hasPort &&
        !((scheme == 'https' && uri.port == 443) ||
            (scheme == 'http' && uri.port == 80));
    final authority = includePort ? '$host:${uri.port}' : host;
    return '$scheme://$authority$path';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadLogicalIdentity && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

class _ParsedLogicalDownloadKey {
  const _ParsedLogicalDownloadKey({
    required this.contentKey,
    required this.season,
    required this.episode,
    required this.dubStatus,
  });

  final String contentKey;
  final int season;
  final int episode;
  final String dubStatus;

  static _ParsedLogicalDownloadKey? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 5 || parts[0] != 'download:v1') return null;
    final seasonPart = parts[2];
    final episodePart = parts[3];
    final dubPart = parts[4];
    if (!seasonPart.startsWith('s') ||
        !episodePart.startsWith('e') ||
        !dubPart.startsWith('dub:')) {
      return null;
    }
    final season = int.tryParse(seasonPart.substring(1));
    final episode = int.tryParse(episodePart.substring(1));
    final dubStatus = dubPart.substring(4);
    if (season == null || episode == null || dubStatus.isEmpty) return null;
    return _ParsedLogicalDownloadKey(
      contentKey: parts[1],
      season: season,
      episode: episode,
      dubStatus: dubStatus,
    );
  }
}

/// Restores the stable logical identity from presentation metadata.
///
/// New metadata carries the key explicitly. Legacy rows may be migrated only
/// from the original media/episode snapshots; executor URLs, filenames and
/// task IDs are never accepted as substitutes because they are mutable attempt
/// details and can collide across episodes.
String? logicalDownloadIdFromMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return null;
  final explicit = metadata['logicalId']?.toString().trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final rawItem = metadata['item'];
  if (rawItem is! Map) return null;
  try {
    final item = MultimediaItem.fromJson(Map<String, dynamic>.from(rawItem));
    Episode? episode;
    final rawEpisode = metadata['episode'];
    if (rawEpisode is Map) {
      episode = Episode.fromJson(Map<String, dynamic>.from(rawEpisode));
    }
    return DownloadLogicalIdentity.fromMedia(item: item, episode: episode).key;
  } catch (_) {
    return null;
  }
}
