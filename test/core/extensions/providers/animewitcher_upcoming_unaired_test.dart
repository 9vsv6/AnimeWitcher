import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/providers/animewitcher_native_provider.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestStorageService extends StorageService {
  @override
  bool isHighQualityPostersEnabled() => false;

  @override
  bool isEpisodeImagesFromAniZipEnabled() => false;
}

AnimeWitcherNativeProvider _provider(Dio dio) =>
    AnimeWitcherNativeProvider(dio, SettingsRepository(_TestStorageService()));

String _paramsOf(RequestOptions options) {
  final data = options.data;
  if (data is Map) {
    return data['params']?.toString() ?? '';
  }
  return data?.toString() ?? '';
}

String _decodedFilters(RequestOptions options) {
  final params = Uri.splitQueryString(
    _paramsOf(options),
    encoding: utf8,
  );
  return params['filters'] ?? '';
}

Map<String, dynamic> _unairedHit(String id, {String title = ''}) {
  return <String, dynamic>{
    'objectID': id,
    'anime_id': id,
    'name': title.isEmpty ? 'قادم $id' : title,
    'path': '/anime/$id',
    'details': <String, dynamic>{
      'state': 'لم يتم بثه بعد',
      'season': 'شتاء عام 2027',
    },
    'poster': <String, dynamic>{
      'large': 'https://cdn.example.test/$id.jpg',
    },
  };
}

({Dio dio, List<RequestOptions> requests}) _stubDio({
  required List<Map<String, dynamic>> hits,
  int nbPages = 3,
}) {
  final requests = <RequestOptions>[];
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final url = options.uri.toString();
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: url.contains('algolia.net')
                ? <String, dynamic>{'hits': hits, 'nbPages': nbPages}
                : <String, dynamic>{},
          ),
        );
      },
    ),
  );
  return (dio: dio, requests: requests);
}

void main() {
  test('coming soon queries unaired titles, not the next season', () async {
    final stub = _stubDio(
      hits: <Map<String, dynamic>>[
        _unairedHit('soon-1', title: 'عمل لم يُبث'),
        _unairedHit('soon-2'),
      ],
    );

    final page = await _provider(stub.dio).getUpcomingPage(limit: 30);

    final algolia = stub.requests.where(
      (request) => request.uri.host.contains('algolia.net'),
    );
    expect(algolia, isNotEmpty);
    expect(
      stub.requests.any(
        (request) => request.uri.path.contains('home_sections'),
      ),
      isFalse,
      reason: 'coming soon must not load the next-season home rail',
    );

    final query = algolia.first;
    expect(query.uri.path, contains('/indexes/series/query'));
    final filters = _decodedFilters(query);
    expect(filters, contains('details.state:'));
    expect(filters, contains('لم يتم بثه بعد'));
    expect(filters, isNot(contains('details.season')));
    expect(filters, isNot(contains('الموسم القادم')));

    expect(page.items, hasLength(2));
    expect(page.items.first.title, 'عمل لم يُبث');
    expect(
      page.items.every((item) => item.status == ShowStatus.upcoming),
      isTrue,
    );
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 30);

    final artifacts = Directory('/opt/cursor/artifacts');
    if (artifacts.existsSync()) {
      File('${artifacts.path}/coming_soon_algolia_filters.txt').writeAsStringSync(
        'index: ${query.uri.path}\nfilters: $filters\n',
      );
    }
  });

  test('coming soon pagination asks Algolia for the next unaired page', () async {
    final stub = _stubDio(hits: <Map<String, dynamic>>[_unairedHit('p2')]);

    await _provider(stub.dio).getUpcomingPage(offset: 30, limit: 30);

    final query = stub.requests.firstWhere(
      (request) => request.uri.host.contains('algolia.net'),
    );
    final params = Uri.splitQueryString(
      _paramsOf(query),
      encoding: utf8,
    );
    expect(params['page'], '1');
    expect(params['filters'], contains('لم يتم بثه بعد'));
  });
}
