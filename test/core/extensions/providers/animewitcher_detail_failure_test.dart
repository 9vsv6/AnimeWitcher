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

enum _FirestoreTarget { details, episodes, summary, other }

_FirestoreTarget _targetFor(RequestOptions options) {
  final path = options.uri.path;
  if (path.contains('episodes_summery')) return _FirestoreTarget.summary;
  if (path.contains('/episodes')) return _FirestoreTarget.episodes;
  if (path.contains('anime_list/')) return _FirestoreTarget.details;
  return _FirestoreTarget.other;
}

AnimeWitcherNativeProvider _provider(Dio dio) =>
    AnimeWitcherNativeProvider(dio, SettingsRepository(_TestStorageService()));

Dio _stubDio({
  required int Function(_FirestoreTarget target) statusFor,
  Map<String, dynamic> Function(_FirestoreTarget target)? dataFor,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final target = _targetFor(options);
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: statusFor(target),
            data: dataFor?.call(target) ?? const <String, dynamic>{},
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, dynamic> _animeDocument() {
  return <String, dynamic>{
    'name':
        'projects/animewitcher-1c66d/databases/(default)/documents/anime_list/offline-anime',
    'fields': <String, dynamic>{
      'name': const <String, dynamic>{'stringValue': 'Offline Anime'},
    },
  };
}

void main() {
  const url = 'https://animewitcher.com/anime/offline-anime';

  test(
    'details report an unavailable Firestore document as an error',
    () async {
      await expectLater(
        _provider(_stubDio(statusFor: (_) => 503)).getDetails(url),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'episodes report unavailable collection and summary as an error',
    () async {
      await expectLater(
        _provider(_stubDio(statusFor: (_) => 503)).getEpisodes(url),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'an empty episode collection is a valid catalog, not a network error',
    () async {
      final episodes = await _provider(
        _stubDio(statusFor: (_) => 200),
      ).getEpisodes(url);
      expect(episodes, isEmpty);
    },
  );

  test(
    'a reachable empty episode collection keeps empty even if summary fails',
    () async {
      final episodes = await _provider(
        _stubDio(
          statusFor: (target) => target == _FirestoreTarget.summary ? 503 : 200,
        ),
      ).getEpisodes(url);
      expect(episodes, isEmpty);
    },
  );

  test('failed episode fetches are not cached so retry can succeed', () async {
    var episodeRequests = 0;
    final provider = _provider(
      _stubDio(
        statusFor: (target) {
          if (target != _FirestoreTarget.episodes &&
              target != _FirestoreTarget.summary) {
            return 200;
          }
          episodeRequests += 1;
          return episodeRequests <= 2 ? 503 : 200;
        },
      ),
    );

    await expectLater(provider.getEpisodes(url), throwsA(isA<StateError>()));
    expect(await provider.getEpisodes(url), isEmpty);
  });

  test(
    'failed details documents are not cached so retry can succeed',
    () async {
      var detailRequests = 0;
      final provider = _provider(
        _stubDio(
          statusFor: (target) {
            if (target != _FirestoreTarget.details) return 200;
            detailRequests += 1;
            return detailRequests == 1 ? 503 : 200;
          },
          dataFor: (target) => target == _FirestoreTarget.details
              ? _animeDocument()
              : const <String, dynamic>{},
        ),
      );

      await expectLater(provider.getDetails(url), throwsA(isA<StateError>()));
      final details = await provider.getDetails(url);
      expect(detailRequests, 2);
      expect(details.title, 'Offline Anime');
    },
  );
}
