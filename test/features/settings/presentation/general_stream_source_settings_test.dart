import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/settings/presentation/general_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/memory_storage_service.dart';

final class _Storage extends MemoryStorageService {
  @override
  T? getPlayerSetting<T>(String key, {T? defaultValue}) =>
      (settings[key] ?? defaultValue) as T?;

  @override
  Future<void> setPlayerSetting(String key, dynamic value) async {
    settings[key] = value;
  }
}

void main() {
  test('stream auto-selection settings persist priorities', () async {
    final storage = _Storage();
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(generalSettingsProvider.notifier);
    expect(container.read(generalSettingsProvider).autoSelectStreamSource, isFalse);

    await notifier.setAutoSelectStreamSource(true);
    await notifier.setStreamServerPriority(const <String>['ST', 'MF', 'PD', 'SF']);
    await notifier.setStreamQualityPriority(
      const <String>['720p', '1080p', '480p', 'متعدد'],
    );

    final state = container.read(generalSettingsProvider);
    expect(state.autoSelectStreamSource, isTrue);
    expect(state.streamServerPriority.first, 'ST');
    expect(state.streamQualityPriority.first, '720p');
  });
}
