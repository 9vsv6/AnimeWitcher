import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/navigation/taskbar_destination.dart';
import '../../../core/storage/settings_repository.dart';

part 'general_settings_provider.g.dart';

enum EpisodeNotificationPreference {
  all('all'),
  favoritesAndWatching('favorites_watching'),
  off('off');

  const EpisodeNotificationPreference(this.storageValue);
  final String storageValue;

  static EpisodeNotificationPreference fromStorageValue(String? value) {
    for (final preference in values) {
      if (preference.storageValue == value) return preference;
    }
    return EpisodeNotificationPreference.all;
  }
}

class GeneralSettings {
  final bool watchHistoryEnabled;
  final String defaultHomeScreen;
  final bool alwaysOnTop;
  final String titlePosition;
  final List<String> taskbarOrder;
  final Set<String> hiddenTaskbarItems;
  final EpisodeNotificationPreference episodeNotificationPreference;

  const GeneralSettings({
    this.watchHistoryEnabled = true,
    this.defaultHomeScreen = '/home',
    this.alwaysOnTop = false,
    this.titlePosition = 'below',
    this.taskbarOrder = defaultTaskbarOrderIds,
    this.hiddenTaskbarItems = const <String>{},
    this.episodeNotificationPreference = EpisodeNotificationPreference.all,
  });

  GeneralSettings copyWith({
    bool? watchHistoryEnabled,
    String? defaultHomeScreen,
    bool? alwaysOnTop,
    String? titlePosition,
    List<String>? taskbarOrder,
    Set<String>? hiddenTaskbarItems,
    EpisodeNotificationPreference? episodeNotificationPreference,
  }) {
    return GeneralSettings(
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      defaultHomeScreen: defaultHomeScreen ?? this.defaultHomeScreen,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      titlePosition: titlePosition ?? this.titlePosition,
      taskbarOrder: taskbarOrder ?? this.taskbarOrder,
      hiddenTaskbarItems: hiddenTaskbarItems ?? this.hiddenTaskbarItems,
      episodeNotificationPreference:
          episodeNotificationPreference ?? this.episodeNotificationPreference,
    );
  }
}

@Riverpod(keepAlive: true)
class GeneralSettingsNotifier extends _$GeneralSettingsNotifier {
  @override
  GeneralSettings build() {
    final repository = ref.watch(settingsRepositoryProvider);
    final order = normalizeTaskbarOrder(repository.getTaskbarOrder())
        .map((destination) => destination.id)
        .toList(growable: false);
    final hidden = normalizeHiddenTaskbarItems(
      repository.getHiddenTaskbarItems(),
    );

    return GeneralSettings(
      watchHistoryEnabled: repository.isWatchHistoryEnabled(),
      defaultHomeScreen: resolveInitialTaskbarRoute(
        repository.getDefaultHomeScreen(),
        order,
        hidden,
      ),
      alwaysOnTop: repository.isAlwaysOnTop(),
      titlePosition: repository.getTitlePosition(),
      taskbarOrder: order,
      hiddenTaskbarItems: hidden,
      episodeNotificationPreference:
          EpisodeNotificationPreference.fromStorageValue(
            repository.getEpisodeNotificationPreference(),
          ),
    );
  }

  Future<void> setEpisodeNotificationPreference(
    EpisodeNotificationPreference preference,
  ) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setEpisodeNotificationPreference(preference.storageValue);
    state = state.copyWith(episodeNotificationPreference: preference);
  }

  Future<void> setWatchHistoryEnabled(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setWatchHistoryEnabled(enabled);
    state = state.copyWith(watchHistoryEnabled: enabled);
  }

  Future<void> setDefaultHomeScreen(String path) async {
    final repository = ref.read(settingsRepositoryProvider);
    final resolved = resolveInitialTaskbarRoute(
      path,
      state.taskbarOrder,
      state.hiddenTaskbarItems,
    );
    await repository.setDefaultHomeScreen(resolved);
    state = state.copyWith(defaultHomeScreen: resolved);
  }

  Future<void> setTaskbarPreferences(
    List<String> order,
    Set<String> hidden,
  ) async {
    final repository = ref.read(settingsRepositoryProvider);
    final normalizedOrder = normalizeTaskbarOrder(order)
        .map((destination) => destination.id)
        .toList(growable: false);
    final normalizedHidden = normalizeHiddenTaskbarItems(hidden);
    final resolvedDefault = resolveInitialTaskbarRoute(
      state.defaultHomeScreen,
      normalizedOrder,
      normalizedHidden,
    );

    await Future.wait<void>([
      repository.setTaskbarOrder(normalizedOrder),
      repository.setHiddenTaskbarItems(normalizedHidden),
      if (resolvedDefault != state.defaultHomeScreen)
        repository.setDefaultHomeScreen(resolvedDefault),
    ]);

    state = state.copyWith(
      taskbarOrder: normalizedOrder,
      hiddenTaskbarItems: normalizedHidden,
      defaultHomeScreen: resolvedDefault,
    );
  }

  Future<void> setAlwaysOnTop(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setAlwaysOnTop(enabled);
    state = state.copyWith(alwaysOnTop: enabled);
  }

  Future<void> setTitlePosition(String position) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setTitlePosition(position);
    state = state.copyWith(titlePosition: position);
  }
}
