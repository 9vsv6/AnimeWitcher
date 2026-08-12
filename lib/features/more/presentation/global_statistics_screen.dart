import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/providers/animewitcher_native_provider.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/multimedia_card.dart';
import '../../details/presentation/details_screen.dart';

class GlobalStatisticsScreen extends ConsumerStatefulWidget {
  const GlobalStatisticsScreen({super.key});

  @override
  ConsumerState<GlobalStatisticsScreen> createState() =>
      _GlobalStatisticsScreenState();
}

class _GlobalStatisticsScreenState
    extends ConsumerState<GlobalStatisticsScreen> {
  late final PageController _pageController;
  final Map<AnimeWitcherGlobalRanking, Future<List<MultimediaItem>>> _loads =
      <AnimeWitcherGlobalRanking, Future<List<MultimediaItem>>>{};
  int _selectedRanking = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  AnimeWitcherNativeProvider? _provider() {
    final active = ref.read(activeProviderProvider);
    if (active is AnimeWitcherNativeProvider) return active;
    for (final provider in ref.read(extensionManagerProvider)) {
      if (provider is AnimeWitcherNativeProvider) return provider;
    }
    return null;
  }

  Future<List<MultimediaItem>> _load(AnimeWitcherGlobalRanking ranking) {
    final provider = _provider();
    if (provider == null) {
      return Future<List<MultimediaItem>>.error(
        StateError('AnimeWitcher Native provider is unavailable'),
      );
    }
    return provider.getGlobalRanking(ranking);
  }

  Future<List<MultimediaItem>> _futureFor(
    AnimeWitcherGlobalRanking ranking,
  ) {
    return _loads.putIfAbsent(ranking, () => _load(ranking));
  }

  Future<void> _refresh(AnimeWitcherGlobalRanking ranking) async {
    final next = _load(ranking);
    setState(() => _loads[ranking] = next);
    await next;
  }

  void _selectRanking(int value) {
    if (value < 0 ||
        value >= AnimeWitcherGlobalRanking.values.length ||
        value == _selectedRanking) {
      return;
    }
    setState(() => _selectedRanking = value);
    _pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 16,
            title: ApplePersistentGlassHeaderScope(
              enabled: Navigator.of(context).canPop(),
              onBack: () => Navigator.of(context).pop(),
              child: Align(
                alignment:
                    isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Directionality(
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(
                    isArabic ? 'الإحصائيات العالمية' : 'Global statistics',
                  ),
                ),
              ),
            ),
            leading: appleUsesPersistentLiquidGlassHeader
                ? null
                : AppleLiquidGlassBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
            elevation: 0,
          ),
        ),
      ),
      body: Column(
        children: [
          _RankingTabs(
            selectedIndex: _selectedRanking,
            isArabic: isArabic,
            onSelected: _selectRanking,
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: AnimeWitcherGlobalRanking.values.length,
              onPageChanged: (value) {
                if (value != _selectedRanking) {
                  setState(() => _selectedRanking = value);
                }
              },
              itemBuilder: (context, index) {
                final ranking = AnimeWitcherGlobalRanking.values[index];
                return FutureBuilder<List<MultimediaItem>>(
                  future: _futureFor(ranking),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _RankingError(
                        isArabic: isArabic,
                        onRetry: () => _refresh(ranking),
                      );
                    }
                    final items = snapshot.data ?? const <MultimediaItem>[];
                    if (items.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () => _refresh(ranking),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.55,
                              child: Center(
                                child: Text(
                                  isArabic
                                      ? 'لا توجد نتائج في هذا التصنيف حاليًا'
                                      : 'No results in this ranking right now',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return _RankingGrid(
                      items: items,
                      ranking: ranking,
                      onRefresh: () => _refresh(ranking),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingTabs extends StatelessWidget {
  const _RankingTabs({
    required this.selectedIndex,
    required this.isArabic,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool isArabic;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rankings = AnimeWitcherGlobalRanking.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < rankings.length; i++) ...[
            Material(
              color: selectedIndex == i
                  ? colors.primary
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  child: Text(
                    isArabic
                        ? rankings[i].arabicTitle
                        : rankings[i].englishTitle,
                    style: TextStyle(
                      color: selectedIndex == i
                          ? colors.onPrimary
                          : colors.onSurface,
                      fontWeight: selectedIndex == i
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            if (i != rankings.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RankingGrid extends StatelessWidget {
  const _RankingGrid({
    required this.items,
    required this.ranking,
    required this.onRefresh,
  });

  final List<MultimediaItem> items;
  final AnimeWitcherGlobalRanking ranking;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        key: PageStorageKey<String>('global-ranking-${ranking.queryType}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        gridDelegate: ResponsiveBreakpoints.animeGridDelegate(
          context,
          maxCrossAxisExtent: isDesktop ? 240 : 150,
          childAspectRatio: isDesktop ? 0.58 : 0.55,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return MultimediaCard(
            key: ValueKey('${ranking.queryType}-${item.url}'),
            imageUrl: item.posterImageUrl,
            title: item.title,
            heroTag: 'global-ranking-${ranking.queryType}-${item.id}-$index',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailsScreen(item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RankingError extends StatelessWidget {
  const _RankingError({required this.isArabic, required this.onRetry});

  final bool isArabic;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              isArabic
                  ? 'تعذر تحميل هذا التصنيف'
                  : 'Could not load this ranking',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
