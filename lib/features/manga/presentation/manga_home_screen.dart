import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/entity/manga.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/anime_catalog_shimmer.dart';
import '../../../shared/widgets/catalog_ltr.dart';
import '../../../shared/widgets/multimedia_card.dart';
import '../../home/presentation/widgets/latest_manga_chapters_section.dart';

/// Manga on a tab of its own, for a viewer who turned that tab on: the new
/// chapters along the top, then every manga by how much it is read, loading
/// more as the page is scrolled. While this tab is on, home leaves manga out.
class MangaHomeScreen extends ConsumerStatefulWidget {
  const MangaHomeScreen({super.key});

  @override
  ConsumerState<MangaHomeScreen> createState() => _MangaHomeScreenState();
}

class _MangaHomeScreenState extends ConsumerState<MangaHomeScreen> {
  final ScrollController _scroll = ScrollController();

  List<MangaLatestChapter> _latest = const <MangaLatestChapter>[];
  final List<MultimediaItem> _popular = <MultimediaItem>[];
  int _nextOffset = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;

  bool get _arabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reload()));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AnimeWitcherProvider? _provider() {
    final providers = ref
        .read(extensionManagerProvider.notifier)
        .getAllProviders();
    for (final provider in providers) {
      if (provider.supportedTypes.contains(ProviderType.manga)) return provider;
    }
    return providers.isEmpty ? null : providers.first;
  }

  Future<void> _reload() async {
    setState(() {
      _popular.clear();
      _nextOffset = 0;
      _hasMore = true;
      _failed = false;
    });
    final provider = _provider();
    if (provider == null) return;
    unawaited(
      provider
          .getLatestMangaPage(limit: 30)
          .then((page) {
            if (mounted) setState(() => _latest = page.items);
          })
          .catchError((Object _) {}),
    );
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final provider = _provider();
    if (provider == null) return;
    setState(() => _loading = true);
    try {
      final page = await provider.searchMangaPage(
        '',
        const ProviderSearchFilters(),
        offset: _nextOffset,
        limit: provider.searchPageSize,
      );
      if (!mounted) return;
      final seen = _popular.map((item) => item.url).toSet();
      setState(() {
        _popular.addAll(page.items.where((item) => seen.add(item.url)));
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 800) {
      unawaited(_loadMore());
    }
  }

  void _open(MultimediaItem item) {
    MangaDetailsRoute($extra: MangaDetailsRouteExtra(item: item))
        .push<void>(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MultimediaCardLayout.catalogGridHorizontalPadding(context);
    final mq = MediaQuery.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          key: const PageStorageKey<String>('manga-home'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding + 8,
                  mq.padding.top + 24,
                  padding + 8,
                  8,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.menu_book_rounded,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _arabic ? 'المانجا' : 'Manga',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_latest.isNotEmpty)
              SliverToBoxAdapter(
                child: LatestMangaChaptersSection(
                  title: _arabic ? 'فصول جديدة' : 'New chapters',
                  items: _latest,
                  onTap: (latest) => _open(latest.manga),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding + 8, 24, padding + 8, 4),
                child: Text(
                  _arabic ? 'الأكثر قراءة' : 'Most read',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding,
                12,
                padding,
                24 + mq.padding.bottom,
              ),
              sliver: _failed && _popular.isEmpty
                  ? SliverToBoxAdapter(
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_arabic ? 'إعادة المحاولة' : 'Retry'),
                        ),
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: ResponsiveBreakpoints.animeGridDelegate(
                        context,
                        maxCrossAxisExtent: 200,
                        childAspectRatio:
                            MultimediaCardLayout.portraitGridAspectRatio,
                        crossAxisSpacing:
                            MultimediaCardLayout.catalogGridCrossAxisSpacing(
                              context,
                            ),
                        mainAxisSpacing:
                            MultimediaCardLayout.catalogGridMainAxisSpacing(
                              context,
                            ),
                        handsetPortraitCrossAxisCount:
                            MultimediaCardLayout.handsetPortraitGridColumns,
                        horizontalPadding: padding,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index >= _popular.length) {
                          return const AnimePosterShimmer();
                        }
                        final item = _popular[index];
                        return CatalogLtr(
                          child: MultimediaCard.fromItem(
                            key: ValueKey<String>('manga-home-${item.url}'),
                            item: item,
                            heroTag: 'manga_home_${item.url}_$index',
                            onTap: () => _open(item),
                          ),
                        );
                      }, childCount: _popular.length + (_loading ? 6 : 0)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
