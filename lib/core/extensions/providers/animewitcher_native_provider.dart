import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html_unescape/html_unescape.dart';

import '../../domain/entity/multimedia_item.dart';
import '../base_provider.dart';

/// First native AnimeWitcher implementation.
///
/// This intentionally lives next to the JavaScript extension while parity is
/// validated. Phase 1 covers native browsing, search, basic details, episodes,
/// and direct/PixelDrain playback. MediaFire/StreamTape and optional metadata
/// sections remain on the JavaScript provider until their native ports are
/// proven stable.
class AnimeWitcherNativeProvider extends SkyStreamProvider {
  AnimeWitcherNativeProvider(this._dio);

  final Dio _dio;
  final HtmlUnescape _unescape = HtmlUnescape();

  static const String _baseUrl = 'https://animewitcher.com';
  static const String _firestoreProjectId = 'animewitcher-1c66d';
  static const String _algoliaAppId = '5UIU27G8CZ';
  static const String _algoliaApiKey = 'ef06c5ee4a0d213c011694f18861805c';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _serverTimeout = Duration(seconds: 6);
  static const int _previewSize = 10;

  @override
  String get packageName => 'com.fares669.animewitcher.native';

  @override
  String get name => 'AnimeWitcher Native (Beta)';

  @override
  String get mainUrl => _baseUrl;

  @override
  String get version => '0.1.0';

  @override
  List<String> get languages => const <String>['ar'];

  @override
  Set<ProviderType> get supportedTypes => const <ProviderType>{
        ProviderType.anime,
        ProviderType.movie,
      };

  @override
  int get viewAllPageSize => 30;

  @override
  int get searchPageSize => 30;

  @override
  bool get supportsIndependentDetailSections => true;

