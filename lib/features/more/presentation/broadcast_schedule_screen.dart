import 'dart:async';

import 'package:flutter/material.dart';
import 'package:animewitcher/shared/widgets/apple_liquid_glass.dart';
import 'package:animewitcher/shared/widgets/underline_segment_tabs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/providers/animewitcher_native_provider.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/anime_catalog_shimmer.dart';
import '../../../shared/widgets/multimedia_card.dart';
import '../../details/presentation/details_screen.dart';

class BroadcastScheduleScreen extends ConsumerStatefulWidget {
  const BroadcastScheduleScreen({super.key});

  @override
  ConsumerState<BroadcastScheduleScreen> createState() =>
      _BroadcastScheduleScreenState();
}

class _BroadcastScheduleScreenState
    extends ConsumerState<BroadcastScheduleScreen>
    with SingleTickerProviderStateMixin {
  late Future<Map<String, List<MultimediaItem>>> _scheduleFuture;
  late final TabController _tabController;
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _todayIndex();
    _tabController = TabController(
      length: animeWitcherBroadcastDays.length,
      vsync: this,
      initialIndex: _selectedDay,
    )..addListener(_handleTabTick);
    _scheduleFuture = _loadSchedule();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabTick)
      ..dispose();
    super.dispose();
  }

  void _handleTabTick() {
    final value = _tabController.index;
    if (value != _selectedDay) {
      setState(() => _selectedDay = value);
    }
  }

  int _todayIndex() {
    return switch (DateTime.now().weekday) {
      DateTime.saturday => 0,
      DateTime.sunday => 1,
      DateTime.monday => 2,
      DateTime.tuesday => 3,
      DateTime.wednesday => 4,
      DateTime.thursday => 5,
      DateTime.friday => 6,
      _ => 0,
    };
  }

  AnimeWitcherNativeProvider? _provider() {
    final active = ref.read(activeProviderProvider);
    if (active is AnimeWitcherNativeProvider) return active;
    for (final provider in ref.read(extensionManagerProvider)) {
      if (provider is AnimeWitcherNativeProvider) return provider;
    }
    return null;
  }

  Future<Map<String, List<MultimediaItem>>> _loadSchedule() async {
    final provider = _provider();
    if (provider == null) {
      throw StateError('AnimeWitcher Native provider is unavailable');
    }
    return provider.getBroadcastSchedule();
  }

  Future<void> _refreshSchedule() async {
    final future = _loadSchedule();
    setState(() => _scheduleFuture = future);
    await future;
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
                    isArabic ? 'جدول البث' : 'Broadcast schedule',
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
      body: FutureBuilder<Map<String, List<MultimediaItem>>>(
        future: _scheduleFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AnimeCatalogShimmer();
          }
          if (snapshot.hasError || !snapshot.hasData) {
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
                          ? 'تعذر تحميل جدول البث'
                          : 'Could not load the broadcast schedule',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _scheduleFuture = _loadSchedule());
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final schedule = snapshot.data!;
          return Column(
            children: [
              _DayTabs(
                controller: _tabController,
                isArabic: isArabic,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (var index = 0;
                        index < animeWitcherBroadcastDays.length;
                        index++)
                      Builder(
                        builder: (context) {
                          final day = animeWitcherBroadcastDays[index];
                          final items =
                              schedule[day] ?? const <MultimediaItem>[];
                          return RefreshIndicator(
                            onRefresh: _refreshSchedule,
                            child: items.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      120,
                                      24,
                                      110,
                                    ),
                                    children: [
                                      Text(
                                        isArabic
                                            ? 'لا يوجد بث مجدول لهذا اليوم'
                                            : 'No broadcasts scheduled for this day',
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  )
                                : _ScheduleGrid(items: items, day: day),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayTabs extends StatelessWidget {
  final TabController controller;
  final bool isArabic;

  const _DayTabs({
    required this.controller,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    const english = <String>[
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];
    return FilterStyleTabBar(
      controller: controller,
      tabs: [
        for (var i = 0; i < animeWitcherBroadcastDays.length; i++)
          FilterStyleTab(
            label: isArabic ? animeWitcherBroadcastDays[i] : english[i],
          ),
      ],
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  final List<MultimediaItem> items;
  final String day;

  const _ScheduleGrid({required this.items, required this.day});

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    return GridView.builder(
      key: PageStorageKey<String>('broadcast-$day'),
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
          key: ValueKey('broadcast-$day-${item.url}'),
          imageUrl: item.posterImageUrl,
          title: item.title,
          heroTag: 'broadcast-$day-${item.id}-$index',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DetailsScreen(item: item),
            ),
          ),
        );
      },
    );
  }
}
