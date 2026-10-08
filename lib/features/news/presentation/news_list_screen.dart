import 'package:flutter/material.dart';
import 'package:animewitcher/shared/widgets/mouse_drag_refresh_indicator.dart';
import 'package:animewitcher/shared/widgets/app_page_header.dart';

import '../../../core/extensions/base_provider.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../home/presentation/widgets/news_card.dart';
import 'news_utils.dart';

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({
    super.key,
    required this.initialItems,
    required this.loadPage,
    this.onOpen,
    this.onAnimeTap,
  });

  final List<NewsItem> initialItems;
  final Future<ProviderNewsPage> Function(int offset, int limit) loadPage;
  final void Function(NewsItem item)? onOpen;
  final void Function(NewsItem item)? onAnimeTap;

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  late final ScrollController _scrollController;
  late List<NewsItem> _items;
  bool _hasMore = true;
  bool _isLoading = false;
  int _nextOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _items = List<NewsItem>.from(widget.initialItems);
    if (_items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 500) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final page = await widget.loadPage(_nextOffset, 20);
      if (!mounted) return;
      final merged = <String, NewsItem>{
        for (final item in _items) item.id: item,
        for (final item in page.items) item.id: item,
      };
      setState(() {
        _items = merged.values.toList(growable: false);
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.loadPage(0, 20);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // Keep the already visible articles when refresh is unavailable.
    }
  }

  VoidCallback _openOf(NewsItem item) => widget.onOpen == null
      ? () => openNewsUrl(item)
      : () => widget.onOpen!(item);

  VoidCallback? _animeTapOf(NewsItem item) =>
      widget.onAnimeTap == null ? null : () => widget.onAnimeTap!(item);

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final headerTop = appPageHeaderContentTopInset(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppPageAppBar(
        title: isArabic ? 'الأخبار' : 'News',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: MouseDragRefreshIndicator(
        onRefresh: _refresh,
        child: _isPhone(context)
            ? _phoneList(context, headerTop)
            : LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final width = constraints.maxWidth - 2 * gap;
                  final layout = NewsMagazineLayout.forWidth(width);
                  final leadCount = layout.leadCount(_items.length);
                  final rest = _items.skip(leadCount).toList(growable: false);
                  final tileWidth =
                      (width - (layout.columns - 1) * gap) / layout.columns;
                  return CustomScrollView(
                    key: const ValueKey<String>('news-magazine'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          gap,
                          headerTop + gap,
                          gap,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _lead(layout, width, leadCount, gap),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          gap,
                          leadCount > 0 ? gap : 0,
                          gap,
                          28,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: layout.columns,
                                mainAxisSpacing: gap,
                                crossAxisSpacing: gap,
                                // The 16:9 picture plus three lines of title and a time.
                                mainAxisExtent: tileWidth * 9 / 16 + 96,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => NewsGridTile(
                              key: ValueKey<String>(
                                'news-tile-${rest[index].id}',
                              ),
                              item: rest[index],
                              onOpen: _openOf(rest[index]),
                              onAnimeTap: _animeTapOf(rest[index]),
                            ),
                            childCount: rest.length,
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 28),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// A phone keeps the plain list it always had: one story per row held
  /// upright, two side by side turned on its side. The magazine is for the
  /// width of a tablet or a computer window.
  static bool _isPhone(BuildContext context) {
    final platform = Theme.of(context).platform;
    final desktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    return !desktop && MediaQuery.sizeOf(context).shortestSide < 600;
  }

  Widget _phoneList(BuildContext context, double headerTop) {
    final size = MediaQuery.sizeOf(context);
    final columns = newsListColumnCount(size);
    final landscapeExtent = newsListLandscapeMainAxisExtent(
      size: size,
      padding: MediaQuery.paddingOf(context),
    );
    return columns == 1
        ? ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(12, headerTop + 12, 12, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _items.length + (_isLoading ? 1 : 0),
            separatorBuilder: (_, index) {
              if (index >= _items.length - 1) return const SizedBox.shrink();
              return const SizedBox(height: 12);
            },
            itemBuilder: (context, index) =>
                _newsItem(context, index, expandToFill: false),
          )
        : GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(12, headerTop + 12, 12, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: landscapeExtent,
            ),
            itemCount: _items.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) =>
                _newsItem(context, index, expandToFill: true),
          );
  }

  Widget _newsItem(
    BuildContext context,
    int index, {
    required bool expandToFill,
  }) {
    if (index >= _items.length) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final item = _items[index];
    final onOpen = widget.onOpen == null
        ? () {
            openNewsUrl(item);
          }
        : () {
            widget.onOpen!(item);
          };
    return NewsCard(
      item: item,
      compact: false,
      expandToFill: expandToFill,
      onOpen: onOpen,
      onAnimeTap: widget.onAnimeTap == null
          ? null
          : () => widget.onAnimeTap!(item),
    );
  }

  /// The newest stories at the top: one large beside two stacked where the
  /// window is wide enough, a single large one on a phone.
  Widget _lead(NewsMagazineLayout layout, double width, int count, double gap) {
    if (count == 0) return const SizedBox.shrink();
    NewsFeatureTile feature(int index, {bool large = false}) => NewsFeatureTile(
      key: ValueKey<String>('news-lead-${_items[index].id}'),
      item: _items[index],
      large: large,
      onOpen: _openOf(_items[index]),
      onAnimeTap: _animeTapOf(_items[index]),
    );
    if (count == 1) {
      return SizedBox(
        height: (width * 0.56).clamp(200.0, 340.0),
        child: feature(0, large: true),
      );
    }
    return SizedBox(
      height: (width * 0.36).clamp(260.0, 440.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: feature(0, large: true)),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: feature(1)),
                SizedBox(height: gap),
                Expanded(child: feature(2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How the magazine page is laid out at a given content width.
class NewsMagazineLayout {
  const NewsMagazineLayout._({required this.columns, required this.wideLead});

  factory NewsMagazineLayout.forWidth(double width) {
    if (width >= 1100) {
      return const NewsMagazineLayout._(columns: 4, wideLead: true);
    }
    if (width >= 760) {
      return const NewsMagazineLayout._(columns: 3, wideLead: true);
    }
    if (width >= 600) {
      return const NewsMagazineLayout._(columns: 2, wideLead: true);
    }
    return const NewsMagazineLayout._(columns: 2, wideLead: false);
  }

  /// Grid columns below the lead stories.
  final int columns;

  /// Whether the lead is one large story beside two stacked ones.
  final bool wideLead;

  /// How many of [available] stories the lead takes.
  int leadCount(int available) {
    if (available == 0) return 0;
    if (wideLead && available >= 3) return 3;
    return 1;
  }
}