  Options _jsonOptions({
    Map<String, String>? headers,
    Duration timeout = _httpTimeout,
  }) {
    return Options(
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        ...?headers,
      },
      sendTimeout: timeout,
      receiveTimeout: timeout,
    );
  }

  dynamic _decodeData(dynamic raw) {
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  Map<String, dynamic> _map(dynamic raw) {
    raw = _decodeData(raw);
    if (raw is! Map) return <String, dynamic>{};
    return raw.map<String, dynamic>(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );
  }

  List<dynamic> _list(dynamic raw) {
    raw = _decodeData(raw);
    return raw is List ? raw : const <dynamic>[];
  }

  Future<Map<String, dynamic>?> _getJson(
    String url, {
    CancelToken? cancelToken,
    Duration timeout = _httpTimeout,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: _jsonOptions(headers: headers, timeout: timeout),
      );
      if ((response.statusCode ?? 0) < 200 || (response.statusCode ?? 0) >= 300) {
        return null;
      }
      final value = _map(response.data);
      return value.isEmpty ? null : value;
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _postJson(
    String url,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
    Duration timeout = _httpTimeout,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: body,
        cancelToken: cancelToken,
        options: _jsonOptions(
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
            ...?headers,
          },
          timeout: timeout,
        ),
      );
      if ((response.statusCode ?? 0) < 200 || (response.statusCode ?? 0) >= 300) {
        return null;
      }
      final value = _map(response.data);
      return value.isEmpty ? null : value;
    } on DioException {
      return null;
    }
  }

  String _firestoreUrl(String path) {
    return 'https://firestore.googleapis.com/v1/projects/'
        '${Uri.encodeComponent(_firestoreProjectId)}'
        '/databases/(default)/documents/$path';
  }

  dynamic _firestoreValue(dynamic raw) {
    final value = _map(raw);
    if (value.isEmpty) return null;

    if (value.containsKey('stringValue')) {
      return value['stringValue']?.toString() ?? '';
    }
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue']?.toString() ?? '') ?? 0;
    }
    if (value.containsKey('doubleValue')) {
      final rawDouble = value['doubleValue'];
      if (rawDouble is num) return rawDouble.toDouble();
      return double.tryParse(rawDouble?.toString() ?? '') ?? 0.0;
    }
    if (value.containsKey('booleanValue')) {
      return value['booleanValue'] == true;
    }
    if (value.containsKey('timestampValue')) {
      return value['timestampValue']?.toString() ?? '';
    }
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('referenceValue')) {
      return value['referenceValue']?.toString() ?? '';
    }
    if (value.containsKey('bytesValue')) {
      return value['bytesValue']?.toString() ?? '';
    }
    if (value.containsKey('geoPointValue')) {
      return _map(value['geoPointValue']);
    }

    final arrayValue = _map(value['arrayValue']);
    if (arrayValue.isNotEmpty) {
      return _list(arrayValue['values'])
          .map<dynamic>(_firestoreValue)
          .toList(growable: false);
    }

    final mapValue = _map(value['mapValue']);
    if (mapValue.isNotEmpty) {
      return _firestoreFields(mapValue['fields']);
    }
    return null;
  }

  Map<String, dynamic> _firestoreFields(dynamic raw) {
    final fields = _map(raw);
    final output = <String, dynamic>{};
    for (final entry in fields.entries) {
      output[entry.key] = _firestoreValue(entry.value);
    }
    return output;
  }

  String _algoliaUrl(String index) {
    return 'https://$_algoliaAppId-dsn.algolia.net/1/indexes/'
        '${Uri.encodeComponent(index)}/query';
  }

  Map<String, String> get _algoliaHeaders => const <String, String>{
        'X-Algolia-Application-Id': _algoliaAppId,
        'X-Algolia-API-Key': _algoliaApiKey,
        'X-Algolia-Agent': 'Algolia for JavaScript (4.x); SkyStream',
        'User-Agent': 'Algolia for Android (3.27.0); Android (13)',
      };

  Future<Map<String, dynamic>> _algoliaQuery(
    String index, {
    String query = '',
    int page = 0,
    int hitsPerPage = 30,
    String filters = '',
    List<String>? attributes,
    CancelToken? cancelToken,
  }) async {
    final params = <String>[];
    void append(String key, Object? value) {
      if (value == null || value.toString().isEmpty) return;
      params.add(
        '${Uri.encodeQueryComponent(key)}='
        '${Uri.encodeQueryComponent(value.toString())}',
      );
    }

    append('query', query);
    append('hitsPerPage', hitsPerPage.clamp(1, 100));
    append('page', page < 0 ? 0 : page);
    if (attributes != null && attributes.isNotEmpty) {
      append('attributesToRetrieve', jsonEncode(attributes));
    }
    if (filters.isNotEmpty) append('filters', filters);

    final payload = await _postJson(
      _algoliaUrl(index),
      <String, dynamic>{'params': params.join('&')},
      cancelToken: cancelToken,
      headers: _algoliaHeaders,
    );
    if (payload == null || payload['hits'] is! List) {
      return <String, dynamic>{
        'hits': const <dynamic>[],
        'page': 0,
        'nbPages': 0,
      };
    }
    return payload;
  }

  static const List<String> _searchAttributes = <String>[
    'objectID',
    'anime_id',
    'name',
    'english_title',
    'poster_uri',
    'path',
    'type',
    'story',
    'description',
    'details',
    'tags',
    'mal_id',
    'malId',
    'poster',
    'cover_uri',
    '_highlightResult',
  ];

  static const List<String> _recentAttributes = <String>[
    'filler',
    'note',
    'name',
    'date',
    'doc_ref',
    'episode_id',
    'anime_id',
    'episode_name',
    'title',
    'series_id',
    'seriesId',
    'series_name',
    'parent_anime_id',
    'parentAnimeId',
    'anime',
    'series',
    'poster_uri',
    'poster',
    'cover_uri',
    'mal_id',
    'malId',
    'type',
    'tags',
    'thumb_uri',
  ];

  String _text(dynamic value) => value == null ? '' : value.toString().trim();

  String _decodeHtml(dynamic value) {
    final text = _unescape.convert(_text(value));
    return text.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  String _lastPathSegment(String value) {
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  String _animeIdFromHit(Map<String, dynamic> source) {
    final anime = _map(source['anime']);
    final series = _map(source['series']);
    final docRef = _text(source['doc_ref'] ?? source['docRef']);
    final docId = docRef.isEmpty
        ? ''
        : _lastPathSegment(docRef);
    final candidates = <dynamic>[
      source['anime_id'],
      source['animeId'],
      source['parent_anime_id'],
      source['parentAnimeId'],
      source['series_id'],
      source['seriesId'],
      anime['anime_id'],
      anime['animeId'],
      anime['id'],
      anime['name'],
      series['anime_id'],
      series['id'],
      series['name'],
      docId,
      source['objectID'],
      source['id'],
      source['path'],
    ];
    for (final candidate in candidates) {
      final value = _text(candidate);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic> _compactHit(Map<String, dynamic> source) {
    const keys = <String>[
      'objectID',
      'anime_id',
      'animeId',
      'name',
      'english_title',
      'poster_uri',
      'poster',
      'cover_uri',
      'path',
      'type',
      'story',
      'description',
      'details',
      'tags',
      'mal_id',
      'malId',
      'year',
      'state',
      'status',
    ];
    final output = <String, dynamic>{};
    for (final key in keys) {
      final value = source[key];
      if (value != null) output[key] = value;
    }
    return output;
  }

  String _makeAnimeUrl(Map<String, dynamic> hit) {
    final animeId = _animeIdFromHit(hit);
    final data = Uri.encodeComponent(jsonEncode(_compactHit(hit)));
    return '$_baseUrl/watch/${Uri.encodeComponent(animeId)}?aw_data=$data';
  }

  _AnimeRoute _parseAnimeUrl(String url) {
    final source = url.trim();
    final uri = Uri.tryParse(source);
    String animeId = '';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      animeId = uri.pathSegments.last;
    }
    Map<String, dynamic> hit = <String, dynamic>{};
    final raw = uri?.queryParameters['aw_data'];
    if (raw != null && raw.isNotEmpty) {
      try {
        hit = _map(jsonDecode(Uri.decodeComponent(raw)));
      } catch (_) {
        try {
          hit = _map(jsonDecode(raw));
        } catch (_) {}
      }
    }
    return _AnimeRoute(animeId: animeId, hit: hit);
  }

  String _posterFromHit(Map<String, dynamic> source) {
    final poster = _map(source['poster']);
    for (final candidate in <dynamic>[
      source['poster_uri'],
      poster['large'],
      poster['medium'],
      source['cover_uri'],
    ]) {
      final value = _text(candidate);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isMovieType(dynamic raw) {
    final value = _text(raw).toLowerCase();
    return value.contains('فيلم') ||
        value == 'movie' ||
        value == 'film' ||
        value.contains('movie');
  }

  ShowStatus _statusFromHit(Map<String, dynamic> source) {
    final details = _map(source['details']);
    final raw = _text(
      details['state'] ??
          details['status'] ??
          source['state'] ??
          source['status'],
    ).toLowerCase();
    if (RegExp(r'مكتمل|منتهي|finished|completed', caseSensitive: false)
        .hasMatch(raw)) {
      return ShowStatus.completed;
    }
    if (RegExp(r'قادم|لم يعرض|upcoming|not yet', caseSensitive: false)
        .hasMatch(raw)) {
      return ShowStatus.upcoming;
    }
    return ShowStatus.ongoing;
  }

  int? _yearFromHit(Map<String, dynamic> source) {
    final details = _map(source['details']);
    final match = RegExp(r'\b(19|20)\d{2}\b')
        .firstMatch(_text(details['year'] ?? source['year']));
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  List<String> _stringList(dynamic raw) {
    return _list(raw)
        .map<String>((value) => _text(value))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  int _malId(Map<String, dynamic> source) {
    final details = _map(source['details']);
    final raw = source['mal_id'] ??
        source['malId'] ??
        source['malID'] ??
        details['mal_id'] ??
        details['malId'] ??
        details['malID'];
    final match = RegExp(r'\d+').firstMatch(_text(raw));
    return match == null ? 0 : (int.tryParse(match.group(0)!) ?? 0);
  }

  MultimediaItem _mapHit(
    Map<String, dynamic> source, {
    bool recent = false,
  }) {
    final title = _text(
      source['name'] ?? source['english_title'] ?? source['objectID'],
    );
    final story = _decodeHtml(source['story'] ?? source['description']);
    String description = story;
    String? episodeBadge;
    if (recent) {
      final rawEpisode = _text(
        source['episode_id'] ??
            source['episodeId'] ??
            source['episode_number'] ??
            source['episodeNumber'] ??
            source['episode_name'] ??
            source['episodeName'],
      );
      final number = RegExp(r'[0-9٠-٩۰-۹]+(?:\.[0-9]+)?').firstMatch(rawEpisode);
      if (number != null) {
        episodeBadge = 'حلقة ${_normalizeDigits(number.group(0)!)}';
      }
      final episodeName = _text(source['episode_name'] ?? source['episodeName']);
      if (episodeName.isNotEmpty) {
        description = story.isEmpty ? episodeName : '$episodeName • $story';
      }
    }

    return MultimediaItem(
      title: title.isEmpty ? 'AnimeWitcher' : title,
      url: _makeAnimeUrl(source),
      posterUrl: _posterFromHit(source),
      description: description.isEmpty ? null : description,
      contentType:
          _isMovieType(source['type']) ? MultimediaContentType.movie : MultimediaContentType.anime,
      provider: packageName,
      year: _yearFromHit(source),
      status: _statusFromHit(source),
      tags: _stringList(source['tags']),
      source: 'AnimeWitcher Native',
      episodeBadge: episodeBadge,
    );
  }

  List<MultimediaItem> _dedupeHits(
    Iterable<dynamic> hits, {
    bool recent = false,
  }) {
    final seen = <String>{};
    final output = <MultimediaItem>[];
    for (final raw in hits) {
      final hit = _map(raw);
      if (hit.isEmpty) continue;
      final item = _mapHit(hit, recent: recent);
      if (item.title.trim().isEmpty || item.url.trim().isEmpty) continue;
      if (!seen.add(item.url)) continue;
      output.add(item);
    }
    return output;
  }

  String _quotedFilterValue(String value) => jsonEncode(value);

  String _filterGroup(String field, Iterable<String> values, String joiner) {
    final clean = values.map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
    if (clean.isEmpty) return '';
    final pieces = clean.map((value) => '$field:${_quotedFilterValue(value)}').toList();
    if (pieces.length == 1) return pieces.first;
    return '(${pieces.join(' $joiner ')})';
  }

  String _buildFilters(ProviderSearchFilters filters) {
    return <String>[
      _filterGroup('details.state', filters.statuses, 'OR'),
      _filterGroup('type', filters.types, 'OR'),
      _filterGroup('details.age', filters.ageRatings, 'OR'),
      _filterGroup('details.year', filters.years, 'OR'),
      _filterGroup('tags', filters.genres, 'AND'),
    ].where((value) => value.isNotEmpty).join(' AND ');
  }

  @override
  Future<ProviderSearchFilterOptions> getSearchFilterOptions() async {
    final years = <String>[
      for (var year = 2028; year >= 1961; year--) year.toString(),
    ];
    return ProviderSearchFilterOptions(
      statuses: const <String>['لم يتم بثه بعد', 'مستمر', 'مكتمل'],
      types: const <String>['مسلسل', 'اونا', 'اوفا', 'فيلم', 'خاصة'],
      ageRatings: const <String>['+17', '+13', 'لجميع الأعمار'],
      years: years,
      genres: const <String>[
        'اكشن', 'مغامرات', 'دراما', 'كوميدي', 'خيال', 'اعادة بعث', 'عالم مختلف',
        'سينين', 'شوجو', 'شونين', 'رعب', 'غموض', 'رومانسي', 'خيال علمي',
        'شريحة من الحياة', 'رياضي', 'خارق للطبيعة', 'تشويق', 'ايتشي', 'سيارات',
        'شياطين', 'لعبة', 'حريم', 'تاريخي', 'فنون قتالية', 'ميكا', 'عسكري',
        'موسيقي', 'طعام', 'بنات كيوت', 'رياضات قتالية', 'محاكاة ساخرة', 'بوليسي',
        'نفسي', 'اثارة شغب', 'راحة نفسية', 'تحول جنسي سحري', 'جريمة منظمة',
        'العاب خطيرة', 'تحقيق', 'دموي', 'ايدول', 'اساطير', 'سباق',
        'لعبة استراتيجية', 'فنون بصرية', 'سفر عبر الزمن', 'نجاة', 'ساموراي',
        'مدرسي', 'مكان عمل', 'فضاء', 'قوة خارقة', 'مصاصي دماء', 'جوسي', 'اطفال',
      ],
    );
  }

  @override
  Future<List<MultimediaItem>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final page = await searchPage(
      query,
      const ProviderSearchFilters(),
      offset: 0,
      limit: searchPageSize,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  @override
  Future<List<MultimediaItem>> searchWithFilters(
    String query,
    ProviderSearchFilters filters, {
    CancelToken? cancelToken,
  }) async {
    final page = await searchPage(
      query,
      filters,
      offset: 0,
      limit: searchPageSize,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  @override
  Future<ProviderMediaPage> searchPage(
    String query,
    ProviderSearchFilters filters, {
    int offset = 0,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    final text = query.trim();
    final expression = _buildFilters(filters);
    final safeLimit = limit.clamp(10, 50).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    if (text.isEmpty && expression.isEmpty) {
      return ProviderMediaPage(items: const [], nextOffset: safeOffset, hasMore: false);
    }
    final pageNumber = safeOffset ~/ safeLimit;
    final payload = await _algoliaQuery(
      'series',
      query: text,
      page: pageNumber,
      hitsPerPage: safeLimit,
      filters: expression,
      attributes: _searchAttributes,
      cancelToken: cancelToken,
    );
    final rawHits = _list(payload['hits']);
    final items = _dedupeHits(rawHits);
    final nbPages = int.tryParse(_text(payload['nbPages'])) ?? 0;
    final hasMore = nbPages > 0 ? pageNumber + 1 < nbPages : rawHits.length >= safeLimit;
    return ProviderMediaPage(
      items: items,
      nextOffset: (pageNumber + 1) * safeLimit,
      hasMore: hasMore,
    );
  }

  _HomePlan? _homePlan(String sectionName) {
    switch (sectionName.trim()) {
      case 'أحدث الحلقات':
        return const _HomePlan(index: 'recent', recent: true);
      case 'أنميات الموسم الحالي':
        return _HomePlan(index: 'series', query: _seasonLabel(_currentSeason()));
      case 'أنميات الموسم القادم':
        return _HomePlan(index: 'series', query: _seasonLabel(_nextSeason(_currentSeason())));
      case 'قائمة الأنمي':
        return const _HomePlan(index: 'series_date_created');
      case 'قائمة الأفلام':
        return const _HomePlan(index: 'series', query: 'فيلم');
      default:
        return null;
    }
  }

  _SeasonInfo _currentSeason() {
    final now = DateTime.now().toUtc();
    final month = now.month;
    if (month == 12) return _SeasonInfo('winter', now.year + 1);
    if (month <= 2) return _SeasonInfo('winter', now.year);
    if (month <= 5) return _SeasonInfo('spring', now.year);
    if (month <= 8) return _SeasonInfo('summer', now.year);
    return _SeasonInfo('fall', now.year);
  }

  _SeasonInfo _nextSeason(_SeasonInfo current) {
    const order = <String>['winter', 'spring', 'summer', 'fall'];
    final index = order.indexOf(current.season);
    if (index < 0 || index == order.length - 1) {
      return _SeasonInfo('winter', current.year + 1);
    }
    return _SeasonInfo(order[index + 1], current.year);
  }

  String _seasonLabel(_SeasonInfo value) {
    const names = <String, String>{
      'winter': 'شتاء',
      'spring': 'ربيع',
      'summer': 'صيف',
      'fall': 'خريف',
    };
    final name = names[value.season] ?? '';
    return name.isEmpty ? '' : '$name عام ${value.year}';
  }

  Future<ProviderMediaPage> _loadHomePage(
    String sectionName, {
    int offset = 0,
    int limit = 30,
  }) async {
    final plan = _homePlan(sectionName);
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 50).toInt();
    if (plan == null) {
      return ProviderMediaPage(items: const [], nextOffset: safeOffset, hasMore: false);
    }
    final pageNumber = safeOffset ~/ safeLimit;
    Future<Map<String, dynamic>> load(String index) => _algoliaQuery(
          index,
          query: plan.query,
          page: pageNumber,
          hitsPerPage: safeLimit,
          attributes: plan.recent ? _recentAttributes : _searchAttributes,
        );

    var payload = await load(plan.index);
    var rawHits = _list(payload['hits']);
    if (rawHits.isEmpty &&
        (sectionName == 'أنميات الموسم الحالي' || sectionName == 'أنميات الموسم القادم') &&
        plan.index != 'series_date_created') {
      payload = await load('series_date_created');
      rawHits = _list(payload['hits']);
    }
    final items = _dedupeHits(rawHits, recent: plan.recent);
    final nbPages = int.tryParse(_text(payload['nbPages'])) ?? 0;
    final hasMore = nbPages > 0 ? pageNumber + 1 < nbPages : rawHits.length >= safeLimit;
    return ProviderMediaPage(
      items: items,
      nextOffset: (pageNumber + 1) * safeLimit,
      hasMore: hasMore,
    );
  }

  @override
  Future<Map<String, List<MultimediaItem>>> getHome() async {
    const names = <String>[
      'أحدث الحلقات',
      'أنميات الموسم الحالي',
      'أنميات الموسم القادم',
      'قائمة الأنمي',
      'قائمة الأفلام',
    ];
    final pages = await Future.wait(
      names.map((section) => _loadHomePage(section, limit: _previewSize)),
    );
    return <String, List<MultimediaItem>>{
      for (var i = 0; i < names.length; i++) names[i]: pages[i].items,
    };
  }

  @override
  Future<List<MultimediaItem>> getHomeSection(String sectionName) async {
    return (await _loadHomePage(sectionName, limit: viewAllPageSize)).items;
  }

  @override
  Future<ProviderMediaPage> getHomeSectionPage(
    String sectionName, {
    int offset = 0,
    int limit = 30,
  }) {
    return _loadHomePage(
      sectionName,
      offset: offset,
      limit: viewAllPageSize,
    );
  }

  Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final result = <String, dynamic>{...base};
    for (final entry in overlay.entries) {
      final value = entry.value;
      if (value == null || _text(value).isEmpty && value is! Map && value is! List) continue;
      if (entry.key == 'details' && value is Map) {
        result['details'] = <String, dynamic>{
          ..._map(result['details']),
          ..._map(value),
        };
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _fetchAnimeDocument(String animeId) async {
    final payload = await _getJson(
      _firestoreUrl('anime_list/${Uri.encodeComponent(animeId)}'),
    );
    return payload == null ? <String, dynamic>{} : _firestoreFields(payload['fields']);
  }

  @override
  Future<MultimediaItem> getDetails(String url) async {
    final route = _parseAnimeUrl(url);
    if (route.animeId.isEmpty) {
      throw StateError('AnimeWitcher anime id is missing');
    }
    final document = await _fetchAnimeDocument(route.animeId);
    final source = _mergeMaps(route.hit, document);
    final details = _map(source['details']);
    final title = _text(source['name'] ?? source['english_title'] ?? route.animeId);
    final description = _decodeHtml(
      source['story'] ?? source['description'] ?? details['story'] ?? details['description'],
    );
    final malId = _malId(source);
    final poster = _posterFromHit(source);
    return MultimediaItem(
      title: title.isEmpty ? route.animeId : title,
      url: url,
      posterUrl: poster,
      bannerUrl: poster.isEmpty ? null : poster,
      description: description.isEmpty ? null : description,
      contentType:
          _isMovieType(source['type']) ? MultimediaContentType.movie : MultimediaContentType.anime,
      provider: packageName,
      year: _yearFromHit(source),
      status: _statusFromHit(source),
      tags: _stringList(source['tags']),
      syncData: malId > 0
          ? <String, String>{'malId': '$malId', 'mal_id': '$malId'}
          : null,
      source: 'AnimeWitcher Native',
    );
  }

  @override
  Future<List<Actor>> getCast(String url) async => const <Actor>[];

  @override
  Future<List<Trailer>> getTrailers(String url) async => const <Trailer>[];

  @override
  Future<List<MultimediaItem>> getRelated(String url) async => const <MultimediaItem>[];

  @override
  Future<List<MultimediaItem>> getRecommendations(String url) async => const <MultimediaItem>[];

  @override
  Future<NextAiring?> getNextAiring(String url) async => null;

  String _normalizeDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const eastern = '۰۱۲۳۴۵۶۷۸۹';
    return value
        .replaceAllMapped(RegExp(r'[٠-٩]'), (m) => '${arabic.indexOf(m.group(0)!)}')
        .replaceAllMapped(RegExp(r'[۰-۹]'), (m) => '${eastern.indexOf(m.group(0)!)}');
  }

  String _localizedEpisodeTitle(dynamic raw) {
    if (raw is String) return _decodeHtml(raw);
    final source = _map(raw);
    for (final key in const <String>[
      'ar', 'ar-SA', 'ar_SA', 'arabic', 'translated', 'value', 'title', 'name',
    ]) {
      final value = _decodeHtml(source[key]);
      if (value.isNotEmpty) return value;
    }
    for (final value in source.values) {
      final text = _decodeHtml(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool _isGenericEpisodeTitle(String value) {
    final title = _normalizeDigits(value.trim().toLowerCase());
    if (title.isEmpty) return true;
    return RegExp(r'^(?:الحلقة|حلقه)\s*\d+$').hasMatch(title) ||
        RegExp(r'^(?:episode|ep\.?)\s*\d+$', caseSensitive: false).hasMatch(title) ||
        RegExp(r'^\d+$').hasMatch(title);
  }

  String _episodeTitle(Map<String, dynamic> source, int number) {
    final generic = _decodeHtml(
      source['name'] ?? source['episode_name'] ?? source['episodeName'] ?? 'الحلقة $number',
    );
    for (final key in const <String>[
      'title_translated', 'titleTranslated', 'title_ar', 'titleAr', 'arabic_title', 'arabicTitle',
      'title_en', 'titleEn', 'title_english', 'titleEnglish', 'english_title', 'englishTitle',
      'episode_title', 'episodeTitle', 'title',
    ]) {
      final title = _localizedEpisodeTitle(source[key]);
      if (title.isNotEmpty && !_isGenericEpisodeTitle(title)) return title;
    }
    return generic.isEmpty ? 'الحلقة $number' : generic;
  }

  _EpisodeRecord _episodeRecord(
    Map<String, dynamic> source, {
    required String fallbackId,
    required int fallbackNumber,
  }) {
    var id = _text(source['doc_id'] ?? source['id'] ?? source['episode_id']);
    if (id.isEmpty) id = fallbackId;
    final rawNumber = source['number'];
    var number = rawNumber is num ? rawNumber.toInt() : int.tryParse(_text(rawNumber)) ?? 0;
    if (number <= 0) {
      final match = RegExp(r'\d+').firstMatch(_normalizeDigits(id));
      number = match == null ? fallbackNumber : int.tryParse(match.group(0)!) ?? fallbackNumber;
    }
    final image = _text(
      source['thumb_uri'] ?? source['image'] ?? source['image_url'] ?? source['poster'],
    );
    return _EpisodeRecord(
      id: id,
      number: number,
      title: _episodeTitle(source, number),
      image: image,
    );
  }

  Future<List<_EpisodeRecord>> _fetchEpisodeSummary(String animeId) async {
    final path = 'anime_list/${Uri.encodeComponent(animeId)}/episodes_summery/summery';
    final payload = await _getJson(_firestoreUrl(path));
    if (payload == null) return const <_EpisodeRecord>[];
    final fields = _firestoreFields(payload['fields']);
    final rawEpisodes = _list(fields['episodes']);
    if (rawEpisodes.isEmpty) return const <_EpisodeRecord>[];
    final output = <_EpisodeRecord>[];
    for (var i = 0; i < rawEpisodes.length; i++) {
      final source = _map(rawEpisodes[i]);
      output.add(
        _episodeRecord(
          source,
          fallbackId: '${i + 1}'.padLeft(3, '0'),
          fallbackNumber: i + 1,
        ),
      );
    }
    return output;
  }

  Future<List<_EpisodeRecord>> _fetchEpisodeCollection(String animeId) async {
    final output = <_EpisodeRecord>[];
    final encoded = Uri.encodeComponent(animeId);
    var pageSize = 1000;
    String nextToken = '';
    final seenTokens = <String>{};
    for (var page = 0; page < 20; page++) {
      var url = '${_firestoreUrl('anime_list/$encoded/episodes')}?pageSize=$pageSize';
      if (nextToken.isNotEmpty) {
        url += '&pageToken=${Uri.encodeQueryComponent(nextToken)}';
      }
      var payload = await _getJson(url);
      if (page == 0 && payload == null && pageSize != 300) {
        pageSize = 300;
        payload = await _getJson('${_firestoreUrl('anime_list/$encoded/episodes')}?pageSize=$pageSize');
      }
      if (payload == null) break;
      final documents = _list(payload['documents']);
      for (var i = 0; i < documents.length; i++) {
        final document = _map(documents[i]);
        final fields = _firestoreFields(document['fields']);
        var id = _text(fields['doc_id']);
        if (id.isEmpty) {
          final name = _text(document['name']);
          if (name.isNotEmpty) id = name.split('/').last;
        }
        try {
          id = Uri.decodeComponent(id);
        } catch (_) {}
        output.add(
          _episodeRecord(
            fields,
            fallbackId: id.isEmpty ? '${output.length + 1}'.padLeft(3, '0') : id,
            fallbackNumber: output.length + 1,
          ),
        );
      }
      final token = _text(payload['nextPageToken']);
      if (token.isEmpty || !seenTokens.add(token)) break;
      nextToken = token;
    }
    return output;
  }

  @override
  Future<List<Episode>> getEpisodes(String url) async {
    final route = _parseAnimeUrl(url);
    if (route.animeId.isEmpty) throw StateError('AnimeWitcher anime id is missing');
    var records = await _fetchEpisodeSummary(route.animeId);
    if (records.isEmpty) records = await _fetchEpisodeCollection(route.animeId);
    records.sort((a, b) => b.number.compareTo(a.number));
    return records
        .map(
          (record) => Episode(
            name: record.title,
            url: '${Uri.encodeComponent(route.animeId)}|${Uri.encodeComponent(record.id)}',
            season: 1,
            episode: record.number,
            posterUrl: record.image.isEmpty ? null : record.image,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Episode>> getEpisodeMetadata(String url) async => const <Episode>[];

  _EpisodeRoute _parseEpisodeUrl(String data) {
    final parts = data.split('|');
    if (parts.length < 2) return const _EpisodeRoute('', '');
    String animeId = parts.first;
    String episodeId = parts.sublist(1).join('|');
    try {
      animeId = Uri.decodeComponent(animeId);
    } catch (_) {}
    try {
      episodeId = Uri.decodeComponent(episodeId);
    } catch (_) {}
    return _EpisodeRoute(animeId.trim(), episodeId.trim());
  }

  _ServerRecord _serverRecord(dynamic raw) {
    final source = _map(raw);
    return _ServerRecord(
      name: _text(source['name']),
      link: _text(source['link']),
      quality: _text(source['quality']),
      originalLink: _text(source['original_link'] ?? source['originalLink']),
      directLink: source['direct_link'] == true || source['directLink'] == true,
      visible: source['visible'] == null ? true : source['visible'] == true,
    );
  }

  Future<List<_ServerRecord>> _serverSummary(String animeId, String episodeId) async {
    final path = 'anime_list/${Uri.encodeComponent(animeId)}/episodes/'
        '${Uri.encodeComponent(episodeId)}/servers2/all_servers';
    final payload = await _getJson(_firestoreUrl(path), timeout: _serverTimeout);
    if (payload == null) return const <_ServerRecord>[];
    final fields = _firestoreFields(payload['fields']);
    return _list(fields['servers'])
        .map<_ServerRecord>(_serverRecord)
        .where((server) => server.visible && server.name.isNotEmpty && server.link.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<_ServerRecord>> _serverCollection(String animeId, String episodeId) async {
    final path = 'anime_list/${Uri.encodeComponent(animeId)}/episodes/'
        '${Uri.encodeComponent(episodeId)}/servers?pageSize=20';
    final payload = await _getJson(_firestoreUrl(path), timeout: _serverTimeout);
    if (payload == null) return const <_ServerRecord>[];
    final output = <_ServerRecord>[];
    for (final raw in _list(payload['documents'])) {
      final document = _map(raw);
      final server = _serverRecord(_firestoreFields(document['fields']));
      if (server.visible && server.name.isNotEmpty && server.link.isNotEmpty) {
        output.add(server);
      }
    }
    return output;
  }

  Future<List<_ServerRecord>> _fetchServers(String animeId, String episodeId) async {
    var servers = await _serverSummary(animeId, episodeId);
    if (servers.isEmpty) servers = await _serverCollection(animeId, episodeId);
    final seen = <String>{};
    return servers.where((server) => seen.add('${server.name}|${server.quality}|${server.link}')).toList();
  }

  String _pixelDrainId(String url) {
    final first = RegExp(
      r'pixeldrain\.(?:com|net)/(?:u|api/file)/([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (first != null) return first.group(1)!;
    final second = RegExp(
      r'pd\.1drv\.eu\.org/([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(url);
    return second?.group(1) ?? '';
  }

  bool _isPixelDrain(_ServerRecord server) {
    final name = server.name.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return name == 'PD' || name == 'PD EU TEST' || name.contains('PIXELDRAIN');
  }

  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('streamtape.') || lower.contains('mediafire.com/')) return false;
    return RegExp(r'\.(?:m3u8|mp4|mkv|webm|m4v|mov|ts|avi)(?:$|[?#])', caseSensitive: false)
            .hasMatch(url) ||
        lower.contains('/api/file/');
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async {
    final route = _parseEpisodeUrl(url);
    if (route.animeId.isEmpty || route.episodeId.isEmpty) {
      throw StateError('Invalid AnimeWitcher episode data');
    }
    final servers = await _fetchServers(route.animeId, route.episodeId);
    final output = <StreamResult>[];
    final seen = <String>{};
    for (final server in servers) {
      String streamUrl = '';
      Map<String, String>? headers;
      String source = server.name;

      if (_isPixelDrain(server)) {
        final id = _pixelDrainId(server.link);
        if (id.isNotEmpty) {
          streamUrl = 'https://pixeldrain.com/api/file/${Uri.encodeComponent(id)}';
        } else if (server.directLink || _isDirectMediaUrl(server.link)) {
          streamUrl = server.link;
        }
        headers = const <String, String>{
          'User-Agent': _userAgent,
          'Referer': 'https://pixeldrain.com/',
          'Origin': 'https://pixeldrain.com',
        };
        source = server.quality.isEmpty ? 'PixelDrain' : 'PixelDrain ${server.quality}';
      } else if (server.directLink || _isDirectMediaUrl(server.link)) {
        streamUrl = server.link;
        headers = <String, String>{
          'User-Agent': _userAgent,
          'Referer': server.originalLink.isNotEmpty ? server.originalLink : server.link,
        };
        source = server.quality.isEmpty ? server.name : '${server.name} ${server.quality}';
      }

      if (streamUrl.isEmpty || !seen.add(streamUrl)) continue;
      output.add(StreamResult(url: streamUrl, source: source, headers: headers));
    }
    return output;
  }
}

class _AnimeRoute {
  const _AnimeRoute({required this.animeId, required this.hit});
  final String animeId;
  final Map<String, dynamic> hit;
}

class _EpisodeRoute {
  const _EpisodeRoute(this.animeId, this.episodeId);
  final String animeId;
  final String episodeId;
}

class _EpisodeRecord {
  const _EpisodeRecord({
    required this.id,
    required this.number,
    required this.title,
    required this.image,
  });
  final String id;
  final int number;
  final String title;
  final String image;
}

class _ServerRecord {
  const _ServerRecord({
    required this.name,
    required this.link,
    required this.quality,
    required this.originalLink,
    required this.directLink,
    required this.visible,
  });
  final String name;
  final String link;
  final String quality;
  final String originalLink;
  final bool directLink;
  final bool visible;
}

class _HomePlan {
  const _HomePlan({required this.index, this.query = '', this.recent = false});
  final String index;
  final String query;
  final bool recent;
}

class _SeasonInfo {
  const _SeasonInfo(this.season, this.year);
  final String season;
  final int year;
}
