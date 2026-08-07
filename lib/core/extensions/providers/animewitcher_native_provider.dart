import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html_unescape/html_unescape.dart';

import '../../domain/entity/multimedia_item.dart';
import '../base_provider.dart';

/// Native AnimeWitcher implementation used during the JS-to-native migration.
///
/// It mirrors the current plugin's Firestore/Algolia metadata, independent
/// detail sections, AniZip episode metadata, and MF/ST/PD playback paths while
/// the JavaScript provider remains installed for side-by-side verification.
class AnimeWitcherNativeProvider extends SkyStreamProvider {
  AnimeWitcherNativeProvider(this._dio);

  final Dio _dio;
  final HtmlUnescape _unescape = HtmlUnescape();

  static const String _baseUrl = 'https://animewitcher.com';
  static const String _firestoreProjectId = 'animewitcher-1c66d';
  static const String _defaultAlgoliaAppId = '5UIU27G8CZ';
  static const String _defaultAlgoliaApiKey = 'ef06c5ee4a0d213c011694f18861805c';
  static const String _aniListUrl = 'https://graphql.anilist.co';
  static const String _aniZipUrl = 'https://api.ani.zip/mappings';

  String _algoliaAppId = _defaultAlgoliaAppId;
  String _algoliaApiKey = _defaultAlgoliaApiKey;
  String _officialCurrentSeason = '';
  String _officialNextSeason = '';
  DateTime _remoteConstantsExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _remoteConstantsRequest;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _serverTimeout = Duration(seconds: 6);
  static const Duration _streamTimeout = Duration(seconds: 12);
  static const Duration _mediaFireTimeout = Duration(seconds: 30);
  static const Duration _aniZipTimeout = Duration(seconds: 12);
  static const Duration _remoteConstantsTtl = Duration(hours: 6);
  static const int _previewSize = 10;
  static const int _maxCastItems = 25;
  static const int _maxRelatedItems = 16;
  static const int _maxRecommendations = 12;

  @override
  String get packageName => 'com.fares669.animewitcher.native';

  @override
  String get name => 'AnimeWitcher Native (Beta)';

  @override
  String get mainUrl => _baseUrl;

  @override
  String get version => '0.2.0';

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

