import 'package:animewitcher/core/account/animewitcher_comment_models.dart';
import 'package:animewitcher/core/account/firestore_rest_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saving a rating PATCHes anime_list/{id}/ratings/{userDocId}.rate',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'name':
                    'projects/animewitcher-1c66d/databases/(default)'
                    '/documents/anime_list/naruto/ratings/user-doc',
                'fields': <String, dynamic>{
                  'rate': <String, dynamic>{'integerValue': '8'},
                },
              },
            ),
          );
        },
      ),
    );
    final client = FirestoreRestClient(dio: dio);
    await client.setDocument(
      animeWitcherAnimeRatingPath('naruto', 'user-doc'),
      const <String, dynamic>{'rate': 8},
      'id-token',
      merge: true,
    );

    final request = requests.single;
    expect(request.method, 'PATCH');
    expect(
      request.path,
      endsWith('/documents/anime_list/naruto/ratings/user-doc'),
    );
    expect(request.queryParameters['updateMask.fieldPaths'], <String>['rate']);
    final payload = Map<String, dynamic>.from(request.data as Map);
    expect(payload['fields'], <String, dynamic>{
      'rate': <String, dynamic>{'integerValue': '8'},
    });
  });

  test('clearing a rating deletes the ratings document', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
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
    final client = FirestoreRestClient(dio: dio);
    await client.deleteDocument(
      animeWitcherAnimeRatingPath('naruto', 'user-doc'),
      'id-token',
    );

    expect(requests.single.method, 'DELETE');
    expect(
      requests.single.path,
      endsWith('/documents/anime_list/naruto/ratings/user-doc'),
    );
  });

  test('published reviews query the reviews collection, not comments', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: const <Map<String, dynamic>>[],
            ),
          );
        },
      ),
    );
    final client = FirestoreRestClient(dio: dio);
    await client.queryPublishedComments('anime_list/naruto/reviews');

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/documents/anime_list/naruto:runQuery'));
    final payload = Map<String, dynamic>.from(request.data as Map);
    final query = Map<String, dynamic>.from(payload['structuredQuery'] as Map);
    expect(query['from'], <Map<String, dynamic>>[
      <String, dynamic>{'collectionId': 'reviews'},
    ]);
    final where = Map<String, dynamic>.from(query['where'] as Map);
    final filter = Map<String, dynamic>.from(where['fieldFilter'] as Map);
    expect(filter['field'], <String, dynamic>{'fieldPath': 'published'});
  });
}
