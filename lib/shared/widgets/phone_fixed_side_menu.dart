import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/taskbar_destination.dart';
import '../../features/characters/presentation/characters_screen.dart';
import '../../features/more/presentation/broadcast_schedule_screen.dart';
import '../../features/more/presentation/coming_soon_screen.dart';
import '../../features/more/presentation/global_statistics_screen.dart';
import '../../features/more/presentation/recent_watched_screen.dart';
import '../../features/more/presentation/seasons_screen.dart';
import '../../features/news/presentation/open_news.dart';
import '../../features/search/presentation/search_domain.dart';
import 'app_side_menu.dart';

/// The phone side menu has a product-defined order. It deliberately does not
/// read the customizable bottom-bar order or hidden items.
List<AppSideMenuEntry> phoneFixedSideMenuEntries(
  BuildContext context,
  WidgetRef ref, {
  required int currentBranchIndex,
  required ValueChanged<TaskbarDestination> onDestination,
}) {
  final arabic =
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
  final currentDomain = ref.watch(searchDomainProvider);

  void open(Widget page) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void openSearch(SearchDomain domain) {
    ref.read(searchDomainProvider.notifier).set(domain);
    onDestination(TaskbarDestination.search);
  }

  bool selectedBranch(TaskbarDestination destination) =>
      currentBranchIndex == destination.branchIndex;

  bool selectedSearch(SearchDomain domain) =>
      selectedBranch(TaskbarDestination.search) && currentDomain == domain;

  return <AppSideMenuEntry>[
    AppSideMenuEntry(
      id: 'home',
      icon: selectedBranch(TaskbarDestination.home)
          ? Icons.home_rounded
          : Icons.home_outlined,
      label: arabic ? 'الرئيسية' : 'Home',
      selected: selectedBranch(TaskbarDestination.home),
      onTap: () => onDestination(TaskbarDestination.home),
    ),
    AppSideMenuEntry(
      id: 'anime-search',
      icon: Icons.movie_rounded,
      label: arabic ? 'الأنمي' : 'Anime',
      selected: selectedSearch(SearchDomain.anime),
      onTap: () => openSearch(SearchDomain.anime),
    ),
    AppSideMenuEntry(
      id: 'manga-search',
      icon: Icons.menu_book_rounded,
      label: arabic ? 'المانجا' : 'Manga',
      selected: selectedSearch(SearchDomain.manga),
      onTap: () => openSearch(SearchDomain.manga),
    ),
    AppSideMenuEntry(
      id: 'animation-search',
      icon: Icons.animation_rounded,
      label: arabic ? 'الانميشن' : 'Animation',
      selected: selectedSearch(SearchDomain.animation),
      onTap: () => openSearch(SearchDomain.animation),
    ),
    AppSideMenuEntry(
      id: 'seasons',
      icon: Icons.calendar_month_rounded,
      label: arabic ? 'المواسم' : 'Seasons',
      onTap: () => open(const SeasonsScreen()),
    ),
    AppSideMenuEntry(
      id: 'global-statistics',
      icon: Icons.query_stats_rounded,
      label: arabic ? 'الإحصائيات العالمية' : 'Global statistics',
      dividerBefore: true,
      onTap: () => open(const GlobalStatisticsScreen()),
    ),
    AppSideMenuEntry(
      id: 'coming-soon',
      icon: Icons.upcoming_rounded,
      label: arabic ? 'القادم قريبًا' : 'Coming soon',
      onTap: () => open(const ComingSoonScreen()),
    ),
    AppSideMenuEntry(
      id: 'library',
      icon: selectedBranch(TaskbarDestination.library)
          ? Icons.video_library_rounded
          : Icons.video_library_outlined,
      label: arabic ? 'المكتبة' : 'Library',
      selected: selectedBranch(TaskbarDestination.library),
      dividerBefore: true,
      onTap: () => onDestination(TaskbarDestination.library),
    ),
    AppSideMenuEntry(
      id: 'favorite-characters',
      icon: Icons.face_rounded,
      label: arabic ? 'الشخصيات المفضلة' : 'Favorite characters',
      onTap: () => open(const CharactersScreen(favoritesOnly: true)),
    ),
    AppSideMenuEntry(
      id: 'recent-watched',
      icon: Icons.history_rounded,
      label: arabic ? 'آخر المشاهدات' : 'Recently watched',
      onTap: () => open(const RecentWatchedScreen()),
    ),
    AppSideMenuEntry(
      id: 'characters-search',
      icon: Icons.groups_rounded,
      label: arabic ? 'الشخصيات' : 'Characters',
      selected: selectedSearch(SearchDomain.characters),
      dividerBefore: true,
      onTap: () => openSearch(SearchDomain.characters),
    ),
    AppSideMenuEntry(
      id: 'broadcast-schedule',
      icon: Icons.calendar_view_week_rounded,
      label: arabic ? 'جدول الحلقات' : 'Episode schedule',
      onTap: () => open(const BroadcastScheduleScreen()),
    ),
    AppSideMenuEntry(
      id: 'news',
      icon: Icons.newspaper_rounded,
      label: arabic ? 'الأخبار' : 'News',
      onTap: () => openNewsScreen(context, ref),
    ),
  ];
}
