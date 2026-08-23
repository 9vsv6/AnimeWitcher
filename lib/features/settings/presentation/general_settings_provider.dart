import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/navigation/taskbar_destination.dart';
import '../../../core/storage/settings_repository.dart';

part 'general_settings_provider.g.dart';

class GeneralSettings {
  final String defaultHomeScreen;
  final bool alwaysOnTop;
  final List<String> taskbarOrder;
  final Set<String> hiddenTaskbarItems;
  final String? downloadDirectory;
  final int downloadConcurrency;
  final int downloadChunks;

  const GeneralSettings({
    this.defaultHomeScreen = '/home',
    this.alwaysOnTop = false,
    this.taskbarOrder = defaultTaskbarOrderIds,
    this.hiddenTaskbarItems = const <String>{},
    this.downloadDirectory,
    this.downloadConcurrency = 3,
    this.downloadChunks = 1,
  });

  GeneralSettings copyWith({
    String? defaultHomeScreen,
    bool? alwaysOnTop,
    List<String>? taskbarOrder,
    Set<String>? hiddenTaskbarItems,
    String? downloadDirectory,
    bool clearDownloadDirectory = false,
    int? downloadConcurrency,
    int? downloadChunks,
  }) {
    return GeneralSettings(
      defaultHomeScreen: defaultHomeScreen ?? this.defaultHomeScreen,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      taskbarOrder: taskbarOrder ?? this.taskbarOrder,
      hiddenTaskbarItems: hiddenTaskbarItems ?? this.hiddenTaskbarItems,
      downloadDirectory: clearDownloadDirectory
          ? null
          : (downloadDirectory ?? this.downloadDirectory),
      downloadConcurrency:
          downloadConcurrency ?? this.downloadConcurrency,
      downloadChunks: downloadChunks ?? this.downloadChunks,
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
      defaultHomeScreen: resolveInitialTaskbarRoute(
        repository.getDefaultHomeScreen(),
        order,
        hidden,
      ),
      alwaysOnTop: repository.isAlwaysOnTop(),
      taskbarOrder: order,
      hiddenTaskbarItems: hidden,
      downloadDirectory: repository.getDownloadDirectory(),
      downloadConcurrency: repository.getDownloadConcurrency(),
      downloadChunks: repository.getDownloadChunks(),
    );
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

  Future<void> setDownloadDirectory(String? path) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setDownloadDirectory(path);
    state = path == null
        ? state.copyWith(clearDownloadDirectory: true)
        : state.copyWith(downloadDirectory: path);
  }

  Future<void> setDownloadConcurrency(int value) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setDownloadConcurrency(value);
    state = state.copyWith(downloadConcurrency: value);
  }

  Future<void> setDownloadChunks(int value) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setDownloadChunks(value);
    state = state.copyWith(downloadChunks: value);
  }

}
