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

AnimeWitcherNativeProvider _providerWithUnavailableFirestore() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 503,
            data: const <String, dynamic>{},
          ),
        );
      },
    ),
  );
  return AnimeWitcherNativeProvider(
    dio,
    SettingsRepository(_TestStorageService()),
  );
}

void main() {
  const url = 'https://animewitcher.com/anime/offline-anime';

  test('details report an unavailable Firestore document as an error',
      () async {
    await expectLater(
      _providerWithUnavailableFirestore().getDetails(url),
      throwsA(isA<StateError>()),
    );
  });

  test('episodes report unavailable collection and summary as an error',
      () async {
    await expectLater(
      _providerWithUnavailableFirestore().getEpisodes(url),
      throwsA(isA<StateError>()),
    );
  });
}
