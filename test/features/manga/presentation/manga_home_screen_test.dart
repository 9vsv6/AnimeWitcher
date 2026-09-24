import 'package:animewitcher/core/domain/entity/manga.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/core/extensions/extension_manager.dart';
import 'package:animewitcher/core/extensions/providers/animewitcher_native_provider.dart';
import 'package:animewitcher/core/navigation/taskbar_destination.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/manga/presentation/manga_home_screen.dart';
import 'package:animewitcher/features/settings/presentation/general_settings_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends StorageService {
  @override
  bool isHighQualityPostersEnabled() => false;

  @override
  bool isEpisodeImagesFromAniZipEnabled() => false;
}

MultimediaItem _manga(String title) => MultimediaItem(
  title: title,
  url: 'https://animewitcher.com/manga/${Uri.encodeComponent(title)}',
  posterUrl: '',
  contentType: MultimediaContentType.manga,
);

final class _MangaSource extends AnimeWitcherNativeProvider {
  _MangaSource() : super(Dio(), SettingsRepository(_Storage()));

  int popularCalls = 0;

  @override
  Future<ProviderMediaPage> searchMangaPage(
    String query,
    ProviderSearchFilters filters, {
    int offset = 0,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    popularCalls++;
    return ProviderMediaPage(
      items: <MultimediaItem>[_manga('Popular One'), _manga('Popular Two')],
      nextOffset: offset + 2,
      hasMore: false,
    );
  }

  @override
  Future<MangaLatestChapterPage> getLatestMangaPage({
    int offset = 0,
    int limit = 30,
  }) async => MangaLatestChapterPage(
    items: <MangaLatestChapter>[
      MangaLatestChapter(
        manga: _manga('Fresh Chapter Manga'),
        chapter: const MangaChapter(
          id: 'c9',
          mangaId: 'm9',
          url: '',
          name: 'الفصل 9',
          number: 9,
        ),
      ),
    ],
    nextOffset: 1,
    hasMore: false,
  );
}

final class _Manager extends ExtensionManager {
  _Manager(this.provider);
  final AnimeWitcherProvider provider;

  @override
  List<AnimeWitcherProvider> build() => <AnimeWitcherProvider>[provider];
}

void main() {
  test('manga has no tab until the viewer turns it on', () {
    const settings = GeneralSettings();
    expect(settings.hiddenTaskbarItems, contains('manga'));
    expect(
      visibleTaskbarDestinations(
        settings.taskbarOrder,
        settings.hiddenTaskbarItems,
      ),
      isNot(contains(TaskbarDestination.manga)),
    );
    expect(
      visibleTaskbarDestinations(settings.taskbarOrder, const <String>{}),
      contains(TaskbarDestination.manga),
    );
  });

  test('the manga tab comes after every existing branch', () {
    expect(TaskbarDestination.manga.branchIndex, 5);
    expect(TaskbarDestination.manga.route, '/manga');
  });

  testWidgets('the manga page shows new chapters and the popular grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _MangaSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extensionManagerProvider.overrideWith(() => _Manager(source)),
        ],
        child: const MaterialApp(home: MangaHomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('New chapters'), findsOneWidget);
    expect(find.text('Fresh Chapter Manga'), findsWidgets);
    expect(find.text('Most read'), findsOneWidget);
    expect(find.text('Popular One'), findsWidgets);
    expect(source.popularCalls, 1);
  });
}
