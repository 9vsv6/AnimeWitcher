import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';

import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/providers/animewitcher_native_provider.dart';

class GlobalStatisticsScreen extends ConsumerStatefulWidget {
  const GlobalStatisticsScreen({super.key});

  @override
  ConsumerState<GlobalStatisticsScreen> createState() =>
      _GlobalStatisticsScreenState();
}

class _GlobalStatisticsScreenState
    extends ConsumerState<GlobalStatisticsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  AnimeWitcherNativeProvider? _provider() {
    final active = ref.read(activeProviderProvider);
    if (active is AnimeWitcherNativeProvider) return active;
    for (final provider in ref.read(extensionManagerProvider)) {
      if (provider is AnimeWitcherNativeProvider) return provider;
    }
    return null;
  }

  Future<Map<String, dynamic>> _load() async {
    final provider = _provider();
    if (provider == null) {
      throw StateError('AnimeWitcher Native provider is unavailable');
    }
    return provider.getGlobalStatistics();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
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
                alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Directionality(
                  textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
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
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatisticsError(isArabic: isArabic, onRetry: _refresh);
          }
          final counters = _flattenCounters(snapshot.data ?? const {});
          if (counters.isEmpty) {
            return Center(
              child: Text(
                isArabic
                    ? 'لا توجد إحصائيات متاحة حاليًا'
                    : 'No statistics are available right now',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _StatisticsGrid(counters: counters, isArabic: isArabic),
          );
        },
      ),
    );
  }

  List<_StatisticEntry> _flattenCounters(Map<String, dynamic> source) {
    final values = <String, num>{};

    void visit(String prefix, dynamic value) {
      if (value is num) {
        values[prefix] = value;
        return;
      }
      if (value is String) {
        final parsed = num.tryParse(value.replaceAll(',', '').trim());
        if (parsed != null) values[prefix] = parsed;
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          visit(prefix.isEmpty ? key : '$prefix.$key', entry.value);
        }
      }
    }

    for (final entry in source.entries) {
      visit(entry.key, entry.value);
    }

    const preferred = <String>[
      'views',
      'episodes_views',
      'movies_views',
      'servers_open_count',
      'users',
      'users_count',
      'anime_count',
      'episodes_count',
      'movies_count',
      'unity_ads_requests',
      'unity_ads_displayed',
      'unity_ads_failed',
    ];
    int rank(String key) {
      final normalized = key.split('.').last.toLowerCase();
      final index = preferred.indexOf(normalized);
      return index < 0 ? preferred.length : index;
    }

    final entries = values.entries
        .where((entry) => entry.key.trim().isNotEmpty)
        .map((entry) => _StatisticEntry(key: entry.key, value: entry.value))
        .toList();
    entries.sort((a, b) {
      final byRank = rank(a.key).compareTo(rank(b.key));
      if (byRank != 0) return byRank;
      return a.key.compareTo(b.key);
    });
    return entries;
  }
}

class _StatisticsGrid extends StatelessWidget {
  const _StatisticsGrid({required this.counters, required this.isArabic});

  final List<_StatisticEntry> counters;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxExtent = width >= 1000 ? 300.0 : width >= 600 ? 260.0 : 210.0;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        childAspectRatio: width >= 600 ? 1.8 : 1.45,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: counters.length,
      itemBuilder: (context, index) {
        final entry = counters[index];
        final normalized = entry.key.split('.').last.toLowerCase();
        final meta = _metadata(normalized, isArabic);
        return _StatisticCard(
          icon: meta.icon,
          label: meta.label,
          value: intl.NumberFormat.decimalPattern().format(entry.value),
        );
      },
    );
  }

  _StatisticMeta _metadata(String key, bool isArabic) {
    switch (key) {
      case 'views':
        return _StatisticMeta(Icons.visibility_rounded, isArabic ? 'المشاهدات' : 'Views');
      case 'episodes_views':
        return _StatisticMeta(Icons.play_circle_rounded, isArabic ? 'مشاهدات الحلقات' : 'Episode views');
      case 'movies_views':
        return _StatisticMeta(Icons.movie_rounded, isArabic ? 'مشاهدات الأفلام' : 'Movie views');
      case 'servers_open_count':
        return _StatisticMeta(Icons.dns_rounded, isArabic ? 'فتح السيرفرات' : 'Server opens');
      case 'users':
      case 'users_count':
        return _StatisticMeta(Icons.people_alt_rounded, isArabic ? 'المستخدمون' : 'Users');
      case 'anime_count':
        return _StatisticMeta(Icons.live_tv_rounded, isArabic ? 'الأنميات' : 'Anime');
      case 'episodes_count':
        return _StatisticMeta(Icons.video_library_rounded, isArabic ? 'الحلقات' : 'Episodes');
      case 'movies_count':
        return _StatisticMeta(Icons.local_movies_rounded, isArabic ? 'الأفلام' : 'Movies');
      case 'unity_ads_requests':
        return _StatisticMeta(Icons.ads_click_rounded, isArabic ? 'طلبات الإعلانات' : 'Ad requests');
      case 'unity_ads_displayed':
        return _StatisticMeta(Icons.ondemand_video_rounded, isArabic ? 'الإعلانات المعروضة' : 'Ads displayed');
      case 'unity_ads_failed':
        return _StatisticMeta(Icons.warning_amber_rounded, isArabic ? 'الإعلانات الفاشلة' : 'Failed ads');
      default:
        final label = key.replaceAll('_', ' ').replaceAll('.', ' · ');
        return _StatisticMeta(Icons.bar_chart_rounded, label);
    }
  }
}

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsError extends StatelessWidget {
  const _StatisticsError({required this.isArabic, required this.onRetry});

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
                  ? 'تعذر تحميل الإحصائيات العالمية'
                  : 'Could not load global statistics',
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

class _StatisticEntry {
  const _StatisticEntry({required this.key, required this.value});
  final String key;
  final num value;
}

class _StatisticMeta {
  const _StatisticMeta(this.icon, this.label);
  final IconData icon;
  final String label;
}
