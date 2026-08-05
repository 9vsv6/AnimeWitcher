import 'package:dio/dio.dart';
import '../domain/entity/multimedia_item.dart';

enum ProviderType { movie, series, anime, livestream, other }

class ProviderSearchFilterOptions {
  final List<String> statuses;
  final List<String> types;
  final List<String> ageRatings;
  final List<String> years;
  final List<String> genres;

  const ProviderSearchFilterOptions({
    this.statuses = const <String>[],
    this.types = const <String>[],
    this.ageRatings = const <String>[],
    this.years = const <String>[],
    this.genres = const <String>[],
  });

  bool get isEmpty =>
      statuses.isEmpty &&
      types.isEmpty &&
      ageRatings.isEmpty &&
      years.isEmpty &&
      genres.isEmpty;

  factory ProviderSearchFilterOptions.fromJson(Map<String, dynamic> json) {
    List<String> read(String key) {
      final value = json[key];
      if (value is! List) return const <String>[];
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    return ProviderSearchFilterOptions(
      statuses: read('statuses'),
      types: read('types'),
      ageRatings: read('ageRatings'),
      years: read('years'),
      genres: read('genres'),
    );
  }
}

class ProviderSearchFilters {
  final Set<String> statuses;
  final Set<String> types;
  final Set<String> ageRatings;
  final Set<String> years;
  final Set<String> genres;

  const ProviderSearchFilters({
    this.statuses = const <String>{},
    this.types = const <String>{},
    this.ageRatings = const <String>{},
    this.years = const <String>{},
    this.genres = const <String>{},
  });

  bool get isEmpty => count == 0;
  bool get isNotEmpty => !isEmpty;

  int get count =>
      statuses.length +
      types.length +
      ageRatings.length +
      years.length +
      genres.length;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'statuses': statuses.toList(growable: false),
      'types': types.toList(growable: false),
      'ageRatings': ageRatings.toList(growable: false),
      'years': years.toList(growable: false),
      'genres': genres.toList(growable: false),
    };
  }
}

class ProviderMediaPage {
  final List<MultimediaItem> items;
  final int nextOffset;
  final bool hasMore;

  const ProviderMediaPage({
    required this.items,
    required this.nextOffset,
    required this.hasMore,
  });
}

abstract class SkyStreamProvider {
  /// Unique Package Name (from plugin.json)
  String get packageName;

  /// Display Name
  String get name;
  String get mainUrl;
  String get version;
  List<String> get languages;
  Set<ProviderType> get supportedTypes;
  bool get hasSearch => true;
  bool get isDebug => packageName.endsWith('.debug');

  /// Cancel any pending JS eval for this provider so the queue isn't blocked
  /// by a stale IIFE load after the triggering search was abandoned.
  /// The provider resets itself so the next search retries cleanly.
  void cancelInit() {}

  // Key methods providers must implement
  Future<List<MultimediaItem>> search(String query, {CancelToken? cancelToken});

  /// Optional provider-defined search filter values.
  Future<ProviderSearchFilterOptions> getSearchFilterOptions() async {
    return const ProviderSearchFilterOptions();
  }

  /// Filtered search falls back to normal text search for older providers.
  Future<List<MultimediaItem>> searchWithFilters(
    String query,
    ProviderSearchFilters filters, {
    CancelToken? cancelToken,
  }) {
    return search(query, cancelToken: cancelToken);
  }

  /// Loads one search page. Older providers remain compatible through
  /// a bounded slice of their existing search result.
  Future<ProviderMediaPage> searchPage(
    String query,
    ProviderSearchFilters filters, {
    int offset = 0,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 100).toInt();
    final all = await searchWithFilters(
      query,
      filters,
      cancelToken: cancelToken,
    );
    if (safeOffset >= all.length) {
      return ProviderMediaPage(
        items: const <MultimediaItem>[],
        nextOffset: safeOffset,
        hasMore: false,
      );
    }
    final end = (safeOffset + safeLimit).clamp(0, all.length).toInt();
    return ProviderMediaPage(
      items: all.sublist(safeOffset, end),
      nextOffset: end,
      hasMore: end < all.length,
    );
  }

  // Returns categorized content (Section Name -> Items)
  Future<Map<String, List<MultimediaItem>>> getHome();

  /// Loads the complete content for one provider home section.
  ///
  /// Providers that do not support lazy sections automatically fall
  /// back to their existing [getHome] result.
  Future<List<MultimediaItem>> getHomeSection(String sectionName) async {
    final home = await getHome();
    return home[sectionName] ?? const <MultimediaItem>[];
  }

  /// Loads one provider Home section page.
  Future<ProviderMediaPage> getHomeSectionPage(
    String sectionName, {
    int offset = 0,
    int limit = 30,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 100).toInt();
    final all = await getHomeSection(sectionName);
    if (safeOffset >= all.length) {
      return ProviderMediaPage(
        items: const <MultimediaItem>[],
        nextOffset: safeOffset,
        hasMore: false,
      );
    }
    final end = (safeOffset + safeLimit).clamp(0, all.length).toInt();
    return ProviderMediaPage(
      items: all.sublist(safeOffset, end),
      nextOffset: end,
      hasMore: end < all.length,
    );
  }

  Future<MultimediaItem> getDetails(String url);

  /// Loads episodes independently from the metadata/details request.
  ///
  /// Older providers remain compatible because the default implementation
  /// falls back to [getDetails] and extracts its embedded episodes.
  Future<List<Episode>> getEpisodes(String url) async {
    final details = await getDetails(url);
    return details.episodes ?? const <Episode>[];
  }

  /// Loads optional episode artwork and season/episode numbering separately.
  ///
  /// This must never be required for rendering the initial episode list.
  Future<List<Episode>> getEpisodeMetadata(String url) async {
    return const <Episode>[];
  }

  // Returns list of video streams (urls)
  Future<List<StreamResult>> loadStreams(String url);
}