  Future<Response<String>?> _getText(
    String url, {
    Duration timeout = _httpTimeout,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          headers: <String, String>{
            'User-Agent': _userAgent,
            ...?headers,
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      return response;
    } on DioException {
      return null;
    }
  }

  Future<void> _refreshRemoteConstants({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _remoteConstantsExpiresAt.isAfter(now)) return;
    final inFlight = _remoteConstantsRequest;
    if (inFlight != null) return inFlight;

    final request = () async {
      final payload = await _getJson(_firestoreUrl('Settings/constants'));
      final fields = payload == null
          ? <String, dynamic>{}
          : _firestoreFields(payload['fields']);
      final settings = _map(fields['search_settings']);
      final seasons = _map(fields['seasons']);
      final appId = _text(
        settings['app_id_v3'] ?? settings['app_id'] ?? settings['application_id'],
      );
      final apiKey = _text(settings['api_key'] ?? settings['search_api_key']);
      if (appId.isNotEmpty) _algoliaAppId = appId;
      if (apiKey.isNotEmpty) _algoliaApiKey = apiKey;
      final current = _text(seasons['current'] ?? fields['current_season']);
      final next = _text(seasons['next'] ?? fields['next_season']);
      if (current.isNotEmpty) _officialCurrentSeason = current;
      if (next.isNotEmpty) _officialNextSeason = next;
      _remoteConstantsExpiresAt = now.add(_remoteConstantsTtl);
    }();
    _remoteConstantsRequest = request;
    try {
      await request;
    } finally {
      if (identical(_remoteConstantsRequest, request)) {
        _remoteConstantsRequest = null;
      }
    }
  }

  String _algoliaUrl(String index) {
    return 'https://$_algoliaAppId-dsn.algolia.net/1/indexes/'
        '${Uri.encodeComponent(index)}/query';
  }

  Map<String, String> get _algoliaHeaders => <String, String>{
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
    await _refreshRemoteConstants();
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
        return _HomePlan(
          index: 'series',
          query: _officialCurrentSeason.isNotEmpty
              ? _officialCurrentSeason
              : _seasonLabel(_currentSeason()),
        );
      case 'أنميات الموسم القادم':
        return _HomePlan(
          index: 'series',
          query: _officialNextSeason.isNotEmpty
              ? _officialNextSeason
              : _seasonLabel(_nextSeason(_currentSeason())),
        );
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
    await _refreshRemoteConstants();
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

  Future<dynamic> _postAny(
    String url,
    Map<String, dynamic> body, {
    Duration timeout = _httpTimeout,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: body,
        options: _jsonOptions(
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
            ...?headers,
          },
          timeout: timeout,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      return _decodeData(response.data);
    } on DioException {
      return null;
    }
  }

  bool _hasUsefulMetadata(Map<String, dynamic> source) {
    return _text(source['name'] ?? source['english_title']).isNotEmpty &&
        _posterFromHit(source).isNotEmpty &&
        _malId(source) > 0;
  }

  Future<Map<String, dynamic>> _fullAnimeRecord(
    String animeId,
    Map<String, dynamic> partial,
  ) async {
    if (_hasUsefulMetadata(partial)) return partial;
    final queryText = _text(partial['name'] ?? partial['english_title'] ?? animeId);
    final payload = await _algoliaQuery(
      'series',
      query: queryText,
      page: 0,
      hitsPerPage: 12,
      attributes: _searchAttributes,
    );
    final target = animeId.trim().toLowerCase();
    Map<String, dynamic>? fallback;
    for (final raw in _list(payload['hits'])) {
      final hit = _map(raw);
      if (hit.isEmpty) continue;
      fallback ??= hit;
      if (_animeIdFromHit(hit).trim().toLowerCase() == target) {
        return _mergeMaps(partial, hit);
      }
    }
    return fallback == null ? partial : _mergeMaps(partial, fallback);
  }

  Future<Map<String, dynamic>> _detailSource(String url) async {
    final route = _parseAnimeUrl(url);
    if (route.animeId.isEmpty) {
      throw StateError('AnimeWitcher anime id is missing');
    }
    final document = await _fetchAnimeDocument(route.animeId);
    var source = _mergeMaps(route.hit, document);
    if (!_hasUsefulMetadata(source)) {
      source = await _fullAnimeRecord(route.animeId, source);
      source = _mergeMaps(source, document);
    }
    return source;
  }

  double? _scoreFromHit(Map<String, dynamic> source) {
    final details = _map(source['details']);
    final rating = _map(source['rating']);
    for (final raw in <dynamic>[details['mal_score'], rating['rate'], source['score']]) {
      final value = raw is num ? raw.toDouble() : double.tryParse(_text(raw));
      if (value != null && value > 0) return value;
    }
    return null;
  }

  int? _durationFromHit(Map<String, dynamic> source) {
    final details = _map(source['details']);
    for (final raw in <dynamic>[details['duration'], source['duration']]) {
      if (raw is num && raw.toInt() > 0) return raw.toInt();
      final match = RegExp(r'\d+').firstMatch(_normalizeDigits(_text(raw)));
      final value = match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
      if (value > 0) return value;
    }
    return null;
  }

  @override
  Future<MultimediaItem> getDetails(String url) async {
    final route = _parseAnimeUrl(url);
    final source = await _detailSource(url);
    final details = _map(source['details']);
    final title = _text(source['name'] ?? source['english_title'] ?? route.animeId);
    final description = _decodeHtml(
      source['story'] ?? source['description'] ?? details['story'] ?? details['description'],
    );
    final malId = _malId(source);
    final poster = _posterFromHit(source);
    final syncData = <String, String>{};
    if (malId > 0) {
      syncData['malId'] = '$malId';
      syncData['mal_id'] = '$malId';
    }
    final englishTitle = _text(details['english_title'] ?? source['english_title']);
    if (englishTitle.isNotEmpty) syncData['awEnglishTitle'] = englishTitle;
    final age = _text(details['age']);
    if (age.isNotEmpty) syncData['awAge'] = age;
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
      score: _scoreFromHit(source),
      duration: _durationFromHit(source),
      status: _statusFromHit(source),
      tags: _stringList(source['tags']),
      contentRating: age.isEmpty ? null : age,
      syncData: syncData.isEmpty ? null : syncData,
      source: 'AnimeWitcher',
    );
  }

  int _positiveInt(dynamic raw) {
    final match = RegExp(r'\d+').firstMatch(_normalizeDigits(_text(raw)));
    final value = match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    return value > 0 ? value : 0;
  }

  String _pickAniListName(dynamic raw) {
    final source = _map(raw);
    for (final key in const <String>['userPreferred', 'full', 'english', 'romaji', 'native']) {
      final value = _text(source[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _pickAniListImage(dynamic raw) {
    final source = _map(raw);
    for (final key in const <String>['extraLarge', 'large', 'medium']) {
      final value = _text(source[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<Map<String, dynamic>> _aniListMedia(int malId) async {
    if (malId <= 0) return <String, dynamic>{};
    const query = r'''
      query AnimeWitcherSkyStream($idMal: Int!) {
        Media(idMal: $idMal, type: ANIME) {
          id
          idMal
          characters(page: 1, perPage: 25, sort: [ROLE, RELEVANCE, ID]) {
            edges {
              role
              node {
                id
                name { full native userPreferred }
                image { large medium }
              }
              voiceActors(language: JAPANESE, sort: [RELEVANCE, ID]) {
                id
                name { full native userPreferred }
                image { large medium }
              }
            }
          }
          recommendations(page: 1, perPage: 25, sort: [RATING_DESC, ID]) {
            nodes {
              id
              rating
              mediaRecommendation {
                id
                idMal
                type
                format
                status
                title { romaji english native userPreferred }
              }
            }
          }
        }
      }
    ''';
    final payload = await _postJson(
      _aniListUrl,
      <String, dynamic>{
        'query': query,
        'variables': <String, dynamic>{'idMal': malId},
      },
    );
    return _map(_map(payload?['data'])['Media']);
  }

  String _characterRole(dynamic raw) {
    switch (_text(raw).toUpperCase()) {
      case 'MAIN':
        return 'شخصية رئيسية';
      case 'SUPPORTING':
        return 'شخصية مساندة';
      case 'BACKGROUND':
        return 'شخصية ثانوية';
      default:
        return 'شخصية';
    }
  }

  @override
  Future<List<Actor>> getCast(String url) async {
    final source = await _detailSource(url);
    final media = await _aniListMedia(_malId(source));
    final edges = _list(_map(media['characters'])['edges']);
    final output = <Actor>[];
    final seen = <String>{};
    for (final raw in edges) {
      final edge = _map(raw);
      final character = _map(edge['node']);
      final name = _pickAniListName(character['name']);
      final key = _text(character['id']).isEmpty ? name : _text(character['id']);
      if (name.isEmpty || !seen.add(key)) continue;
      Actor? voiceActor;
      for (final voiceRaw in _list(edge['voiceActors'])) {
        final voice = _map(voiceRaw);
        final voiceName = _pickAniListName(voice['name']);
        if (voiceName.isEmpty) continue;
        final voiceImage = _pickAniListImage(voice['image']);
        voiceActor = Actor(
          name: voiceName,
          image: voiceImage.isEmpty ? null : voiceImage,
          role: 'مؤدي الصوت الياباني',
        );
        break;
      }
      final image = _pickAniListImage(character['image']);
      output.add(Actor(
        name: name,
        image: image.isEmpty ? null : image,
        role: _characterRole(edge['role']),
        voiceActor: voiceActor,
      ));
      if (output.length >= _maxCastItems) break;
    }
    return output;
  }

  String _youtubeId(dynamic raw) {
    final source = raw is Map ? _map(raw) : <String, dynamic>{};
    final value = _text(source.isEmpty
        ? raw
        : source['id'] ?? source['youtube_video_id'] ?? source['youtubeVideoId'] ?? source['url']);
    if (value.isEmpty) return '';
    for (final pattern in <RegExp>[
      RegExp(r'youtube\.com/watch\?v=([A-Za-z0-9_-]{6,})', caseSensitive: false),
      RegExp(r'youtube\.com/embed/([A-Za-z0-9_-]{6,})', caseSensitive: false),
      RegExp(r'youtu\.be/([A-Za-z0-9_-]{6,})', caseSensitive: false),
      RegExp(r'youtube\.com/shorts/([A-Za-z0-9_-]{6,})', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(value);
      if (match != null) return match.group(1) ?? '';
    }
    return RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(value) ? value : '';
  }

  @override
  Future<List<Trailer>> getTrailers(String url) async {
    final route = _parseAnimeUrl(url);
    if (route.animeId.isEmpty) return const <Trailer>[];
    final payload = await _getJson(
      _firestoreUrl(
        'anime_list/${Uri.encodeComponent(route.animeId)}/details/anime_trailer',
      ),
    );
    if (payload == null) return const <Trailer>[];
    final fields = _firestoreFields(payload['fields']);
    final id = _youtubeId(fields['youtube_video_id'] ?? fields['youtubeVideoId']);
    if (id.isEmpty) return const <Trailer>[];
    return <Trailer>[Trailer(url: 'https://www.youtube.com/watch?v=$id')];
  }

  Map<String, dynamic> _firestoreDocumentHit(dynamic raw) {
    final document = _map(raw);
    if (document.isEmpty) return <String, dynamic>{};
    final hit = _firestoreFields(document['fields']);
    final name = _text(document['name']);
    final id = name.isEmpty ? '' : name.split('/').last;
    if (id.isNotEmpty) {
      hit.putIfAbsent('objectID', () => id);
      hit.putIfAbsent('anime_id', () => id);
      hit.putIfAbsent('path', () => id);
    }
    return hit;
  }

  Future<List<Map<String, dynamic>>> _runMalIdQuery(
    List<int> ids,
    String valueType,
  ) async {
    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    final values = ids
        .map<Map<String, dynamic>>((id) => valueType == 'integer'
            ? <String, dynamic>{'integerValue': '$id'}
            : <String, dynamic>{'stringValue': '$id'})
        .toList(growable: false);
    final raw = await _postAny(
      'https://firestore.googleapis.com/v1/projects/$_firestoreProjectId/'
      'databases/(default)/documents:runQuery',
      <String, dynamic>{
        'structuredQuery': <String, dynamic>{
          'from': <Map<String, dynamic>>[
            <String, dynamic>{'collectionId': 'anime_list'},
          ],
          'where': <String, dynamic>{
            'fieldFilter': <String, dynamic>{
              'field': <String, dynamic>{'fieldPath': 'mal_id'},
              'op': 'IN',
              'value': <String, dynamic>{
                'arrayValue': <String, dynamic>{'values': values},
              },
            },
          },
          'limit': ids.length,
        },
      },
    );
    final output = <Map<String, dynamic>>[];
    for (final rowRaw in _list(raw)) {
      final hit = _firestoreDocumentHit(_map(rowRaw)['document']);
      if (hit.isNotEmpty) output.add(hit);
    }
    return output;
  }

  Future<Map<int, Map<String, dynamic>>> _resolveMalIds(Iterable<int> rawIds) async {
    final ids = rawIds.where((id) => id > 0).toSet().toList(growable: false);
    final output = <int, Map<String, dynamic>>{};
    for (var start = 0; start < ids.length; start += 10) {
      final end = (start + 10).clamp(0, ids.length).toInt();
      final batch = ids.sublist(start, end);
      for (final hit in await _runMalIdQuery(batch, 'string')) {
        final id = _malId(hit);
        if (id > 0) output[id] = hit;
      }
      final missing = batch.where((id) => !output.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        for (final hit in await _runMalIdQuery(missing, 'integer')) {
          final id = _malId(hit);
          if (id > 0) output[id] = hit;
        }
      }
    }
    return output;
  }

  String _relationType(dynamic raw) {
    final value = _text(raw).replaceAll(RegExp(r'[\s-]+'), '_').toUpperCase();
    return value.isEmpty ? 'OTHER' : value;
  }

  String _relationLabel(String type) {
    const labels = <String, String>{
      'PREQUEL': 'السابق',
      'SEQUEL': 'التالي',
      'PARENT': 'القصة الرئيسية',
      'PARENT_STORY': 'القصة الرئيسية',
      'FULL_STORY': 'القصة الرئيسية',
      'SIDE_STORY': 'قصة جانبية',
      'SPIN_OFF': 'عمل مشتق',
      'ALTERNATIVE': 'نسخة بديلة',
      'ALTERNATIVE_VERSION': 'نسخة بديلة',
      'SUMMARY': 'ملخص',
      'COMPILATION': 'تجميعة',
      'ADAPTATION': 'اقتباس',
      'CHARACTER': 'عمل مرتبط بالشخصيات',
      'SOURCE': 'المصدر',
      'OTHER': 'أخرى',
    };
    return labels[type] ?? 'عمل مرتبط';
  }

  int _relationPriority(String type) {
    const priorities = <String, int>{
      'PREQUEL': 0,
      'SEQUEL': 1,
      'PARENT': 2,
      'PARENT_STORY': 2,
      'FULL_STORY': 2,
      'SIDE_STORY': 3,
      'SPIN_OFF': 4,
      'ALTERNATIVE': 5,
      'ALTERNATIVE_VERSION': 5,
      'SUMMARY': 6,
      'COMPILATION': 7,
      'OTHER': 8,
      'CHARACTER': 9,
      'SOURCE': 10,
      'ADAPTATION': 10,
    };
    return priorities[type] ?? 8;
  }

  List<_RelatedCandidate> _officialRelations(Map<String, dynamic> source) {
    final details = _map(source['details']);
    dynamic raw = source['related_anime_ids'] ??
        source['relatedAnimeIds'] ??
        source['related_anime'] ??
        source['relatedAnime'] ??
        details['related_anime_ids'] ??
        details['relatedAnimeIds'] ??
        details['related_anime'];
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        raw = raw.split(RegExp(r'[\s,|]+')).where((value) => value.isNotEmpty).toList();
      }
    }
    final current = _malId(source);
    final output = <_RelatedCandidate>[];
    final seen = <int>{};
    for (final entry in _list(raw)) {
      final item = entry is Map ? _map(entry) : <String, dynamic>{'mal_id': entry};
      final id = _positiveInt(
        item['mal_id'] ?? item['malId'] ?? item['idMal'] ?? item['malID'],
      );
      if (id <= 0 || id == current || !seen.add(id)) continue;
      final type = _relationType(
        item['relation_type'] ?? item['relationType'] ?? item['type'] ?? item['relation'],
      );
      output.add(_RelatedCandidate(id, type, _relationLabel(type)));
    }
    output.sort((a, b) => _relationPriority(a.type).compareTo(_relationPriority(b.type)));
    return output.take(_maxRelatedItems).toList(growable: false);
  }

  MultimediaItem _relatedItem(
    Map<String, dynamic> hit, {
    String? relationType,
    String? relationLabel,
  }) {
    final item = _mapHit(hit);
    return MultimediaItem(
      title: item.title,
      url: item.url,
      posterUrl: item.posterUrl,
      bannerUrl: item.bannerUrl,
      description: item.description,
      contentType: item.contentType,
      provider: packageName,
      year: item.year,
      status: item.status,
      tags: item.tags,
      relationType: relationType,
      relationLabel: relationLabel,
      source: 'AnimeWitcher',
    );
  }

  @override
  Future<List<MultimediaItem>> getRelated(String url) async {
    final source = await _detailSource(url);
    final relations = _officialRelations(source);
    if (relations.isEmpty) return const <MultimediaItem>[];
    final resolved = await _resolveMalIds(relations.map((item) => item.malId));
    final output = <MultimediaItem>[];
    for (final relation in relations) {
      final hit = resolved[relation.malId];
      if (hit == null) continue;
      output.add(_relatedItem(
        hit,
        relationType: relation.type,
        relationLabel: relation.label,
      ));
    }
    return output;
  }

  @override
  Future<List<MultimediaItem>> getRecommendations(String url) async {
    final source = await _detailSource(url);
    final currentMal = _malId(source);
    final media = await _aniListMedia(currentMal);
    final nodes = _list(_map(media['recommendations'])['nodes'])
        .map(_map)
        .toList(growable: false)
      ..sort((a, b) {
        final left = a['rating'] is num ? (a['rating'] as num).toDouble() : 0.0;
        final right = b['rating'] is num ? (b['rating'] as num).toDouble() : 0.0;
        return right.compareTo(left);
      });
    final ids = <int>[];
    final seen = <int>{};
    for (final recommendation in nodes) {
      final target = _map(recommendation['mediaRecommendation']);
      if (_text(target['type']).isNotEmpty && _text(target['type']).toUpperCase() != 'ANIME') {
        continue;
      }
      final id = _positiveInt(target['idMal']);
      if (id <= 0 || id == currentMal || !seen.add(id)) continue;
      ids.add(id);
      if (ids.length >= _maxRecommendations) break;
    }
    final resolved = await _resolveMalIds(ids);
    return ids
        .map((id) => resolved[id])
        .whereType<Map<String, dynamic>>()
        .map((hit) => _relatedItem(hit))
        .take(_maxRecommendations)
        .toList(growable: false);
  }

  int _normalizeUnixSeconds(dynamic raw) {
    if (raw == null || _text(raw).isEmpty) return 0;
    double? value = raw is num ? raw.toDouble() : double.tryParse(_text(raw));
    if (value == null) {
      final date = DateTime.tryParse(_text(raw));
      if (date != null) value = date.millisecondsSinceEpoch / 1000;
    }
    if (value == null || value <= 0) return 0;
    if (value > 100000000000) value /= 1000;
    return value.floor();
  }

  int _nextEpisodeTimestamp(Map<String, dynamic> source) {
    return _normalizeUnixSeconds(
      source['nextEpTimeInSec'] ??
          source['next_ep_time_in_sec'] ??
          source['nextEpisodeTime'] ??
          source['next_episode_time'] ??
          source['nextAiringAt'] ??
          source['airingAt'],
    );
  }

  @override
  Future<NextAiring?> getNextAiring(String url) async {
    final source = await _detailSource(url);
    if (_statusFromHit(source) == ShowStatus.completed) return null;
    final unixTime = _nextEpisodeTimestamp(source);
    if (unixTime <= 0) return null;
    final route = _parseAnimeUrl(url);
    var records = await _fetchEpisodeSummary(route.animeId);
    if (records.isEmpty) records = await _fetchEpisodeCollection(route.animeId);
    var latest = 0;
    for (final record in records) {
      if (record.number > latest) latest = record.number;
    }
    if (latest <= 0) {
      for (final raw in <dynamic>[
        source['episode_id'],
        source['episode'],
        source['latest_episode'],
        source['last_episode'],
      ]) {
        final value = _positiveInt(raw);
        if (value > latest) latest = value;
      }
    }
    if (latest <= 0) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (unixTime < now - 5 * 60) return null;
    return NextAiring(episode: latest + 1, unixTime: unixTime);
  }

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

  Map<String, dynamic> _aniZipEpisodeFor(
    Map<String, dynamic> payload,
    int number,
  ) {
    if (number <= 0) return <String, dynamic>{};
    final episodes = _map(payload['episodes']);
    final direct = _map(episodes['$number']);
    if (direct.isNotEmpty) return direct;
    for (final raw in episodes.values) {
      final item = _map(raw);
      final absolute = _positiveInt(
        item['absoluteEpisodeNumber'] ?? item['absolute_episode_number'],
      );
      if (absolute == number) return item;
    }
    return <String, dynamic>{};
  }

  int _aniZipSeasonNumber(Map<String, dynamic> payload, int targetEpisode) {
    for (final raw in <dynamic>[
      payload['seasonNumber'],
      payload['season_number'],
      payload['season'],
    ]) {
      final value = _positiveInt(raw);
      if (value > 0) return value;
    }
    for (final number in <int>[targetEpisode, targetEpisode - 1]) {
      final item = _aniZipEpisodeFor(payload, number);
      final value = _positiveInt(
        item['seasonNumber'] ?? item['season_number'] ?? item['season'],
      );
      if (value > 0) return value;
    }
    final counts = <int, int>{};
    for (final raw in _map(payload['episodes']).values) {
      final item = _map(raw);
      final season = _positiveInt(
        item['seasonNumber'] ?? item['season_number'] ?? item['season'],
      );
      if (season > 0) counts[season] = (counts[season] ?? 0) + 1;
    }
    var bestSeason = 0;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount ||
          (entry.value == bestCount && entry.key > bestSeason)) {
        bestSeason = entry.key;
        bestCount = entry.value;
      }
    }
    return bestSeason;
  }

  @override
  Future<List<Episode>> getEpisodeMetadata(String url) async {
    try {
      final route = _parseAnimeUrl(url);
      if (route.animeId.isEmpty) return const <Episode>[];
      final source = await _detailSource(url);
      final malId = _malId(source);
      if (malId <= 0) return const <Episode>[];
      final payload = await _getJson(
        '$_aniZipUrl?mal_id=${Uri.encodeQueryComponent('$malId')}',
        timeout: _aniZipTimeout,
      );
      if (payload == null || _map(payload['episodes']).isEmpty) {
        return const <Episode>[];
      }
      var records = await _fetchEpisodeSummary(route.animeId);
      if (records.isEmpty) records = await _fetchEpisodeCollection(route.animeId);
      if (records.isEmpty) return const <Episode>[];
      var targetEpisode = 0;
      for (final record in records) {
        if (record.number > targetEpisode) targetEpisode = record.number;
      }
      final season = _aniZipSeasonNumber(payload, targetEpisode);
      final seasonNumber = season > 0 ? season : 1;
      final output = <Episode>[];
      for (final record in records) {
        final aniZip = _aniZipEpisodeFor(payload, record.number);
        final local = _positiveInt(
          aniZip['episodeNumber'] ?? aniZip['episode_number'] ?? aniZip['episode'],
        );
        final image = _text(
          aniZip['image'] ??
              aniZip['imageUrl'] ??
              aniZip['image_url'] ??
              aniZip['thumbnail'],
        );
        output.add(Episode(
          name: record.title,
          url: '${Uri.encodeComponent(route.animeId)}|${Uri.encodeComponent(record.id)}',
          season: seasonNumber,
          episode: local > 0 ? local : record.number,
          posterUrl: image.isEmpty ? null : image,
        ));
      }
      return output;
    } catch (_) {
      // Optional metadata must never delay or break the episode list.
      return const <Episode>[];
    }
  }

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

  String _serverFamily(dynamic raw) {
    final value = raw is _ServerRecord ? raw.name : _text(raw);
    final name = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (name == 'PD' || name == 'PIXELDRAIN' || name == 'PIXEL DRAIN') return 'PD';
    if (name == 'ST' || name == 'STREAMTAPE' || name == 'STREAM TAPE') return 'ST';
    if (name == 'MF' ||
        name == 'MF2' ||
        name == 'MD' ||
        name == 'MEDIAFIRE' ||
        name == 'MEDIA FIRE' ||
        name == 'MEDIAFIRE 2' ||
        name == 'MEDIA FIRE 2') {
      return 'MF';
    }
    return '';
  }

  int _qualityNumber(String value) {
    final match = RegExp(r'\d{3,4}').firstMatch(value);
    return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
  }

  String _normalizeQuality(String value) {
    final text = value.toLowerCase();
    if (text.contains('2160') || text.contains('4k')) return '4K';
    if (text.contains('1080') || text.contains('fhd')) return 'FHD';
    if (text.contains('720') || RegExp(r'(^|[^a-z])hd([^a-z]|$)').hasMatch(text)) return 'HD';
    if (text.contains('480') ||
        text.contains('360') ||
        RegExp(r'(^|[^a-z])sd([^a-z]|$)').hasMatch(text)) {
      return 'SD';
    }
    return 'Auto';
  }

  Future<List<_ServerRecord>> _serverSummary(String animeId, String episodeId) async {
    final path = 'anime_list/${Uri.encodeComponent(animeId)}/episodes/'
        '${Uri.encodeComponent(episodeId)}/servers2/all_servers';
    final payload = await _getJson(_firestoreUrl(path), timeout: _serverTimeout);
    if (payload == null) return const <_ServerRecord>[];
    final fields = _firestoreFields(payload['fields']);
    return _list(fields['servers'])
        .map<_ServerRecord>(_serverRecord)
        .where((server) =>
            server.visible &&
            server.name.isNotEmpty &&
            server.link.isNotEmpty &&
            _serverFamily(server).isNotEmpty)
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
      if (server.visible &&
          server.name.isNotEmpty &&
          server.link.isNotEmpty &&
          _serverFamily(server).isNotEmpty) {
        output.add(server);
      }
    }
    return output;
  }

  Future<List<_ServerRecord>> _fetchServers(String animeId, String episodeId) async {
    var servers = await _serverSummary(animeId, episodeId);
    if (servers.isEmpty) servers = await _serverCollection(animeId, episodeId);
    final seen = <String>{};
    final output = servers.where((server) {
      final family = _serverFamily(server);
      return family.isNotEmpty && seen.add('$family|${server.quality}|${server.link}');
    }).toList();
    output.sort((a, b) {
      final quality = _qualityNumber(b.quality).compareTo(_qualityNumber(a.quality));
      if (quality != 0) return quality;
      const priorities = <String, int>{'MF': 0, 'ST': 1, 'PD': 2};
      return (priorities[_serverFamily(a)] ?? 99).compareTo(
        priorities[_serverFamily(b)] ?? 99,
      );
    });
    return output;
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

  bool _isMediaFireSharePage(String value) {
    return RegExp(
      r'^https?://(?:www\.)?mediafire\.com/(?:file|file_premium|download)/',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  bool _isMediaFireDirectHost(String value) {
    final uri = Uri.tryParse(value.trim());
    final host = uri?.host.toLowerCase() ?? '';
    return RegExp(r'^download[^.]*\.mediafire\.com$').hasMatch(host) ||
        host.endsWith('.mediafireusercontent.com') ||
        host == 'mediafireusercontent.com';
  }

  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase();
    if (RegExp(r'(?:streamtape|strtape|streamadblockplus)\.', caseSensitive: false)
            .hasMatch(lower) ||
        _isMediaFireSharePage(lower) ||
        RegExp(r'pixeldrain\.(?:com|net)/u/', caseSensitive: false).hasMatch(lower)) {
      return false;
    }
    return RegExp(
          r'\.(?:m3u8|mp4|mkv|webm|m4v|mov|ts|avi)(?:$|[?#])',
          caseSensitive: false,
        ).hasMatch(url) ||
        lower.contains('/api/file/');
  }

  String _normalizePageEscapes(String value) {
    var text = _unescape.convert(value);
    text = text
        .replaceAll(r'\u003a', ':')
        .replaceAll(r'\u003A', ':')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u002f', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\x3a', ':')
        .replaceAll(r'\x3A', ':')
        .replaceAll(r'\x26', '&')
        .replaceAll(r'\x3d', '=')
        .replaceAll(r'\x3D', '=')
        .replaceAll(r'\x2f', '/')
        .replaceAll(r'\x2F', '/')
        .replaceAll(r'\/', '/');
    return text;
  }

  String _absoluteUrl(String raw, String base) {
    final value = _normalizePageEscapes(raw).trim().replaceAll(RegExp(r"""^[\s"'`]+|[\s"'`]+$"""), '');
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return uri.toString();
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return value;
    try {
      return baseUri.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  String _decodeFlexibleBase64(String raw) {
    var value = _text(raw)
        .replaceFirst(RegExp(r'^data:[^,]*;base64,', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    if (value.isEmpty) return '';
    while (value.length % 4 != 0) value += '=';
    try {
      return utf8.decode(base64.decode(value), allowMalformed: true).trim();
    } catch (_) {
      return '';
    }
  }

  String _mediaFireCandidate(String raw, String pageUrl) {
    final candidate = _absoluteUrl(raw, pageUrl);
    if (candidate.isEmpty || _isMediaFireSharePage(candidate)) return '';
    if (_isMediaFireDirectHost(candidate) ||
        RegExp(r'\.(?:mp4|mkv|webm|m4v|mov|avi|ts)(?:$|[?#])', caseSensitive: false)
            .hasMatch(candidate)) {
      return candidate;
    }
    return '';
  }

  Future<List<StreamResult>> _extractMediaFire(_ServerRecord server) async {
    final quick = RegExp(
      r'mediafire\.com/(?:file|file_premium|download)/([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(server.link)?.group(1);
    final pageUrl = quick == null || quick.isEmpty
        ? server.link
        : 'https://www.mediafire.com/file/${Uri.encodeComponent(quick)}/file';
    final response = await _getText(
      pageUrl,
      timeout: _mediaFireTimeout,
      headers: const <String, String>{
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': 'https://www.mediafire.com/',
        'Origin': 'https://www.mediafire.com',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
      },
    );
    if (response == null) return const <StreamResult>[];
    final finalUrl = response.realUri.toString();
    var playable = _mediaFireCandidate(finalUrl, pageUrl);
    final body = _normalizePageEscapes(response.data ?? '');
    if (playable.isEmpty) {
      final anchorPattern = RegExp(r'<a\b[^>]*>', caseSensitive: false);
      for (final match in anchorPattern.allMatches(body)) {
        final tag = match.group(0) ?? '';
        if (!RegExp(
          r'''\bid\s*=\s*["']downloadButton["']|\baria-label\s*=\s*["']Download file["']|\bclass\s*=\s*["'][^"']*\bpopsok\b''',
          caseSensitive: false,
        ).hasMatch(tag)) {
          continue;
        }
        final href = RegExp(
          r'''\bhref\s*=\s*(?:["']([^"']+)["']|([^\s>]+))''',
          caseSensitive: false,
        ).firstMatch(tag);
        playable = _mediaFireCandidate(href?.group(1) ?? href?.group(2) ?? '', finalUrl);
        if (playable.isNotEmpty) break;
      }
    }
    if (playable.isEmpty) {
      final scrambled = RegExp(
        r'''data-scrambled-url\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final match in scrambled.allMatches(body)) {
        final decoded = _decodeFlexibleBase64(match.group(1) ?? '');
        playable = _mediaFireCandidate(decoded, finalUrl);
        if (playable.isNotEmpty) break;
      }
    }
    if (playable.isEmpty) {
      for (final pattern in <RegExp>[
        RegExp(r'''https?://download[^/\s"'<>\\]+\.mediafire\.com/[^\s"'<>\\]+''', caseSensitive: false),
        RegExp(r'''https?://[^/\s"'<>\\]+\.mediafireusercontent\.com/[^\s"'<>\\]+''', caseSensitive: false),
      ]) {
        final match = pattern.firstMatch(body);
        if (match != null) {
          playable = _mediaFireCandidate(match.group(0) ?? '', finalUrl);
          if (playable.isNotEmpty) break;
        }
      }
    }
    if (playable.isEmpty) return const <StreamResult>[];
    return <StreamResult>[
      StreamResult(
        url: playable,
        source: 'MediaFire - ${_normalizeQuality(server.quality)}',
        headers: <String, String>{
          'User-Agent': _userAgent,
          'Referer': finalUrl.isEmpty ? pageUrl : finalUrl,
          'Accept-Encoding': 'identity',
        },
      ),
    ];
  }

  bool _streamTapeNoiseMatches(String value, String canonical) {
    return value.toLowerCase().replaceAll('g', '') ==
        canonical.toLowerCase().replaceAll('g', '');
  }

  String _canonicalStreamTapeUrl(String raw) {
    var value = _normalizePageEscapes(raw).trim();
    if (value.startsWith('//')) value = 'https:$value';
    if (value.startsWith('/')) value = 'https://streamtape.com$value';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return '';
    var host = uri.host.toLowerCase();
    var endpoint = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (_streamTapeNoiseMatches(host, 'streamtape.com')) host = 'streamtape.com';
    if (_streamTapeNoiseMatches(endpoint, 'get_video')) endpoint = 'get_video';
    final params = <String>[];
    var hasId = false;
    uri.query.split('&').where((part) => part.isNotEmpty).forEach((part) {
      final index = part.indexOf('=');
      var key = index >= 0 ? part.substring(0, index) : part;
      final rest = index >= 0 ? part.substring(index + 1) : '';
      for (final canonical in const <String>['id', 'expires', 'ip', 'token']) {
        if (_streamTapeNoiseMatches(key, canonical)) {
          key = canonical;
          break;
        }
      }
      if (key.toLowerCase() == 'id' && rest.isNotEmpty) hasId = true;
      params.add(index >= 0 ? '$key=$rest' : key);
    });
    if (host != 'streamtape.com' || endpoint != 'get_video' || !hasId) return '';
    return '${uri.scheme.toLowerCase()}://$host/$endpoint?${params.join('&')}';
  }

  String _streamTapeConstructedUrl(String body) {
    final source = _normalizePageEscapes(body);
    final constructed = RegExp(
      r'''innerHTML\s*=\s*["']([^"']+)["']\s*\+\s*\(\s*["']([^"']+)["']\s*\)''',
      caseSensitive: false,
    ).firstMatch(source);
    if (constructed != null) {
      final first = constructed.group(1) ?? '';
      final rawSecond = constructed.group(2) ?? '';
      final second = rawSecond.length > 3 ? rawSecond.substring(3) : rawSecond;
      final value = _canonicalStreamTapeUrl(first + second);
      if (value.isNotEmpty) return value;
    }
    for (final pattern in <RegExp>[
      RegExp(r'''id=["']ideoooolink["'][^>]*>([^<]+)<''', caseSensitive: false),
      RegExp(r'''id=["']robotlink["'][^>]*>([^<]+)<''', caseSensitive: false),
      RegExp(r'''id=["']norobotlink["'][^>]*>([^<]+)<''', caseSensitive: false),
      RegExp(r'''id=["']videolink["'][^>]*>([^<]+)<''', caseSensitive: false),
      RegExp(r'''(?:innerHTML|src)\s*=\s*["'](//[^"']*get[^"']*video[^"']+)["']''', caseSensitive: false),
      RegExp(r'''["'](https?://[^"']*get[^"']*video\?[^"']+)["']''', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      final value = _canonicalStreamTapeUrl(match.group(1) ?? '');
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<List<StreamResult>> _extractStreamTape(_ServerRecord server) async {
    final response = await _getText(
      server.link,
      timeout: _streamTimeout,
      headers: const <String, String>{
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': 'https://streamtape.com/',
        'Origin': 'https://streamtape.com',
      },
    );
    if (response == null) return const <StreamResult>[];
    final tokenUrl = _streamTapeConstructedUrl(response.data ?? '');
    if (tokenUrl.isEmpty) return const <StreamResult>[];
    final playbackUrl = '$tokenUrl${tokenUrl.contains('?') ? '&' : '?'}dl=1';
    return <StreamResult>[
      StreamResult(
        url: playbackUrl,
        source: 'StreamTape - ${_normalizeQuality(server.quality)}',
        headers: <String, String>{
          'User-Agent': _userAgent,
          'Referer': response.realUri.toString(),
          'Origin': 'https://streamtape.com',
          'Accept-Encoding': 'identity',
        },
      ),
    ];
  }

  Future<List<StreamResult>> _resolveServer(_ServerRecord server) async {
    final family = _serverFamily(server);
    if (family.isEmpty) return const <StreamResult>[];
    if (server.directLink || _isDirectMediaUrl(server.link)) {
      final label = family == 'PD' ? 'PixelDrain' : family == 'ST' ? 'StreamTape' : 'MediaFire';
      return <StreamResult>[
        StreamResult(
          url: server.link,
          source: '$label - ${_normalizeQuality(server.quality)}',
          headers: <String, String>{
            'User-Agent': _userAgent,
            'Referer': server.originalLink.isNotEmpty ? server.originalLink : server.link,
          },
        ),
      ];
    }
    if (family == 'PD') {
      final id = _pixelDrainId(server.link);
      if (id.isEmpty) return const <StreamResult>[];
      return <StreamResult>[
        StreamResult(
          url: 'https://pixeldrain.com/api/file/${Uri.encodeComponent(id)}',
          source: 'PixelDrain - ${_normalizeQuality(server.quality)}',
          headers: const <String, String>{
            'User-Agent': _userAgent,
            'Referer': 'https://pixeldrain.com/',
            'Origin': 'https://pixeldrain.com',
          },
        ),
      ];
    }
    if (family == 'ST') return _extractStreamTape(server);
    if (family == 'MF') return _extractMediaFire(server);
    return const <StreamResult>[];
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async {
    final route = _parseEpisodeUrl(url);
    if (route.animeId.isEmpty || route.episodeId.isEmpty) {
      throw StateError('Invalid AnimeWitcher episode data');
    }
    final servers = await _fetchServers(route.animeId, route.episodeId);
    if (servers.isEmpty) return const <StreamResult>[];

    // Native migration currently mirrors the plugin's default FAST preference:
    // PixelDrain first, StreamTape second, MediaFire only when both fail.
    for (final family in const <String>['PD', 'ST', 'MF']) {
      final familyServers = servers.where((server) => _serverFamily(server) == family).toList();
      if (familyServers.isEmpty) continue;
      final groups = await Future.wait(familyServers.map(_resolveServer));
      final seen = <String>{};
      final output = <StreamResult>[];
      for (final group in groups) {
        for (final stream in group) {
          if (stream.url.isEmpty || !seen.add(stream.url)) continue;
          output.add(stream);
        }
      }
      if (output.isNotEmpty) return output;
    }
    return const <StreamResult>[];
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

class _RelatedCandidate {
  const _RelatedCandidate(this.malId, this.type, this.label);
  final int malId;
  final String type;
  final String label;
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
