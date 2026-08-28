import 'dart:convert';

import 'package:animewitcher/core/extensions/providers/animewitcher_native_provider.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _stringField(String value) =>
    <String, dynamic>{'stringValue': value};

Map<String, dynamic> _mapField(Map<String, dynamic> fields) =>
    <String, dynamic>{
      'mapValue': <String, dynamic>{'fields': fields},
    };

Map<String, dynamic> _settingsDocument({bool searchActive = true}) {
  return <String, dynamic>{
    'name':
        'projects/animewitcher-1c66d/databases/(default)/documents/Settings/constants',
    'fields': <String, dynamic>{
      'search_settings': _mapField(<String, dynamic>{
        'app_id_v3': _stringField('SCHEDAPP'),
        'api_key': _stringField('search-key'),
        'browse_api_key': _stringField('browse-key'),
        'is_search_active': <String, dynamic>{'booleanValue': searchActive},
      }),
    },
  };
}

Map<String, dynamic> _document(String id) {
  return <String, dynamic>{
    'name':
        'projects/animewitcher-1c66d/databases/(default)/documents/anime_list/$id',
    'fields': <String, dynamic>{
      'name': <String, dynamic>{'stringValue': 'Anime $id'},
      'show_time': const <String, dynamic>{'stringValue': 'السبت'},
      'poster': <String, dynamic>{
        'mapValue': <String, dynamic>{
          'fields': <String, dynamic>{
            'large': <String, dynamic>{
              'stringValue': 'https://cdn.example.test/$id.jpg',
            },
          },
        },
      },
    },
  };
}

Map<String, dynamic> _algoliaHits() {
  return <String, dynamic>{
    'hits': <Map<String, dynamic>>[
      <String, dynamic>{
        'objectID': 'one',
        'name': 'Anime one',
        'show_time': 'السبت',
      },
      <String, dynamic>{
        'objectID': 'two',
        'name': 'Anime two',
        'show_time': 'السبت',
      },
    ],
    'page': 0,
    'nbPages': 3,
  };
}

bool _isAlgolia(Uri uri) =>
    uri.host.contains('algolia.net') || uri.host.contains('algolianet.com');

({Dio dio, List<RequestOptions> requests}) _stubDio({
  bool searchActive = true,
  int algoliaStatus = 200,
  Map<String, dynamic>? algoliaPayload,
  int runQueryStatus = 200,
  List<Map<String, dynamic>>? runQueryDocuments,
}) {
  final requests = <RequestOptions>[];
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final path = options.uri.path;
        if (path.contains('Settings/constants') &&
            options.uri.host.contains('firestore')) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: _settingsDocument(searchActive: searchActive),
            ),
          );
          return;
        }
        if (_isAlgolia(options.uri)) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: algoliaStatus,
              data: algoliaPayload ?? _algoliaHits(),
            ),
          );
          return;
        }
        if (path.contains(':runQuery')) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: runQueryStatus,
              data: <Map<String, dynamic>>[
                for (final document
                    in runQueryDocuments ??
                        <Map<String, dynamic>>[
                          _document('fs-one'),
                          _document('fs-two'),
                        ])
                  <String, dynamic>{'document': document},
              ],
            ),
          );
          return;
        }
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: const <String, dynamic>{},
          ),
        );
      },
    ),
  );
  return (dio: dio, requests: requests);
}

class _TestStorageService extends StorageService {
  @override
  bool isHighQualityPostersEnabled() => true;

  @override
  bool isEpisodeImagesFromAniZipEnabled() => false;
}

AnimeWitcherNativeProvider _provider(Dio dio) =>
    AnimeWitcherNativeProvider(dio, SettingsRepository(_TestStorageService()));

RequestOptions _algoliaQuery(List<RequestOptions> requests) {
  return requests.singleWhere(
    (request) =>
        _isAlgolia(request.uri) &&
        request.uri.path.endsWith('/indexes/series/query'),
  );
}

void main() {
  test(
    'broadcast schedule uses Algolia series query with show_time and 12 hits',
    () async {
      final stub = _stubDio();

      final page = await _provider(stub.dio).getBroadcastSchedulePage('السبت');

      expect(page.items.map((item) => item.title).toList(), <String>[
        'Anime one',
        'Anime two',
      ]);
      expect(page.nextOffset, 12);
      expect(page.hasMore, isTrue);

      final query = _algoliaQuery(stub.requests);
      expect(query.method, 'POST');
      expect(query.uri.host, startsWith('schedapp-dsn.algolia.net'));
      expect(query.headers['X-Algolia-API-Key'], 'search-key');
      final params = Uri.splitQueryString(
        (query.data as Map)['params'].toString(),
        encoding: utf8,
      );
      expect(params['filters'], contains('show_time:'));
      expect(params['filters'], contains('السبت'));
      expect(params['hitsPerPage'], '12');
      expect(params['page'], '0');
      expect(
        stub.requests.any((request) => request.uri.path.contains(':runQuery')),
        isFalse,
      );
    },
  );

  test('empty Algolia schedule day does not fall back to Firestore', () async {
    final stub = _stubDio(
      algoliaPayload: <String, dynamic>{
        'hits': const <dynamic>[],
        'page': 0,
        'nbPages': 0,
      },
    );

    final page = await _provider(stub.dio).getBroadcastSchedulePage('السبت');

    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(
      stub.requests.any((request) => request.uri.path.contains(':runQuery')),
      isFalse,
    );
  });

  test(
    'Algolia schedule failure falls back to Firestore show_time query',
    () async {
      final stub = _stubDio(algoliaStatus: 503);

      final page = await _provider(stub.dio).getBroadcastSchedulePage('السبت');

      expect(page.items.map((item) => item.title).toList(), <String>[
        'Anime fs-one',
        'Anime fs-two',
      ]);
      final firestore = stub.requests.singleWhere(
        (request) => request.uri.path.contains(':runQuery'),
      );
      final payload = Map<String, dynamic>.from(firestore.data as Map);
      final query = Map<String, dynamic>.from(payload['structuredQuery'] as Map);
      expect(query['limit'], 13);
      final where = Map<String, dynamic>.from(query['where'] as Map);
      final filter = Map<String, dynamic>.from(where['fieldFilter'] as Map);
      expect(filter['field'], <String, dynamic>{'fieldPath': 'show_time'});
      expect(filter['value'], <String, dynamic>{'stringValue': 'السبت'});
    },
  );

  test(
    'broadcast schedule page ignores an unknown day without a network call',
    () async {
      final stub = _stubDio();

      final page = await _provider(
        stub.dio,
      ).getBroadcastSchedulePage('غير معروف');

      expect(page.items, isEmpty);
      expect(page.nextOffset, 0);
      expect(page.hasMore, isFalse);
      expect(stub.requests, isEmpty);
    },
  );

  test('schedule still queries Algolia when is_search_active is false',
      () async {
    final stub = _stubDio(searchActive: false);

    final page = await _provider(stub.dio).getBroadcastSchedulePage('السبت');

    expect(page.items, isNotEmpty);
    final query = _algoliaQuery(stub.requests);
    expect(query.method, 'POST');
    expect(query.headers['X-Algolia-API-Key'], 'search-key');
    expect(
      stub.requests.any((request) => request.uri.path.contains(':runQuery')),
      isFalse,
    );
  });
}
