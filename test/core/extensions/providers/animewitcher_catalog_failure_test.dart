import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/core/extensions/providers/animewitcher_native_provider.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestStorageService extends StorageService {
  @override
  bool isHighQualityPostersEnabled() => true;

  @override
  bool isEpisodeImagesFromAniZipEnabled() => false;
}

AnimeWitcherNativeProvider _providerWithUnavailableCatalog() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: options.method == 'POST' ? 503 : 200,
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
  test('search page reports catalog transport failure instead of empty results',
      () async {
    await expectLater(
      _providerWithUnavailableCatalog().searchPage(
        'test',
        const ProviderSearchFilters(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('home reports unavailable section configuration instead of blank success',
      () async {
    await expectLater(
      _providerWithUnavailableCatalog().getHome(),
      throwsA(isA<StateError>()),
    );
  });
}
