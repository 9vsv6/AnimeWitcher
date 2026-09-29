import 'package:animewitcher/features/search/presentation/search_domain.dart';
import 'package:animewitcher/features/search/presentation/search_provider.dart';
import 'package:animewitcher/features/search/presentation/widgets/search_header_bar.dart';
import 'package:animewitcher/features/search/presentation/widgets/search_glass_surface.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _IdleSearchNotifier extends PagedSearchNotifier {
  @override
  SearchAggregateState build() => const SearchAggregateState();
}

void main() {
  testWidgets('iOS puts the search actions where every platform does', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (_) async => null,
    );
    await tester.binding.setSurfaceSize(const Size(428, 300));

    final controller = TextEditingController();
    final searchFocus = FocusNode();
    final clearFocus = FocusNode();
    Future<Rect> actionsOn(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchPagedResultsProvider.overrideWith(_IdleSearchNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(428, 300),
                padding: EdgeInsets.only(right: 59),
              ),
              child: Scaffold(
                body: SearchHeaderBar(
                  textController: controller,
                  searchFocusNode: searchFocus,
                  clearButtonFocusNode: clearFocus,
                  onSubmitted: (_) {},
                  onChanged: (_) {},
                  onShowFilters: () {},
                  onSortSelected: (_) {},
                  sortValue: 'favorites',
                  sortItems: const <AppleNativeMenuItem>[
                    AppleNativeMenuItem(
                      value: 'favorites',
                      label: 'Favorites',
                      systemImage: 'star.fill',
                    ),
                  ],
                  sortIcon: Icons.star_rounded,
                  sortSystemImage: 'star.fill',
                  sortTooltip: 'Sort',
                  activeFilterCount: 0,
                  isFilterLoading: false,
                  showSort: true,
                  showFilter: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getRect(
        find.byKey(const ValueKey('search-action-capsule')),
      );
    }

    try {
      // The native glass header iOS once lined up with is retired: iOS lays
      // the bar out as every other platform does.
      final ios = await actionsOn(TargetPlatform.iOS);
      final android = await actionsOn(TargetPlatform.android);
      expect(ios, android);
    } finally {
      controller.dispose();
      searchFocus.dispose();
      clearFocus.dispose();
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    }
  });

  testWidgets(
    'character search header keeps only the filter action, which picks the category',
    (tester) async {
      final controller = TextEditingController();
      final searchFocus = FocusNode();
      final clearFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(searchFocus.dispose);
      addTearDown(clearFocus.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchPagedResultsProvider.overrideWith(_IdleSearchNotifier.new),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SearchHeaderBar(
                textController: controller,
                searchFocusNode: searchFocus,
                clearButtonFocusNode: clearFocus,
                onSubmitted: (_) {},
                onChanged: (_) {},
                onShowFilters: () {},
                onSortSelected: (_) {},
                sortValue: 'favorites',
                sortItems: const <AppleNativeMenuItem>[
                  AppleNativeMenuItem(value: 'favorites', label: 'Favorites'),
                ],
                sortIcon: Icons.star_rounded,
                sortSystemImage: 'star.fill',
                sortTooltip: 'Sort',
                activeFilterCount: 2,
                isFilterLoading: false,
                showSort: false,
                showFilter: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byTooltip('Search domain'), findsNothing);
      expect(find.byTooltip('Sort'), findsNothing);
      expect(find.byTooltip('الفلاتر'), findsOneWidget);
    },
  );

  testWidgets('search field matches the library pill geometry in Arabic', (
    tester,
  ) async {
    final controller = TextEditingController();
    final searchFocus = FocusNode();
    final clearFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(searchFocus.dispose);
    addTearDown(clearFocus.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchPagedResultsProvider.overrideWith(_IdleSearchNotifier.new),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchHeaderBar(
              textController: controller,
              searchFocusNode: searchFocus,
              clearButtonFocusNode: clearFocus,
              onSubmitted: (_) {},
              onChanged: (_) {},
              onShowFilters: () {},
              onSortSelected: (_) {},
              sortValue: 'favorites',
              sortItems: const <AppleNativeMenuItem>[
                AppleNativeMenuItem(value: 'favorites', label: 'Favorites'),
              ],
              sortIcon: Icons.star_rounded,
              sortSystemImage: 'star.fill',
              sortTooltip: 'Sort',
              activeFilterCount: 0,
              isFilterLoading: false,
              showSort: false,
              showFilter: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final fieldFinder = find.byType(TextField);
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.textDirection, TextDirection.rtl);
    expect(Directionality.of(tester.element(fieldFinder)), TextDirection.rtl);

    final surface = find.byType(SearchGlassSurface);
    final container = tester.widget<AnimatedContainer>(
      find.descendant(of: surface, matching: find.byType(AnimatedContainer)),
    );
    final decoration = container.decoration! as BoxDecoration;
    final radius = decoration.borderRadius! as BorderRadius;
    expect(container.constraints?.maxHeight ?? SearchGlassSurface.height, 42);
    expect(radius.topLeft.x, 99);
    expect(decoration.border, isNull);
  });

  testWidgets('Arabic search hint follows the selected search domain', (
    tester,
  ) async {
    final controller = TextEditingController();
    final searchFocus = FocusNode();
    final clearFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(searchFocus.dispose);
    addTearDown(clearFocus.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchPagedResultsProvider.overrideWith(_IdleSearchNotifier.new),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchHeaderBar(
              textController: controller,
              searchFocusNode: searchFocus,
              clearButtonFocusNode: clearFocus,
              onSubmitted: (_) {},
              onChanged: (_) {},
              onShowFilters: () {},
              onSortSelected: (_) {},
              sortValue: 'favorites',
              sortItems: const <AppleNativeMenuItem>[
                AppleNativeMenuItem(value: 'favorites', label: 'Favorites'),
              ],
              sortIcon: Icons.star_rounded,
              sortSystemImage: 'star.fill',
              sortTooltip: 'Sort',
              activeFilterCount: 0,
              isFilterLoading: false,
              showSort: true,
              showFilter: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchHeaderBar)),
    );
    for (final entry in <(SearchDomain, String)>[
      (SearchDomain.anime, 'ابحث عن انمي'),
      (SearchDomain.manga, 'ابحث عن مانجا'),
      (SearchDomain.all, 'ابحث عن الكل'),
      (SearchDomain.animation, 'ابحث عن انميشن'),
      (SearchDomain.characters, 'ابحث عن شخصيات'),
    ]) {
      container.read(searchDomainProvider.notifier).set(entry.$1);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        entry.$2,
      );
    }
  });

  testWidgets('character search expands into the missing sort space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    final searchFocus = FocusNode();
    final clearFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(searchFocus.dispose);
    addTearDown(clearFocus.dispose);

    Future<double> searchWidth({required bool showSort}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchPagedResultsProvider.overrideWith(_IdleSearchNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SearchHeaderBar(
                textController: controller,
                searchFocusNode: searchFocus,
                clearButtonFocusNode: clearFocus,
                onSubmitted: (_) {},
                onChanged: (_) {},
                onShowFilters: () {},
                onSortSelected: (_) {},
                sortValue: 'favorites',
                sortItems: const <AppleNativeMenuItem>[
                  AppleNativeMenuItem(value: 'favorites', label: 'Favorites'),
                ],
                sortIcon: Icons.star_rounded,
                sortSystemImage: 'star.fill',
                sortTooltip: 'Sort',
                activeFilterCount: 0,
                isFilterLoading: false,
                showSort: showSort,
                showFilter: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getRect(find.byType(SearchGlassSurface)).width;
    }

    final regular = await searchWidth(showSort: true);
    final characters = await searchWidth(showSort: false);

    expect(characters, greaterThan(regular + 30));
  });
}
