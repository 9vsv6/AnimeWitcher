import 'package:flutter/material.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/multimedia_card.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';
import 'controllers/view_all_controller.dart';

enum ViewAllCategory {
  popularMovies,
  popularTV,
  nowPlayingMovies,
  onTheAirTV,
  topRatedMovies,
  topRatedTV,
  airingTodayTV,
  trending,

  /// Provider-sourced content from the home screen.
  providerContent,
}

class ViewAllScreen extends ConsumerStatefulWidget {
  final String title;
  final List<MultimediaItem> initialMediaList;
  final ViewAllCategory category;
  final void Function(MultimediaItem item)? onTap;

  /// Loads exactly one provider page. The page is requested only when the
  /// user approaches the bottom, so View All never downloads the full catalog.
  final Future<ProviderMediaPage> Function(int offset)? loadPage;

  const ViewAllScreen({
    super.key,
    required this.title,
    required this.initialMediaList,
    required this.category,
    this.onTap,
    this.loadPage,
  });

  @override
  ConsumerState<ViewAllScreen> createState() => _ViewAllScreenState();
}

class _ViewAllScreenState extends ConsumerState<ViewAllScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<MultimediaItem> _providerItems = <MultimediaItem>[];
  final Set<String> _providerSeen = <String>{};

  bool _isPortrait = true;
  bool _providerLoading = false;
  bool _providerHasMore = true;
  int _providerOffset = 0;

  bool get _isProvider => widget.category == ViewAllCategory.providerContent;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    for (final item in widget.initialMediaList) {
      final key = _itemKey(item);
      if (_providerSeen.add(key)) _providerItems.add(item);
    }

    if (widget.initialMediaList.isNotEmpty) {
      _checkAspectRatio();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isProvider) {
        _providerHasMore = widget.loadPage != null;
        if (_providerHasMore) _loadNextProviderPage();
        return;
      }

      final controller = ref.read(
        viewAllControllerProvider(widget.category).notifier,
      );
      controller.init(widget.initialMediaList);
      _checkInitialFill();
    });
  }

  String _itemKey(MultimediaItem item) {
    final url = item.url.trim();
    if (url.isNotEmpty) return url;
    return '${item.id}|${item.title}|${item.posterUrl}';
  }

  Future<void> _loadNextProviderPage() async {
    final loader = widget.loadPage;
    if (!_isProvider ||
        loader == null ||
        _providerLoading ||
        !_providerHasMore) {
      return;
    }

    final requestedOffset = _providerOffset;
    setState(() => _providerLoading = true);

    try {
      final page = await loader(requestedOffset);
      if (!mounted) return;

      for (final item in page.items) {
        if (_providerSeen.add(_itemKey(item))) {
          _providerItems.add(item);
        }
      }

      setState(() {
        final fallbackAdvance = page.items.isNotEmpty ? page.items.length : 1;
        _providerOffset = page.nextOffset > requestedOffset
            ? page.nextOffset
            : requestedOffset + fallbackAdvance;
        _providerHasMore = page.hasMore &&
            (page.nextOffset > requestedOffset || page.items.isNotEmpty);
        _providerLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureProviderFill(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _providerLoading = false;
        _providerHasMore = false;
      });
    }
  }

  void _ensureProviderFill() {
    if (!mounted || !_providerHasMore || _providerLoading) return;
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <
            _scrollController.position.viewportDimension * 0.65) {
      _loadNextProviderPage();
    }
  }

  Future<void> _checkAspectRatio() async {
    if (widget.initialMediaList.isEmpty) return;
    final url = widget.initialMediaList.first.posterImageUrl;
    if (url.isEmpty) return;
    final isPortrait = await ImageUtils.isImagePortrait(url);
    if (mounted && _isPortrait != isPortrait) {
      setState(() => _isPortrait = isPortrait);
    }
  }

  void _checkInitialFill() {
    if (!context.mounted || _isProvider) return;
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent <= 0) {
      final state = ref.read(viewAllControllerProvider(widget.category));
      if (state.hasMore && !state.isLoading) {
        ref
            .read(viewAllControllerProvider(widget.category).notifier)
            .fetchNextPage()
            .then((_) {
              if (context.mounted) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _checkInitialFill(),
                );
              }
            });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 500) {
      return;
    }

    if (_isProvider) {
      _loadNextProviderPage();
    } else {
      ref
          .read(viewAllControllerProvider(widget.category).notifier)
          .fetchNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ViewAllState? controllerState = _isProvider
        ? null
        : ref.watch(viewAllControllerProvider(widget.category));

    if (!_isProvider) {
      ref.listen(viewAllControllerProvider(widget.category), (previous, next) {
        if (next.items.isEmpty && !next.isLoading && next.page == 1) {
          _checkInitialFill();
        }
      });
    }

    final items = _isProvider ? _providerItems : controllerState!.items;
    final isLoading = _isProvider
        ? _providerLoading
        : controllerState!.isLoading;

    final isDesktop = context.isDesktop;
    final maxExtent = isDesktop
        ? (_isPortrait ? 240.0 : 340.0)
        : (_isPortrait ? 150.0 : 220.0);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (screenWidth / maxExtent).ceil().clamp(1, 20);
    final childAspectRatio = _isPortrait ? 0.55 : 1.35;
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            centerTitle: false,
            titleSpacing: 16,
            title: ApplePersistentGlassHeaderScope(
              enabled: Navigator.of(context).canPop(),
              onBack: () => context.pop(),
              child: Align(
                alignment:
                    isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Directionality(
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            leading: appleUsesPersistentLiquidGlassHeader
                ? null
                : AppleLiquidGlassBackButton(onPressed: () => context.pop()),
            elevation: 0,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0, 0.3],
          ),
        ),
        child: GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: items.length + (isLoading ? crossAxisCount : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return ShimmerPlaceholder(borderRadius: 12);
            }

            final item = items[index];
            final imageUrl = item.posterImageUrl;
            final uniqueTag =
                'view_all_${widget.category.name}_${item.id}_$index';

            return MultimediaCard(
              key: ValueKey(_itemKey(item)),
              imageUrl: imageUrl,
              title: item.title,
              episodeBadge: item.episodeBadge,
              heroTag: uniqueTag,
              isPortrait: _isPortrait,
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!(item);
                } else {
                  DetailsRoute(
                    $extra: DetailsRouteExtra(item: item),
                  ).push<void>(context);
                }
              },
            );
          },
        ),
      ),
    );
  }
}
