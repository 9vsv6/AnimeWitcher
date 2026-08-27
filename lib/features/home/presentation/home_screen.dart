import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animewitcher/core/navigation/taskbar_destination.dart';
import 'home_provider.dart';
import 'home_state.dart';
import 'package:animewitcher/features/home/presentation/widgets/continue_watching_section.dart';
import 'package:animewitcher/features/search/presentation/search_provider.dart';
import 'package:animewitcher/features/library/presentation/history_provider.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/media_horizontal_list.dart';
import 'view_all_screen.dart';
import '../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../shared/widgets/loading_indicator.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'package:animewitcher/core/extensions/extension_manager.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/core/router/app_router.dart';
import '../../../shared/widgets/cards_wrapper.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';
import '../../../shared/widgets/apple_liquid_glass.dart';
import '../../../shared/widgets/recoverable_network_state.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/providers/device_info_provider.dart';
import 'widgets/dashboard_header_bar.dart';
import 'widgets/news_section.dart';
import '../../../shared/widgets/taskbar_visibility.dart';
import 'package:animewitcher/features/news/presentation/news_list_screen.dart';
import 'package:animewitcher/features/news/presentation/news_utils.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';

import 'package:animewitcher/core/utils/localized_text.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Hides the platform scrollbar — replaced by a gradient edge hint.
class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBottomFade = ValueNotifier(false);
  final FocusNode _firstActionFocusNode = FocusNode();

  /// Carousel controller exposed by HomeHeroCarousel via [onControllerReady].
  /// Used by DashboardHeaderBar arrows.
  HeroCarouselController? _carouselController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  bool _isWidescreenForScroll() {
    final profile = ref.read(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    return isTv || profile?.isLargeScreen == true || context.isTabletOrLarger;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Track gradient edge hint visibility — fades away near the bottom.
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final showFade = maxScroll > 0 && currentScroll < maxScroll - 10;
    if (showFade != _showBottomFade.value) {
      _showBottomFade.value = showFade;
    }

    // On widescreen there is no mobile AppBar (opacity notifier).
    // Skip all work to avoid per-frame overhead that
    // can stall the rendering pipeline during bounce / direction-change.
    if (_isWidescreenForScroll()) return;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showBottomFade.dispose();
    _firstActionFocusNode.dispose();
    super.dispose();
  }

  void _openNewsArticle(NewsItem item) {
    openNewsUrl(item);
  }

  Future<void> _openLinkedNewsAnime(
    BuildContext context,
    AnimeWitcherProvider provider,
    NewsItem item,
  ) async {
    final animeId = item.animeId?.trim();
    if (animeId == null || animeId.isEmpty) return;

    try {
      final baseUrl = provider.mainUrl.replaceFirst(RegExp(r'/$'), '');
      final details = await provider.getDetails(
        baseUrl + '/watch/' + Uri.encodeComponent(animeId),
      );
      if (!context.mounted) return;
      DetailsRoute(
        $extra: DetailsRouteExtra(item: details),
      ).push<void>(context);
    } catch (_) {
      // The article remains usable even if its linked anime is unavailable.
    }
  }

  void _openNewsList(
    BuildContext context,
    AnimeWitcherProvider provider,
    List<NewsItem> items,
  ) {
    pushOverTaskbar<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NewsListScreen(
          initialItems: items,
          loadPage: (offset, limit) =>
              provider.getNewsPage(offset: offset, limit: limit),
          onOpen: (item) => _openNewsArticle(item),
          onAnimeTap: (item) {
            _openLinkedNewsAnime(context, provider, item);
          },
        ),
      ),
    );
  }

  void _openSearchPage({bool focusKeyboard = false, bool clearQuery = false}) {
    if (clearQuery) {
      ref.read(searchQueryProvider.notifier).set('');
      ref.read(searchSuggestionControllerProvider.notifier).clear();
    }
    const SearchRoute().go(context);
    if (!focusKeyboard && !clearQuery) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (clearQuery) {
        ref.read(searchClearRequestProvider.notifier).request();
      }
      if (focusKeyboard) {
        ref.read(searchFocusRequestProvider.notifier).request();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final homeDataAsync = ref.watch(homeDataProvider);
    final continueWatching = ref.watch(continueWatchingProvider);
    final l10n = AppLocalizations.of(context)!;
    final activeProvider = ref.watch(activeProviderProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    // Use profile?.isLargeScreen so this matches AppScaffold's sidebar
    // decision even when the HomeScreen's context width is narrowed
    // by the sidebar (e.g. iPad portrait).
    final isWidescreen =
        isTv || profile?.isLargeScreen == true || context.isTabletOrLarger;

    // On widescreen: no AppBar, no FAB — we use the DashboardHeaderBar instead.
    // The header lives outside the scroll view in a plain Column so there is
    // no SliverPersistentHeader / pinned-header interaction with scroll
    // physics (which was causing scroll-direction-change jitter on iPad).
    if (isWidescreen) {
      return Scaffold(
        extendBodyBehindAppBar: false,
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DashboardHeaderBar(
                searchFocusNode: _firstActionFocusNode,
                onShowSearch: () => _openSearchPage(focusKeyboard: true),
                onPrevious: _carouselController != null
                    ? () => _carouselController!.previousPage()
                    : null,
                onNext: _carouselController != null
                    ? () => _carouselController!.nextPage()
                    : null,
              ),
            ),
            Expanded(
              child: _buildBody(
                context,
                homeDataAsync,
                continueWatching,
                isWidescreen: true,
              ),
            ),
          ],
        ),
      );
    }

    // Mobile: keep the home controls in the app-wide native toolbar.
    // The same UIKit toolbar instance later morphs into the details actions.
    final usePersistentGlass = appleUsesPersistentLiquidGlassHeader;
    final persistentButtons = <AppleLiquidGlassToolbarButton>[
      AppleLiquidGlassToolbarButton(
        width: 42,
        tooltip: appText(context, english: 'Search', arabic: 'بحث'),
        icon: Icons.search_rounded,
        color: Theme.of(context).colorScheme.primary,
        onPressed: () => _openSearchPage(focusKeyboard: true),
      ),
    ];
    final mobileScaffold = Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            systemOverlayStyle: overlayStyle,
            forceMaterialTransparency: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              l10n.appTitle,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            actions: usePersistentGlass
                ? const <Widget>[SizedBox(width: 58)]
                : [
                    Padding(
                      padding: const EdgeInsets.only(
                        right: LayoutConstants.spacingSm,
                      ),
                      child: Focus(
                        focusNode: _firstActionFocusNode,
                        child: SizedBox.square(
                          dimension: 42,
                          child: AppleLiquidGlassToolbarButton(
                            width: 42,
                            tooltip: appText(
                              context,
                              english: 'Search',
                              arabic: 'بحث',
                            ),
                            icon: Icons.search_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () =>
                                _openSearchPage(focusKeyboard: true),
                          ),
                        ),
                      ),
                    ),
                  ],
          ),
        ),
      ),
      body: _buildBody(context, homeDataAsync, continueWatching),
    );

    if (!usePersistentGlass) return mobileScaffold;
    return ApplePersistentGlassHeaderScope(
      branchIndex: TaskbarDestination.home.branchIndex,
      trailingButtons: persistentButtons,
      child: mobileScaffold,
    );
  }

  bool _isLatestAddedSectionTitle(String title) {
    final normalized = title
        .toLowerCase()
        .replaceAll(RegExp(r'[ً-ٰٟ]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();

    return normalized.contains('اخر الاعمال المضافه') ||
        normalized.contains('الاعمال المضافه حديثا') ||
        normalized.contains('latest additions') ||
        normalized.contains('recently added');
  }

  bool _isMostWatchedAnimationSectionTitle(String title) {
    final normalized = title
        .toLowerCase()
        .replaceAll(RegExp(r'[ً-ٰٟ]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();

    final isAnimation =
        normalized.contains('انميشن') ||
        normalized.contains('انيميشن') ||
        normalized.contains('animation');
    final isMostWatched =
        normalized.contains('الاكثر مشاهده') ||
        normalized.contains('most watched') ||
        normalized.contains('most viewed');
    return isAnimation && isMostWatched;
  }

  List<Widget> _buildProviderSectionsWithNews(
    BuildContext context,
    Map<String, List<MultimediaItem>> data,
    List<NewsItem> news,
    AnimeWitcherProvider provider,
  ) {
    final entries = data.entries
        .where((entry) => entry.key != 'Trending')
        .toList(growable: false);
    var newsAfterIndex = entries.indexWhere(
      (entry) => _isMostWatchedAnimationSectionTitle(entry.key),
    );
    if (newsAfterIndex < 0) {
      newsAfterIndex = entries.indexWhere(
        (entry) => _isLatestAddedSectionTitle(entry.key),
      );
    }
    if (newsAfterIndex < 0 && entries.isNotEmpty) {
      newsAfterIndex = entries.length - 1;
    }

    Widget buildNewsSection() {
      return NewsSection(
        title: Localizations.localeOf(context).languageCode == 'ar'
            ? 'الأخبار'
            : 'News',
        items: news,
        onViewAll: () => _openNewsList(context, provider, news),
        onOpen: _openNewsArticle,
        onAnimeTap: (item) {
          _openLinkedNewsAnime(context, provider, item);
        },
      );
    }

    final sections = <Widget>[];
    if (entries.isEmpty && news.isNotEmpty) {
      sections.add(buildNewsSection());
    }

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      sections.add(
        MediaHorizontalList(
          title: entry.key,
          mediaList: entry.value,
          category: ViewAllCategory.providerContent,
          showViewAll: true,
          fixedPhysicalDirection: true,
          loadViewAllPage: (offset) => provider.getHomeSectionPage(
            entry.key,
            offset: offset,
            limit: provider.viewAllPageSize,
          ),
          onTap: (item) {
            DetailsRoute(
              $extra: DetailsRouteExtra(item: item),
            ).push<void>(context);
          },
          heroTagPrefix: 'home',
          forcePortrait: _isLatestAddedSectionTitle(entry.key),
        ),
      );
      if (news.isNotEmpty && index == newsAfterIndex) {
        sections.add(buildNewsSection());
      }
    }

    return sections;
  }

  Widget _buildBody(
    BuildContext context,
    HomeState state,
    List<HistoryItem> continueWatching, {
    bool isWidescreen = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isResolving = ref.watch(providerResolutionLoadingProvider);

    if (isResolving) {
      return Center(
        child: AppLoadingIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final activeProvider = ref.watch(activeProviderProvider);
    if (activeProvider == null) {
      return _buildNoProviderState(context, l10n, isWidescreen: isWidescreen);
    }

    return switch (state) {
      HomeLoading() => _withGradientEdgeHint(
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildCarouselShimmer(context)),
            SliverToBoxAdapter(child: _buildListShimmer(context)),
            SliverToBoxAdapter(child: _buildListShimmer(context)),
            SliverToBoxAdapter(child: _buildListShimmer(context)),
          ],
        ),
      ),
      HomeNoProvider() => _buildNoProviderState(
        context,
        l10n,
        isWidescreen: isWidescreen,
      ),
      HomeOffline() => _buildErrorState(context, ref),
      HomeError() => _buildErrorState(context, ref),
      HomeSuccess(:final data, :final news) => _withGradientEdgeHint(
        RefreshIndicator(
          onRefresh: () async {
            await Future.wait<void>([
              ref.read(continueWatchingProvider.notifier).refreshFromServer(),
              ref.read(homeDataProvider.notifier).fetch(),
            ]);
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              if (data.containsKey('Trending'))
                SliverToBoxAdapter(
                  child: HomeHeroCarousel(
                    movies: data['Trending']!,
                    scrollController: _scrollController,
                    onNavigateUp: () => _firstActionFocusNode.requestFocus(),
                    onControllerReady: (c) =>
                        setState(() => _carouselController = c),
                    onTap: (item) {
                      DetailsRoute(
                        $extra: DetailsRouteExtra(item: item),
                      ).push<void>(context);
                    },
                  ),
                )
              else if (data.isNotEmpty)
                SliverToBoxAdapter(
                  child: HomeHeroCarousel(
                    movies: data.values.first,
                    scrollController: _scrollController,
                    onNavigateUp: () => _firstActionFocusNode.requestFocus(),
                    onControllerReady: (c) =>
                        setState(() => _carouselController = c),
                    onTap: (item) {
                      DetailsRoute(
                        $extra: DetailsRouteExtra(item: item),
                      ).push<void>(context);
                    },
                  ),
                )
              else if (!isWidescreen)
                // No carousel — add top padding so content below doesn't
                // overlap with the transparent app bar (mobile only).
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight,
                  ),
                ),

              if (continueWatching.isNotEmpty)
                SliverToBoxAdapter(
                  child: ContinueWatchingSection(
                    title: l10n.continueWatching,
                    items: continueWatching,
                    topPadding: isWidescreen ? 0 : null,
                  ),
                ),

              SliverList(
                delegate: SliverChildListDelegate(
                  _buildProviderSectionsWithNews(
                    context,
                    data,
                    news,
                    activeProvider,
                  ),
                ),
              ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          ),
        ),
      ),
    };
  }

  Widget _withGradientEdgeHint(Widget scrollView) {
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: const _NoScrollbarBehavior(),
          child: scrollView,
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 48, // Taller height for smoother blend
          child: ValueListenableBuilder<bool>(
            valueListenable: _showBottomFade,
            builder: (context, show, _) {
              if (!show) return const SizedBox.shrink();
              final surfaceColor = Theme.of(context).colorScheme.surface;
              return IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        surfaceColor.withValues(alpha: 0.0),
                        surfaceColor.withValues(alpha: 0.15),
                        surfaceColor.withValues(alpha: 0.45),
                        surfaceColor.withValues(alpha: 0.8),
                        surfaceColor,
                      ],
                      stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNoProviderState(
    BuildContext context,
    AppLocalizations l10n, {
    bool isWidescreen = false,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.extension_off_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.selectProviderToStart,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (isWidescreen) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => ref.invalidate(homeDataProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    LayoutConstants.radiusPill,
                  ),
                ),
              ),
            ),
          ] else
            Text(l10n.tapExtensionIcon),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    return RecoverableNetworkState(
      onRetry: () => ref.read(homeDataProvider.notifier).fetch(),
      onOpenDownloads: () => const DownloadsRoute().go(context),
    );
  }

  Widget _buildCarouselShimmer(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.60;
    final isDesktop = context.isDesktop;

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LayoutConstants.dashboardContentPadding,
          vertical: LayoutConstants.spacingSm,
        ),
        child: SizedBox(
          height: heroHeight,
          width: double.infinity,
          child: ShimmerPlaceholder(borderRadius: 18),
        ),
      );
    } else {
      return SizedBox(
        height: heroHeight,
        width: double.infinity,
        child: ShimmerPlaceholder.rectangular(
          width: double.infinity,
          height: heroHeight,
          borderRadius: 0,
        ),
      );
    }
  }

  Widget _buildListShimmer(BuildContext context) {
    final isDesktop = context.isDesktop;
    final isDesktopLandscape = context.isDesktopLandscape;
    final isHandsetLandscape = context.isHandsetLandscape;
    final spacing = isDesktop
        ? LayoutConstants.spacingLg
        : LayoutConstants.spacingSm;
    final cardWidth = isDesktopLandscape
        ? ResponsiveBreakpoints.desktopLandscapeAnimeCardWidth(
            context,
            horizontalPadding: LayoutConstants.dashboardContentPadding,
            spacing: spacing,
          )
        : isHandsetLandscape
        ? ResponsiveBreakpoints.handsetLandscapeAnimeCardWidth(
            context,
            horizontalPadding: LayoutConstants.spacingMd,
            spacing: spacing,
          )
        : (isDesktop ? 200.0 : 130.0);
    final imageHeight = cardWidth / (2 / 3);
    final listHeight = imageHeight + 40.0;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Placeholder
          Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop
                  ? LayoutConstants.dashboardContentPadding
                  : LayoutConstants.spacingMd,
              LayoutConstants.spacingLg,
              isDesktop
                  ? LayoutConstants.dashboardContentPadding
                  : LayoutConstants.spacingMd,
              LayoutConstants.spacingSm,
            ),
            child: ShimmerPlaceholder.rectangular(
              width: 150,
              height: 24,
              borderRadius: 4,
            ),
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
          // List Placeholder
          SizedBox(
            height: listHeight,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? LayoutConstants.dashboardContentPadding
                    : LayoutConstants.spacingMd,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: 10,
              separatorBuilder: (_, _) => SizedBox(width: spacing),
              itemBuilder: (context, index) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerPlaceholder.rectangular(
                      width: cardWidth,
                      height: imageHeight,
                      borderRadius: 12,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
