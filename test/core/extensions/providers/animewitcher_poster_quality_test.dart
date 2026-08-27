import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/core/extensions/providers/animewitcher_native_provider.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:animewitcher/core/storage/storage_service.dart';

const String _smallPoster = 'https://cdn.animewitcher.com/small/one_piece.jpg';
const String _largePoster = 'https://cdn.animewitcher.com/large/one_piece.jpg';

class _PosterQualitySettingsRepository extends SettingsRepository {
  _PosterQualitySettingsRepository() : super(StorageService());

  @override
  bool isHighQualityPostersEnabled() => true;
}

Map<String, dynamic> _algoliaHit({Map<String, dynamic>? poster}) {
  return <String, dynamic>{
    'hits': <Map<String, dynamic>>[
      <String, dynamic>{
        'objectID': 'one_piece',
        'anime_id': 'one_piece',
        'name': 'ون بيس',
        'poster_uri': _smallPoster,
        if (poster != null) 'poster': poster,
      },
    ],
    'nbPages': 1,
  };
}

List<Map<String, dynamic>> get _batchGetResponse => <Map<String, dynamic>>[
  <String, dynamic>{
    'found': <String, dynamic>{
      'name':
          'projects/animewitcher-1c66d/databases/(default)'
          '/documents/anime_list/one_piece',
      'fields': <String, dynamic>{
        'poster': <String, dynamic>{
          'mapValue': <String, dynamic>{
            'fields': <String, dynamic>{
              'large': <String, dynamic>{'stringValue': _largePoster},
              'medium': <String, dynamic>{'stringValue': _smallPoster},
            },
          },
        },
      },
    },
  },
];

/// Dio that answers Algolia queries with [algoliaPayload] and Firestore
/// `batchGet` calls with the poster document, recording every request.
({Dio dio, List<RequestOptions> requests}) _stubDio(
  Map<String, dynamic> algoliaPayload,
) {
  final requests = <RequestOptions>[];
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final url = options.uri.toString();
        dynamic data = <String, dynamic>{};
        if (url.contains('documents:batchGet')) {
          data = _batchGetResponse;
        } else if (url.contains('algolia.net')) {
          data = algoliaPayload;
        }
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: data,
          ),
        );
      },
    ),
  );
  return (dio: dio, requests: requests);
}

AnimeWitcherNativeProvider _provider(Dio dio) =>
    AnimeWitcherNativeProvider(dio, _PosterQualitySettingsRepository());

Iterable<RequestOptions> _batchGets(List<RequestOptions> requests) =>
    requests.where((r) => r.uri.toString().contains('documents:batchGet'));

void main() {
  test('list hits pick up the large poster from anime_list', () async {
    final stub = _stubDio(_algoliaHit());
    final page = await _provider(stub.dio).searchPage(
      'one piece',
      const ProviderSearchFilters(),
    );

    expect(page.items.single.posterUrl, _largePoster);

    final batch = _batchGets(stub.requests).single;
    expect(batch.method, 'POST');
    final payload = Map<String, dynamic>.from(batch.data as Map);
    expect(payload['documents'], <String>[
      'projects/animewitcher-1c66d/databases/(default)'
          '/documents/anime_list/one_piece',
    ]);
    final mask = Map<String, dynamic>.from(payload['mask'] as Map);
    expect(mask['fieldPaths'], <String>['poster', 'poster_uri', 'cover_uri']);
  });

  test('a hit that already carries a large poster is not looked up', () async {
    final stub = _stubDio(
      _algoliaHit(poster: <String, dynamic>{'large': _largePoster}),
    );
    final page = await _provider(stub.dio).searchPage(
      'one piece',
      const ProviderSearchFilters(),
    );

    expect(page.items.single.posterUrl, _largePoster);
    expect(_batchGets(stub.requests), isEmpty);
  });

  test('the poster lookup is cached across pages', () async {
    final stub = _stubDio(_algoliaHit());
    final provider = _provider(stub.dio);

    await provider.searchPage('one piece', const ProviderSearchFilters());
    await provider.searchPage(
      'one piece',
      const ProviderSearchFilters(),
      offset: 30,
    );

    expect(_batchGets(stub.requests), hasLength(1));
  });

  test('items keep their own poster when the lookup fails', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final url = options.uri.toString();
          if (url.contains('documents:batchGet')) {
            handler.reject(
              DioException(requestOptions: options, error: 'offline'),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: url.contains('algolia.net')
                  ? _algoliaHit()
                  : <String, dynamic>{},
            ),
          );
        },
      ),
    );

    final page = await _provider(
      dio,
    ).searchPage('one piece', const ProviderSearchFilters());

    expect(page.items.single.posterUrl, _smallPoster);
  });
}
