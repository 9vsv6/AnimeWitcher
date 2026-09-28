import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/core/extensions/extension_manager.dart';
import 'package:animewitcher/core/providers/episode_sort_provider.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/details/presentation/details_controller.dart';
import 'package:animewitcher/features/library/presentation/downloads_provider.dart';
import 'package:animewitcher/features/library/presentation/history_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/memory_storage_service.dart';

final class _Provider extends AnimeWitcherProvider {
  int detailsCalls = 0;
  int episodeCalls = 0;

  @override
  String get packageName => 'test.anime';

  @override
  String get name => 'Test Anime';

  @override
  String get mainUrl => 'https://example.test';

  @override
  String get version => '1';

  @override
  List<String> get languages => const <String>['ar'];

  @override
  Set<ProviderType> get supportedTypes => const <ProviderType>{
    ProviderType.anime,
  };

  @override
  Future<List<MultimediaItem>> search(
    String query, {
    CancelToken? cancelToken,
  }) async => const <MultimediaItem>[];

  @override
  Future<Map<String, List<MultimediaItem>>> getHome() async =>
      const <String, List<MultimediaItem>>{};

  @override
  Future<MultimediaItem> getDetails(String url) async {
    detailsCalls++;
    return MultimediaItem(
      title: 'Lazy Anime',
      url: url,
      posterUrl: '',
      contentType: MultimediaContentType.anime,
      provider: packageName,
    );
  }

  @override
  Future<List<Episode>> getEpisodes(String url) async {
    episodeCalls++;
    return <Episode>[
      Episode(
        name: 'Episode 1',
        url: 'episode://1',
        season: 1,
        episode: 1,
      ),
    ];
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async =>
      const <StreamResult>[];
}

final class _Manager extends ExtensionManager {
  _Manager(this.provider);
  final AnimeWitcherProvider provider;

  @override
  List<AnimeWitcherProvider> build() => <AnimeWitcherProvider>[provider];
}

final class _AscendingSort extends EpisodeSortAscendingNotifier {
  @override
  bool build() => true;

  @override
  void setAscending(bool value) => state = value;
}

final class _EmptyDownloads extends DownloadsNotifier {
  @override
  Future<List<DownloadItem>> build() async => const <DownloadItem>[];
}

final class _EmptyHistory extends WatchHistory {
  @override
  List<HistoryItem> build() => const <HistoryItem>[];
}

Future<void> _flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('anime details does not request episodes until explicitly opened', () async {
    final provider = _Provider();
    final container = ProviderContainer(
      overrides: [
        extensionManagerProvider.overrideWith(() => _Manager(provider)),
        activeProviderProvider.overrideWithValue(provider),
        episodeSortAscendingProvider.overrideWith(() => _AscendingSort()),
        storageServiceProvider.overrideWithValue(MemoryStorageService()),
        downloadsProvider.overrideWith(() => _EmptyDownloads()),
        watchHistoryProvider.overrideWith(() => _EmptyHistory()),
      ],
    );
    addTearDown(container.dispose);

    const url = 'https://example.test/anime/lazy';
    final item = MultimediaItem(
      title: 'Lazy Anime',
      url: url,
      posterUrl: '',
      contentType: MultimediaContentType.anime,
      provider: provider.packageName,
    );
    // This family is auto-disposed when nobody listens. Keep the tested
    // controller alive while exercising the two explicit load calls.
    final subscription = container.listen<DetailsState>(
      detailsControllerProvider(url),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final controller = container.read(detailsControllerProvider(url).notifier);

    await controller.loadDetails(item);
    await _flush();

    expect(provider.detailsCalls, 1);
    expect(provider.episodeCalls, 0);

    await controller.loadEpisodesOnDemand();
    expect(provider.episodeCalls, 1);

    await controller.loadEpisodesOnDemand();
    expect(provider.episodeCalls, 1);
  });
}
