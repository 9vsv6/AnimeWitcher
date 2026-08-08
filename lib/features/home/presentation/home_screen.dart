import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_provider.dart';
import 'home_state.dart';
import 'package:skystream/features/home/presentation/widgets/continue_watching_section.dart';
import 'package:skystream/features/search/presentation/search_provider.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import '../../settings/presentation/general_settings_provider.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/media_horizontal_list.dart';
import 'view_all_screen.dart';
import '../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../shared/widgets/loading_indicator.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/extensions/base_provider.dart';
import 'package:skystream/core/router/app_router.dart';
import '../../../shared/widgets/cards_wrapper.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/providers/device_info_provider.dart';
import 'widgets/dashboard_header_bar.dart';
import 'widgets/provider_search_filter_dialog.dart';
import 'widgets/news_section.dart';
import 'package:skystream/features/news/presentation/news_list_screen.dart';
import 'package:skystream/features/news/presentation/news_utils.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';

import 'package:skystream/core/utils/localized_text.dart';
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Hides the platform scrollbar — replaced by a gradient edge hint.
class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

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
  final ValueNotifier<double> _appBarOpacityNotifier = ValueNotifier<double>(0);
  final ValueNotifier<bool> _showBottomFade = ValueNotifier(false);
  final FocusNode _firstActionFocusNode = FocusNode();
  bool _isLoadingProviderSearchFilters = false;
  final Map<String, ProviderSearchFilterOptions> _searchFilterOptionsCache = {};

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

    final opacity = (_scrollController.offset * 0.8 / 300).clamp(0.0, 1.0);
    if (opacity != _appBarOpacityNotifier.value) {
      _appBarOpacityNotifier.value = opacity;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _appBarOpacityNotifier.dispose();
    _showBottomFade.dispose();
    _firstActionFocusNode.dispose();
    super.dispose();
  }

  void _openNewsArticle(NewsItem item) {
    openNewsUrl(item);
  }

  Future<void> _openLinkedNewsAnime(
    BuildContext context,
    SkyStreamProvider provider,
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
    SkyStreamProvider provider,
    List<NewsItem> items,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
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

  void _openSearchPage({
    bool focusKeyboard = false,
    bool clearQuery = false,
  }) {
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

  Future<void> _showProviderSearchFilters(WidgetRef ref) async {
    final provider = ref.read(activeProviderProvider);
    if (provider == null || _isLoadingProviderSearchFilters) return;

    setState(() => _isLoadingProviderSearchFilters = true);
    ProviderSearchFilters? selected;
    try {
      final options =
          _searchFilterOptionsCache[provider.packageName] ??
          await provider.getSearchFilterOptions();
      _searchFilterOptionsCache[provider.packageName] = options;

      if (!mounted) return;
      if (options.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode == 'ar'
                    ? 'هذه الإضافة لا توفر فلاتر بحث'
                    : 'This provider does not expose search filters',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      selected = await showDialog<ProviderSearchFilters>(
        context: context,
        builder: (dialogContext) => ProviderSearchFilterDialog(
          options: options,
          initialValue: ref.read(searchProviderFiltersProvider),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingProviderSearchFilters = false);
      }
    }

    if (!mounted || selected == null) return;
    ref.read(searchProviderFiltersProvider.notifier).set(selected);
    ref.read(searchFilterProvider.notifier).set(SearchFilter.content);
    _openSearchPage(clearQuery: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final homeDataAsync = ref.watch(homeDataProvider);
    final history = ref.watch(watchHistoryProvider);
    final generalSettings = ref.watch(generalSettingsProvider);
    final l10n = AppLocalizations.of(context)!;
    final activeProvider = ref.watch(activeProviderProvider);
    final activeSearchFilters = ref.watch(searchProviderFiltersProvider);

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
                onShowSearchFilters: () => _showProviderSearchFilters(ref),
                searchFilters: activeSearchFilters,
                isFilterLoading: _isLoadingProviderSearchFilters,
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
                history,
                generalSettings.watchHistoryEnabled,
                isWidescreen: true,
              ),
            ),
          ],
        ),
      );
    }

    // Mobile layout: existing AppBar + FAB
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
        systemOverlayStyle: overlayStyle,
        forceMaterialTransparency: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ValueListenableBuilder<double>(
          valueListenable: _appBarOpacityNotifier,
          // Apply the fade via the color's alpha channel rather than an
          // Opacity widget. Opacity forces a saveLayer() every frame for as
          // long as the AppBar is in the tree (even at opacity 1.0), which
          // shows up on the perf overlay as a constant raster cost. Alpha
          // blending on a Container fill costs ~0.
          builder: (context, opacity, _) => Container(
            color: Theme.of(
              context,
            ).scaffoldBackgroundColor.withValues(alpha: opacity),
          ),
        ),
        title: Text(l10n.appTitle),
        actions: [
          // Search filters use the active provider's own supported values.
          Padding(
            padding: const EdgeInsets.only(right: LayoutConstants.spacingSm),
            child: CardsWrapper(
              onTap: () => _showProviderSearchFilters(ref),
              borderRadius: BorderRadius.circular(50),
              child: CircleAvatar(
                backgroundColor: activeSearchFilters.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.1),
                radius: 18,
                child: _isLoadingProviderSearchFilters
                    ? SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: activeSearchFilters.isNotEmpty
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.tune_rounded,
                        color: activeSearchFilters.isNotEmpty
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface,
                        size: 18,
                      ),
              ),
            ),
          ),

          // 1. Search Action Button
          Padding(
            padding: const EdgeInsets.only(right: LayoutConstants.spacingSm),
            child: CardsWrapper(
              focusNode: _firstActionFocusNode,
              onTap: () => _openSearchPage(focusKeyboard: true),
              borderRadius: BorderRadius.circular(50),
              child: CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
                radius: 18,
                child: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 18,
                ),
              ),
            ),
          ),

        ],
      ),
        ),
      ),
      body: _buildBody(
        context,
        homeDataAsync,
        history,
        generalSettings.watchHistoryEnabled,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    HomeState state,
    List<dynamic> history,
    bool watchHistoryEnabled,
    {
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
      HomeOffline() => _buildErrorState(context, l10n.noInternetError, ref),
      HomeError(:final message) => _buildErrorState(context, message, ref),
      HomeSuccess(:final data, :final news) => _withGradientEdgeHint(
        RefreshIndicator(
          onRefresh: () async => ref.read(homeDataProvider.notifier).fetch(),
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

              if (watchHistoryEnabled && history.isNotEmpty)
                SliverToBoxAdapter(
                  child: ContinueWatchingSection(
                    title: l10n.continueWatching,
                    items: history.cast<HistoryItem>(),
                    topPadding: isWidescreen ? 0 : null,
                  ),
                ),

              if (news.isNotEmpty)
                SliverToBoxAdapter(
                  child: NewsSection(
                    title: Localizations.localeOf(context).languageCode == 'ar'
                        ? 'الأخبار'
                        : 'News',
                    items: news,
                    onViewAll: () =>
                        _openNewsList(context, activeProvider, news),
                    onOpen: _openNewsArticle,
                    onAnimeTap: (item) {
                      _openLinkedNewsAnime(context, activeProvider, item);
                    },
                  ),
                ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final filteredEntries = data.entries
                        .where((e) => e.key != 'Trending')
                        .toList();
                    if (index >= filteredEntries.length) return null;
                    final entry = filteredEntries[index];
                    return MediaHorizontalList(
                      title: entry.key,
                      mediaList: entry.value,
                      category: ViewAllCategory.providerContent,
                      showViewAll: true,
                      fixedPhysicalDirection: true,
                      loadViewAllPage: (offset) =>
                          activeProvider.getHomeSectionPage(
                            entry.key,
                            offset: offset,
                            limit: activeProvider.viewAllPageSize,
                          ),
                      onTap: (item) {
                        DetailsRoute(
                          $extra: DetailsRouteExtra(item: item),
                        ).push<void>(context);
                      },
                      heroTagPrefix: 'home',
                    );
                  },
                  childCount: data.entries
                      .where((e) => e.key != 'Trending')
                      .length,
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

  Widget _buildErrorState(BuildContext context, String error, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bool isOffline = error == l10n.noInternetError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              isOffline ? l10n.noInternetConnection : l10n.siteNotReachable,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isOffline
                  ? l10n.checkConnectionOrDownloads
                  : l10n.tryVpnOrConnection,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!isOffline) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  l10n.errorDetails(error),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => ref.invalidate(homeDataProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.retry),
                ),
                ElevatedButton.icon(
                  onPressed: () => const LibraryRoute().push<void>(context),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: Text(l10n.goToDownloads),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildCarouselShimmer(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.60;
    final isDesktop =
        size.width > LayoutConstants.exploreCarouselDesktopBreakpoint;

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
    final cardWidth = isDesktop ? 200.0 : 130.0;
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
            separatorBuilder: (_, _) => SizedBox(
              width: isDesktop
                  ? LayoutConstants.spacingLg
                  : LayoutConstants.spacingSm,
            ),
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
