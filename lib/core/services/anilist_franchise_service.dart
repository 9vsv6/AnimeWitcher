import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entity/multimedia_item.dart';
import '../network/dio_client_provider.dart';

final aniListFranchiseServiceProvider = Provider<AniListFranchiseService>((
  ref,
) {
  return AniListFranchiseService(ref.watch(dioClientProvider));
});

class AniListFranchiseNode {
  const AniListFranchiseNode({required this.item, required this.related});

  final MultimediaItem item;
  final List<MultimediaItem> related;
}

class AniListFranchiseService {
  AniListFranchiseService(this._dio);

  static const String _endpoint = 'https://graphql.anilist.co';
  static const int _cacheMax = 300;
  static final Map<int, AniListFranchiseNode?> _cache =
      <int, AniListFranchiseNode?>{};

  final Dio _dio;

  Future<AniListFranchiseNode?> fetchByMalId(int malId) async {
    if (malId <= 0) return null;
    if (_cache.containsKey(malId)) {
      final cached = _cache.remove(malId);
      _cache[malId] = cached;
      return cached;
    }

    const query = r'''
query ($malId: Int) {
  Media(idMal: $malId, type: ANIME) {
    id
    idMal
    format
    title { romaji english native }
    synonyms
    startDate { year }
    coverImage { extraLarge large medium }
    relations {
      edges {
        relationType
        node {
          id
          idMal
          format
          title { romaji english native }
          synonyms
          startDate { year }
          coverImage { extraLarge large medium }
        }
      }
    }
  }
}
''';

    final response = await _dio.post<Map<String, dynamic>>(
      _endpoint,
      data: <String, dynamic>{
        'query': query,
        'variables': <String, dynamic>{'malId': malId},
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final media = (response.data?['data'] as Map?)?['Media'];
    if (media is! Map) return null;

    final node = aniListFranchiseNodeFromJson(
      Map<String, dynamic>.from(media),
    );
    if (node == null) return null;

    _cache[malId] = node;
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
    return node;
  }
}

AniListFranchiseNode? aniListFranchiseNodeFromJson(
  Map<String, dynamic> media,
) {
  final item = _aniListItem(media);
  if (item == null) return null;

  final related = <MultimediaItem>[];
  final relations = media['relations'];
  final edges = relations is Map ? relations['edges'] : null;
  if (edges is List) {
    for (final rawEdge in edges) {
      if (rawEdge is! Map) continue;
      final rawNode = rawEdge['node'];
      if (rawNode is! Map) continue;
      final relationType = '${rawEdge['relationType'] ?? ''}'
          .trim()
          .toUpperCase();
      final relatedItem = _aniListItem(
        Map<String, dynamic>.from(rawNode),
        relationType: relationType,
      );
      if (relatedItem != null) related.add(relatedItem);
    }
  }

  return AniListFranchiseNode(item: item, related: related);
}

MultimediaItem? _aniListItem(
  Map<String, dynamic> raw, {
  String? relationType,
}) {
  final malId = (raw['idMal'] as num?)?.toInt();
  if (malId == null || malId <= 0) return null;
  final aniListId = (raw['id'] as num?)?.toInt();
  final title = _bestAniListTitle(raw);
  final format = '${raw['format'] ?? ''}'.trim().toUpperCase();
  final startDate = raw['startDate'];
  final year = startDate is Map ? (startDate['year'] as num?)?.toInt() : null;
  final cover = raw['coverImage'];

  String poster = '';
  if (cover is Map) {
    for (final key in const <String>['extraLarge', 'large', 'medium']) {
      final value = '${cover[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') {
        poster = value;
        break;
      }
    }
  }

  return MultimediaItem(
    title: title,
    url: 'anilist-mal:$malId',
    posterUrl: poster,
    contentType: format == 'MOVIE'
        ? MultimediaContentType.movie
        : MultimediaContentType.anime,
    year: year,
    catalogType: _catalogTypeForAniListFormat(format),
    relationType: relationType,
    source: 'AniList',
    syncData: <String, String>{
      'malId': '$malId',
      'mal_id': '$malId',
      if (aniListId != null) 'anilistId': '$aniListId',
      if (aniListId != null) 'anilist_id': '$aniListId',
      'anilistFormat': format,
    },
  );
}

String _bestAniListTitle(Map<String, dynamic> raw) {
  final title = raw['title'];
  final candidates = <String>[];
  if (title is Map) {
    for (final key in const <String>['english', 'romaji', 'native']) {
      final value = '${title[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') candidates.add(value);
    }
  }
  final synonyms = raw['synonyms'];
  if (synonyms is List) {
    for (final value in synonyms) {
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null') candidates.add(text);
    }
  }
  if (candidates.isEmpty) return 'Anime';

  final marker = RegExp(
    r'(?:\bseason\s*\d+|\d+(?:st|nd|rd|th)\s+season|\bpart\s*\d+|\bcour\s*\d+)',
    caseSensitive: false,
  );
  for (final candidate in candidates) {
    if (marker.hasMatch(candidate)) return candidate;
  }
  return candidates.first;
}

String _catalogTypeForAniListFormat(String format) => switch (format) {
  'TV' || 'TV_SHORT' => 'مسلسل',
  'MOVIE' => 'فيلم',
  'OVA' => 'اوفا',
  'ONA' => 'اونا',
  'SPECIAL' => 'خاصة',
  _ => 'مسلسل',
};
