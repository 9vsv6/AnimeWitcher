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

  Future<MultimediaItem> getDetails(String url);

  /// Loads episodes independently from the metadata/details request.
  ///
  /// Older providers remain compatible because the default implementation
  /// falls back to [getDetails] and extracts its embedded episodes.
  Future<List<Episode>> getEpisodes(String url) async {
    final details = await getDetails(url);
    return details.episodes ?? const <Episode>[];
  }

  // Returns list of video streams (urls)
  Future<List<StreamResult>> loadStreams(String url);
}
