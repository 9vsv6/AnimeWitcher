import 'dart:convert';

import 'package:animewitcher/core/network/dio_client_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('series_similar gets rating and year in its original Algolia request', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dio = container.read(dioClientProvider);
    RequestOptions? observed;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          observed = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: const <String, dynamic>{'hits': <dynamic>[]},
            ),
          );
        },
      ),
    );

    final originalAttributes = <String>[
      'objectID',
      'name',
      'poster_uri',
      'order',
      'path',
      'type',
      'poster',
      'tags',
    ];
    final encodedAttributes = Uri.encodeQueryComponent(
      jsonEncode(originalAttributes),
    );

    await dio.post<dynamic>(
      'https://SRCAPP-dsn.algolia.net/1/indexes/series_similar/query',
      data: <String, dynamic>{
        'params': 'query=action&attributesToRetrieve=$encodedAttributes',
      },
    );

    expect(observed, isNotNull);
    final data = Map<String, dynamic>.from(observed!.data as Map);
    final params = Uri.splitQueryString(data['params'] as String, encoding: utf8);
    final attributes = (jsonDecode(params['attributesToRetrieve']!) as List)
        .map((value) => value.toString())
        .toList(growable: false);

    expect(attributes, containsAll(originalAttributes));
    expect(attributes, contains('details'));
    expect(attributes, contains('rating'));
    expect(attributes, contains('year'));
    expect(attributes, contains('imdb_rate'));
    expect(attributes, contains('mal_id'));
  });
}
