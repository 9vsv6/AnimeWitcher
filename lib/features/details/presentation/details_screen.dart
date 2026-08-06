import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../core/utils/image_fallbacks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import 'package:skystream/shared/widgets/custom_widgets.dart';

import '../../library/presentation/library_provider.dart';
import '../../library/presentation/library_state.dart';

import 'details_controller.dart';
import "widgets/details_layout_widgets.dart";
import "widgets/details_desktop_hero.dart";
import "widgets/premium_details_widgets.dart";
import "widgets/anime_information_section.dart";
import "../../../shared/widgets/expandable_text.dart";
import "../../../shared/widgets/loading_indicator.dart";
import 'package:skystream/l10n/generated/app_localizations.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool autoPlay;

  const DetailsScreen({super.key, required this.item, this.autoPlay = false});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen>
    with SingleTickerProviderStateMixin {
  static const double _tabSwipeDistanceThreshold = 72;
  static const double _tabSwipeVelocityThreshold = 650;
  static const Duration _tabTransitionDuration = Duration(milliseconds: 260);

  bool _didTriggerAutoPlay = false;
  int _selectedDetailsTab = 0;
  double _tabSwipeDistance = 0;
  bool _tabSwipeStartedAtBackEdge = false;
  Offset _tabSlideFrom = Offset.zero;
  late final AnimationController _tabTransitionController;
  late final Animation<double> _tabTransitionAnimation;

  void _switchDetailsTab(int targetTab) {
    if (targetTab == _selectedDetailsTab) return;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final entersFromLeft = isRtl ? targetTab == 1 : targetTab == 0;
    _tabSlideFrom = Offset(entersFromLeft ? -0.16 : 0.16, 0);

    setState(() => _selectedDetailsTab = targetTab);
    _tabTransitionController.forward(from: 0);
  }

  Widget _buildTabTransition({required Widget child}) {
    return FadeTransition(
      opacity: _tabTransitionAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: _tabSlideFrom,
          end: Offset.zero,
        ).animate(_tabTransitionAnimation),
        child: child,
      ),
    );
  }

  Widget _buildDetailsTabSwipeRegion({
    required Widget child,
    required bool enabled,
  }) {
    if (!enabled) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _tabSwipeDistance = 0;
        // Preserve the native iOS back gesture from the physical left edge.
        _tabSwipeStartedAtBackEdge = details.globalPosition.dx <= 24;
      },
      onHorizontalDragUpdate: (details) {
        if (_tabSwipeStartedAtBackEdge) return;
        _tabSwipeDistance += details.primaryDelta ?? 0;
      },
      onHorizontalDragCancel: () {
        _tabSwipeDistance = 0;
        _tabSwipeStartedAtBackEdge = false;
      },
      onHorizontalDragEnd: (details) {
        final distance = _tabSwipeDistance;
        final velocity = details.primaryVelocity ?? 0;
        final ignored = _tabSwipeStartedAtBackEdge;
        _tabSwipeDistance = 0;
        _tabSwipeStartedAtBackEdge = false;
        if (ignored) return;

        final swipeLeft =
            distance <= -_tabSwipeDistanceThreshold ||
            velocity <= -_tabSwipeVelocityThreshold;
        final swipeRight =
            distance >= _tabSwipeDistanceThreshold ||
            velocity >= _tabSwipeVelocityThreshold;

        final isRtl = Directionality.of(context) == TextDirection.rtl;
        // Arabic: details -> episodes by swiping right, and episodes ->
        // details by swiping left. English uses the opposite directions.
        final swipeTowardEpisodes = isRtl ? swipeRight : swipeLeft;
        final swipeTowardDetails = isRtl ? swipeLeft : swipeRight;

        if (swipeTowardEpisodes && _selectedDetailsTab != 1) {
          _switchDetailsTab(1);
        } else if (swipeTowardDetails && _selectedDetailsTab != 0) {
          _switchDetailsTab(0);
        }
      },
      child: child,
    );
  }

  Future<void> _copyAnimeTitle(BuildContext context, String title) async {
    await Clipboard.setData(ClipboardData(text: title));
    await HapticFeedback.selectionClick();

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Title copied'),
        duration: Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: _tabTransitionDuration,
      value: 1,
    );
    _tabTransitionAnimation = CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(detailsControllerProvider(widget.item.url).notifier)
          .loadDetails(widget.item, autoPlay: widget.autoPlay);
    });
  }

  @override
  void dispose() {
    _tabTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(detailsControllerProvider(widget.item.url), (prev, next) {
      if (!widget.autoPlay || _didTriggerAutoPlay) return;
      final prevState = prev ?? const DetailsState();
      final nextState = next;
      final wasReady =
          prevState.episodes.hasValue &&
          (prevState.episodes.value?.isNotEmpty ?? false);
      final isReady =
          nextState.episodes.hasValue &&
          (nextState.episodes.value?.isNotEmpty ?? false);

      if (wasReady || !isReady) {
        return;
      }

      final item = nextState.item ?? nextState.details.value ?? widget.item;
      _didTriggerAutoPlay = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(detailsControllerProvider(widget.item.url).notifier)
            .handlePlayPress(context, item);
      });
    });
    final isBookmarked = ref.watch(
      libraryProvider.select(
        (state) =>
            state is LibrarySuccess &&
            state.items.any((i) => i.url == widget.item.url),
      ),
    );
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isLarge = context.isTabletOrLarger;

    final detailsAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.details),
    );
    final details = detailsAsync.value;
    final episodesAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.episodes),
    );
    final castAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.cast),
    );
    final trailersAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.trailers),
    );
    final relatedAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.related),
    );
    final recommendationsAsync = ref.watch(
      detailsControllerProvider(
        widget.item.url,
      ).select((s) => s.recommendations),
    );
    final currentItem = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.item),
    );
    final isMovie = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.isMovie),
    );
    final item = currentItem ?? details ?? widget.item;
    final selectedEpisodeCount = ref.watch(
      detailsControllerProvider(
        widget.item.url,
      ).select((state) => state.selectedEpisodeKeys.length),
    );

    final l10n = AppLocalizations.of(context)!;

    // ── Desktop / TV: Immersive hero layout ──
    if (isLarge) {
      return _buildDesktopLayout(
        context,
        item,
        details,
        detailsAsync,
        episodesAsync,
        castAsync,
        trailersAsync,
        relatedAsync,
        recommendationsAsync,
        isMovie,
        isBookmarked,
        libraryNotifier,
        l10n,
        selectedEpisodeCount,
      );
    }

    // ── Mobile: SliverAppBar-based layout (unchanged) ──
    return Scaffold(
      bottomNavigationBar:
          selectedEpisodeCount == 0 || (!isMovie && _selectedDetailsTab != 1)
          ? null
          : _buildEpisodeSelectionBar(context, selectedEpisodeCount),
      body: _buildDetailsTabSwipeRegion(
        enabled: !isMovie,
        child: CustomScrollView(
          slivers: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: SliverAppBar(
              pinned: true,
              expandedHeight: LayoutConstants.detailsExpandedHeightMobile,
              stretch: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'banner_${item.url}',
                    child: CachedNetworkImage(
                      imageUrl:
                          AppImageFallbacks.optional(item.bannerUrl) ??
                          AppImageFallbacks.poster(
                            item.posterUrl,
                            label: item.title,
                          ) ??
                          '',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      // Bound decoded bitmap; plugin backdrops are often at
                      // source resolution. Without this, 4K-source posters
                      // burn ~33 MB per detail page.
                      memCacheWidth:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                        label: item.title,
                        isBackdrop: true,
                      ),
                    ),
                  ),
                  // 1. Legibility Scrim: Fixed dark-tinted overlay at the bottom of the backdrop
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  // 2. Blend-into-page transition: Theme-aware eased fade to surface
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.15),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.45),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Mobile: back/bookmark excluded from D-pad traversal.
            // Users navigate back via hardware Back key on TV remotes.
            leading: Focus(
              descendantsAreTraversable: false,
              child: CustomButton(
                shape: const CircleBorder(),
                backgroundColor: Colors.black45,
                onPressed: () => context.pop(),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            actions: [
              Focus(
                descendantsAreTraversable: false,
                child: IconButton(
                  icon: Icon(
                    isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: isBookmarked
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                  ),
                  onPressed: () {
                    if (isBookmarked) {
                      libraryNotifier.removeItem(item.url);
                    } else {
                      libraryNotifier.addItem(item);
                    }
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
              ),
          ),
          ..._buildMobileSlivers(
            context,
            item,
            details,
            detailsAsync,
            episodesAsync,
            castAsync,
            trailersAsync,
            relatedAsync,
            recommendationsAsync,
            isMovie,
            l10n,
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeSelectionBar(BuildContext context, int selectedCount) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final controller = ref.read(
      detailsControllerProvider(widget.item.url).notifier,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Material(
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.30),
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 112,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  Widget actionButton({
                    required String label,
                    required IconData icon,
                    required VoidCallback onPressed,
                    required bool outlined,
                  }) {
                    final style = outlined
                        ? OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            visualDensity: VisualDensity.compact,
                          )
                        : FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            visualDensity: VisualDensity.compact,
                          );

                    if (outlined) {
                      return OutlinedButton.icon(
                        onPressed: onPressed,
                        icon: Icon(icon, size: 21),
                        label: Text(label),
                        style: style,
                      );
                    }

                    return FilledButton.icon(
                      onPressed: onPressed,
                      icon: Icon(icon, size: 21),
                      label: Text(label),
                      style: style,
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            color: colors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$selectedCount selected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel selection',
                            visualDensity: VisualDensity.compact,
                            onPressed: controller.clearEpisodeSelection,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: actionButton(
                              label: 'Watched',
                              icon: Icons.visibility_rounded,
                              outlined: false,
                              onPressed: () async {
                                await controller.setSelectedEpisodesWatched(
                                  widget.item.url,
                                  true,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: actionButton(
                              label: 'Unwatched',
                              icon: Icons.visibility_off_rounded,
                              outlined: true,
                              onPressed: () async {
                                await controller.setSelectedEpisodesWatched(
                                  widget.item.url,
                                  false,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Select all episodes',
                            onPressed: controller.selectAllEpisodes,
                            icon: const Icon(Icons.select_all_rounded),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              maximumSize: const Size(48, 48),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  DESKTOP / TV  — Immersive hero layout
  // ─────────────────────────────────────────────────────────────────

  String _mediaIdentity(MultimediaItem item) {
    final url = item.url.trim();
    if (url.isNotEmpty) return 'url:$url';

    return [
      item.provider ?? '',
      item.title.trim().toLowerCase(),
      item.year?.toString() ?? '',
      item.contentType.name,
    ].join('|');
  }

  MultimediaItem _inheritProvider(MultimediaItem parent, MultimediaItem child) {
    final childProvider = child.provider?.trim();
    if (childProvider != null && childProvider.isNotEmpty) {
      return child;
    }

    final parentProvider = parent.provider?.trim();
    if (parentProvider == null || parentProvider.isEmpty) {
      return child;
    }

    return child.copyWith(provider: parentProvider);
  }

  List<MultimediaItem> _uniqueMediaItems(List<MultimediaItem>? items) {
    if (items == null || items.isEmpty) {
      return const <MultimediaItem>[];
    }

    final seen = <String>{};
    return items
        .where((item) => seen.add(_mediaIdentity(item)))
        .toList(growable: false);
  }

  List<MultimediaItem> _recommendationsWithoutRelatedLists(
    List<MultimediaItem>? recommendations,
    List<MultimediaItem>? related,
  ) {
    final relatedKeys = _uniqueMediaItems(related).map(_mediaIdentity).toSet();
    return _uniqueMediaItems(recommendations)
        .where((value) => !relatedKeys.contains(_mediaIdentity(value)))
        .toList(growable: false);
  }

  Widget _sectionLoadingPlaceholder(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          const Center(child: AppLoadingIndicator()),
        ],
      ),
    );
  }

  List<Widget> _buildIndependentDetailSections(
    BuildContext context,
    MultimediaItem item,
    AppLocalizations l10n,
    AsyncValue<List<Actor>> castState,
    AsyncValue<List<Trailer>> trailersState,
    AsyncValue<List<MultimediaItem>> relatedState,
    AsyncValue<List<MultimediaItem>> recommendationsState,
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final cast = castState.asData?.value ?? item.cast ?? const <Actor>[];
    final trailers =
        trailersState.asData?.value ?? item.trailers ?? const <Trailer>[];
    final related = _uniqueMediaItems(
      relatedState.asData?.value ?? item.related,
    );
    final recommendations = _recommendationsWithoutRelatedLists(
      recommendationsState.asData?.value ?? item.recommendations,
      related,
    );
    final widgets = <Widget>[];

    if (cast.isNotEmpty) {
      widgets.addAll([const SizedBox(height: 32), CastCarousel(cast: cast)]);
    } else if (castState.isLoading) {
      widgets.add(
        _sectionLoadingPlaceholder(
          context,
          isArabic ? 'طاقم الشخصيات' : 'Cast',
        ),
      );
    }

    if (trailers.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 32),
        TrailersSection(trailers: trailers),
      ]);
    } else if (trailersState.isLoading) {
      widgets.add(
        _sectionLoadingPlaceholder(
          context,
          isArabic ? 'العرض الدعائي' : 'Trailers & Extras',
        ),
      );
    }

    if (related.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 32),
        RecommendationsCarousel(
          title: l10n.relatedAnime,
          items: related,
          showRelationBadge: true,
          onItemTap: (relatedItem) {
            final target = _inheritProvider(item, relatedItem);
            DetailsRoute(
              $extra: DetailsRouteExtra(item: target),
            ).push<void>(context);
          },
        ),
      ]);
    } else if (relatedState.isLoading) {
      widgets.add(
        _sectionLoadingPlaceholder(context, l10n.relatedAnime),
      );
    }

    if (recommendations.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 32),
        RecommendationsCarousel(
          items: recommendations,
          onItemTap: (recommendation) {
            final target = _inheritProvider(item, recommendation);
            DetailsRoute(
              $extra: DetailsRouteExtra(item: target),
            ).push<void>(context);
          },
        ),
      ]);
    } else if (recommendationsState.isLoading) {
      widgets.add(
        _sectionLoadingPlaceholder(
          context,
          isArabic ? 'المزيد مثل هذا' : 'More Like This',
        ),
      );
    }

    return widgets;
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState,
    AsyncValue<List<Episode>> episodesState,
    AsyncValue<List<Actor>> castState,
    AsyncValue<List<Trailer>> trailersState,
    AsyncValue<List<MultimediaItem>> relatedState,
    AsyncValue<List<MultimediaItem>> recommendationsState,
    bool isMovie,
    bool isBookmarked,
    dynamic libraryNotifier,
    AppLocalizations l10n,
    int selectedEpisodeCount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      bottomNavigationBar:
          selectedEpisodeCount == 0 || (!isMovie && _selectedDetailsTab != 1)
          ? null
          : _buildEpisodeSelectionBar(context, selectedEpisodeCount),
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            // Back button — D-pad reachable (Up from Play)
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
              style: IconButton.styleFrom(
                backgroundColor: isDark ? Colors.black45 : Colors.white54,
                foregroundColor: textColor,
              ),
            ),
            actions: [
              // Bookmark — D-pad reachable
              IconButton(
                icon: Icon(
                  isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: isBookmarked
                      ? Theme.of(context).colorScheme.primary
                      : textColor,
                ),
                onPressed: () {
                  if (isBookmarked) {
                    libraryNotifier.removeItem(item.url);
                  } else {
                    libraryNotifier.addItem(item);
                  }
                },
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? Colors.black45 : Colors.white54,
                  foregroundColor: textColor,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: _buildDetailsTabSwipeRegion(
        enabled: !isMovie,
        child: DetailsDesktopHero(
          displayItem: item,
          baseItem: widget.item,
          details: item,
          detailsState: detailsState,
          isMovie: isMovie,
          itemUrl: widget.item.url,
          child: _buildDesktopContentBelow(
            context,
            item,
            details,
            detailsState,
            episodesState,
            castState,
            trailersState,
            relatedState,
            recommendationsState,
            isMovie,
            l10n,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPageTabs(
    BuildContext context,
    AsyncValue<List<Episode>> episodesState,
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final episodeCount = episodesState.asData?.value.length ?? 0;
    final episodeLabel = episodeCount > 0
        ? '${isArabic ? 'الحلقات' : 'Episodes'} ($episodeCount)'
        : isArabic
        ? 'الحلقات'
        : 'Episodes';

    // Episode UI v2: equal-width tabs without selected checkmarks.
    Widget tab({
      required bool selected,
      required Widget leading,
      required String label,
      required VoidCallback onTap,
    }) {
      return ChoiceChip(
        selected: selected,
        showCheckmark: false,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        label: SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              leading,
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        onSelected: (_) => onTap(),
      );
    }

    return Row(
      children: [
        Expanded(
          child: tab(
            selected: _selectedDetailsTab == 0,
            leading: const Icon(Icons.info_outline_rounded, size: 21),
            label: isArabic ? 'التفاصيل' : 'Details',
            onTap: () {
              if (_selectedDetailsTab == 0) return;
              _switchDetailsTab(0);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: tab(
            selected: _selectedDetailsTab == 1,
            leading: episodesState.isLoading
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.video_library_outlined, size: 21),
            label: episodeLabel,
            onTap: () {
              if (_selectedDetailsTab == 1) return;
              _switchDetailsTab(1);
            },
          ),
        ),
      ],
    );
  }

  Widget _episodeLoadStatus(
    BuildContext context,
    AsyncValue<List<Episode>> episodesState,
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

    if (episodesState.isLoading) {
      // Episode UI v2: keep the loading state centered horizontally.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const AppLoadingIndicator(),
              const SizedBox(height: 12),
              Text(
                isArabic
                    ? 'يتم تحميل الحلقات في الخلفية…'
                    : 'Episodes are loading in the background…',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (episodesState.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isArabic ? 'تعذر تحميل الحلقات' : 'Could not load episodes',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                ref
                    .read(detailsControllerProvider(widget.item.url).notifier)
                    .retryEpisodes();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      );
    }

    final episodes = episodesState.asData?.value ?? const <Episode>[];
    if (episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(isArabic ? 'لا توجد حلقات متاحة' : 'No episodes available'),
      );
    }

    return const SizedBox.shrink();
  }

  List<String> _normalizedGenres(MultimediaItem item) {
    final seen = <String>{};
    final genres = <String>[];

    for (final rawTag in item.tags ?? const <String>[]) {
      for (final candidate in rawTag.split(RegExp(r'[,،|/]'))) {
        final genre = candidate.trim();
        if (genre.isEmpty) continue;

        final key = genre.toLowerCase();
        if (seen.add(key)) {
          genres.add(genre);
        }
      }
    }

    return genres;
  }

  Widget _buildSynopsisAndGenres(
    BuildContext context,
    MultimediaItem item,
    AsyncValue<MultimediaItem?> detailsState,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final genres = _normalizedGenres(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.synopsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ExpandableText(
          text: item.description ?? l10n.noDescription,
          maxLines: 4,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.textTheme.bodyMedium?.color,
            height: 1.5,
          ),
        ),
        if (detailsState.hasError) ...[
          const SizedBox(height: 18),
          Text(
            l10n.errorPrefix(detailsState.error.toString()),
            style: TextStyle(color: colors.error),
          ),
        ],
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            isArabic ? 'التصنيفات' : 'Genres',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final genre in genres)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text(
                      genre,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Content rendered below the desktop hero.
  Widget _buildDesktopContentBelow(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState,
    AsyncValue<List<Episode>> episodesState,
    AsyncValue<List<Actor>> castState,
    AsyncValue<List<Trailer>> trailersState,
    AsyncValue<List<MultimediaItem>> relatedState,
    AsyncValue<List<MultimediaItem>> recommendationsState,
    bool isMovie,
    AppLocalizations l10n,
  ) {
    final tabContent = _selectedDetailsTab == 0 || isMovie
        ? <Widget>[
            _buildSynopsisAndGenres(context, item, detailsState, l10n),
            const SizedBox(height: 28),
            AnimeInformationSection(item: item),
            if (isMovie) ...[
              const SizedBox(height: 24),
              _episodeLoadStatus(context, episodesState),
              if (episodesState.hasValue &&
                  (episodesState.value?.isNotEmpty ?? false))
                DetailsDesktopEpisodeColumn(
                  parentItem: item,
                  itemUrl: widget.item.url,
                  isMovie: true,
                ),
            ],
            ..._buildIndependentDetailSections(
              context,
              item,
              l10n,
              castState,
              trailersState,
              relatedState,
              recommendationsState,
            ),
          ]
        : <Widget>[
            _episodeLoadStatus(context, episodesState),
            if (episodesState.hasValue &&
                (episodesState.value?.isNotEmpty ?? false)) ...[
              DetailsSeasonListWrapper(itemUrl: widget.item.url),
              const SizedBox(height: 16),
              DetailsDesktopEpisodeColumn(
                parentItem: item,
                itemUrl: widget.item.url,
                isMovie: false,
              ),
            ],
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMovie) ...[
          _buildDetailsPageTabs(context, episodesState),
          const SizedBox(height: 24),
        ],
        _buildTabTransition(
          child: Column(
            key: ValueKey<int>(isMovie ? 0 : _selectedDetailsTab),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: tabContent,
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  List<Widget> _buildMobileSlivers(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState,
    AsyncValue<List<Episode>> episodesState,
    AsyncValue<List<Actor>> castState,
    AsyncValue<List<Trailer>> trailersState,
    AsyncValue<List<MultimediaItem>> relatedState,
    AsyncValue<List<MultimediaItem>> recommendationsState,
    bool isMovie,
    AppLocalizations l10n,
  ) {
    final showDetailsPage = _selectedDetailsTab == 0 || isMovie;
    final episodeReady =
        episodesState.hasValue && (episodesState.value?.isNotEmpty ?? false);

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'poster_${item.url}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl:
                              AppImageFallbacks.poster(
                                item.posterUrl,
                                label: item.title,
                              ) ??
                              '',
                          width: 100,
                          height: 150,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              ThumbnailErrorPlaceholder(label: item.title),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Directionality(
                        textDirection: Directionality.of(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () =>
                                  _copyAnimeTitle(context, item.title),
                              child: item.logoUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: item.logoUrl!,
                                      height: 50,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft,
                                      errorWidget: (_, _, _) => Text(
                                        item.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    )
                                  : Text(
                                      item.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            MetadataBar(
                              item: item,
                              isLoading: detailsState is AsyncLoading,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              DetailsActionButtons(
                item: widget.item,
                details: item,
                itemUrl: widget.item.url,
              ),
              if (item.nextAiring != null) ...[
                const SizedBox(height: 16),
                NextAiringWidget(nextAiring: item.nextAiring!),
              ],
              const SizedBox(height: 24),
              if (!isMovie) _buildDetailsPageTabs(context, episodesState),
            ],
          ),
        ),
      ),
    ];

    if (showDetailsPage) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildTabTransition(
            child: Padding(
              key: const ValueKey<int>(0),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSynopsisAndGenres(context, item, detailsState, l10n),
                  const SizedBox(height: 28),
                  AnimeInformationSection(item: item),
                  if (isMovie) ...[
                    const SizedBox(height: 20),
                    _episodeLoadStatus(context, episodesState),
                  ],
                  ..._buildIndependentDetailSections(
                    context,
                    item,
                    l10n,
                    castState,
                    trailersState,
                    relatedState,
                    recommendationsState,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      );

      if (isMovie && episodeReady) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverDetailsEpisodeList(
              parentItem: item,
              itemUrl: widget.item.url,
              isMovie: true,
            ),
          ),
        );
      }
    } else {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildTabTransition(
            child: Padding(
              key: const ValueKey<int>(1),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _episodeLoadStatus(context, episodesState),
                  if (episodeReady)
                    DetailsSeasonListWrapper(itemUrl: widget.item.url),
                  if (episodeReady) const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      );

      if (episodeReady) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverDetailsEpisodeList(
              parentItem: item,
              itemUrl: widget.item.url,
              isMovie: false,
              transition: _tabTransitionAnimation,
              transitionOffset: _tabSlideFrom,
            ),
          ),
        );
      }

      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 50)));
    }

    return slivers;
  }
}
