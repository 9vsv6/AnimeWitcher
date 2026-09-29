import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/settings/presentation/player_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

final class _Storage extends StorageService {
  final Map<String, Object?> playerSettings = <String, Object?>{};

  @override
  T? getPlayerSetting<T>(String key, {T? defaultValue}) =>
      (playerSettings[key] ?? defaultValue) as T?;

  @override
  Future<void> setPlayerSetting(String key, dynamic value) async {
    playerSettings[key] = value;
  }
}

final class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPathProvider = PathProviderPlatform.instance;

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
  });

  test('retargets downloaded Anime4K shaders after the iOS app container moves', () async {
    const oldSupport =
        '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support';
    const newSupport =
        '/var/mobile/Containers/Data/Application/NEW-UUID/Library/Application Support';
    final storage = _Storage()
      ..playerSettings['player_anime4k_shader_dir'] =
          p.join(oldSupport, 'anime4k_shaders');
    PathProviderPlatform.instance = _PathProvider(newSupport);

    final container = ProviderContainer(
      overrides: <Override>[
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final settings = await container.read(playerSettingsProvider.future);

    expect(
      p.normalize(settings.anime4kShaderDirectory),
      p.normalize(p.join(newSupport, 'anime4k_shaders')),
    );
  });
}
