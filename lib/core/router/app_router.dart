import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/features/home/presentation/home_screen.dart';
import 'package:skystream/features/search/presentation/search_screen.dart';
import 'package:skystream/features/library/presentation/library_screen.dart';
import 'package:skystream/features/library/presentation/downloads_screen.dart';
import 'package:skystream/features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/developer_options_screen.dart';
import '../../features/details/presentation/details_screen.dart';
import '../../features/explore/presentation/view_all_screen.dart';
import '../../features/player/presentation/player_screen.dart';
import '../domain/entity/multimedia_item.dart';
import '../navigation/taskbar_destination.dart';
import '../extensions/base_provider.dart';
import 'package:skystream/shared/widgets/app_scaffold.dart';
import '../../core/storage/settings_repository.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:flutter/foundation.dart';
import '../logger/app_logger.dart';

part 'app_router.g.dart';

// --- Route Data Classes ---

@TypedStatefulShellRoute<AppShellRouteData>(
  branches: [
    TypedStatefulShellBranch<HomeBranchData>(
      routes: [TypedGoRoute<HomeRoute>(path: '/home')],
    ),
    TypedStatefulShellBranch<SearchBranchData>(
      routes: [TypedGoRoute<SearchRoute>(path: '/search')],
    ),
    TypedStatefulShellBranch<LibraryBranchData>(
      routes: [TypedGoRoute<LibraryRoute>(path: '/library')],
    ),
    TypedStatefulShellBranch<DownloadsBranchData>(
      routes: [TypedGoRoute<DownloadsRoute>(path: '/downloads')],
    ),
    TypedStatefulShellBranch<SettingsBranchData>(
      routes: [
        TypedGoRoute<SettingsRoute>(
          path: '/settings',
          routes: [
            TypedGoRoute<DeveloperOptionsRoute>(path: 'developer'),
          ],
        ),
      ],
    ),
  ],
)
class AppShellRouteData extends StatefulShellRouteData {
  const AppShellRouteData();

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) {
    return AppScaffold(navigationShell: navigationShell);
  }
}

class HomeBranchData extends StatefulShellBranchData {
  const HomeBranchData();
}

class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const HomeScreen();
}

class SearchBranchData extends StatefulShellBranchData {
  const SearchBranchData();
}

class SearchRoute extends GoRouteData with $SearchRoute {
  const SearchRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SearchScreen();
}


class LibraryBranchData extends StatefulShellBranchData {
  const LibraryBranchData();
}

class LibraryRoute extends GoRouteData with $LibraryRoute {
  const LibraryRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LibraryScreen();
}

class DownloadsBranchData extends StatefulShellBranchData {
  const DownloadsBranchData();
}

class DownloadsRoute extends GoRouteData with $DownloadsRoute {
  const DownloadsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DownloadsScreen();
}

class SettingsBranchData extends StatefulShellBranchData {
  const SettingsBranchData();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SettingsScreen();
}

// --- Sub-routes of Settings ---


class DeveloperOptionsRoute extends GoRouteData with $DeveloperOptionsRoute {
  const DeveloperOptionsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DeveloperOptionsScreen();
}

@TypedGoRoute<AppLogsRoute>(path: '/logs')
class AppLogsRoute extends GoRouteData with $AppLogsRoute {
  const AppLogsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return TalkerScreen(
      talker: talker,
      theme: TalkerScreenTheme(
        backgroundColor: Theme.of(context).colorScheme.surface,
        textColor: Theme.of(context).colorScheme.onSurface,
        cardColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

// --- Typed Extras ---

class DetailsRouteExtra {
  const DetailsRouteExtra({required this.item, this.autoPlay = false});
  final MultimediaItem item;
  final bool autoPlay;
}

class PlayerRouteExtra {
  const PlayerRouteExtra({
    required this.item,
    required this.videoUrl,
    this.episode,
  });
  final MultimediaItem item;
  final String videoUrl;
  final Episode? episode;
}

class ViewAllRouteExtra {
  const ViewAllRouteExtra({
    required this.title,
    required this.initialMediaList,
    required this.category,
    this.onTap,
    this.loadPage,
  });
  final String title;
  final List<MultimediaItem> initialMediaList;
  final ViewAllCategory category;
  final void Function(MultimediaItem item)? onTap;
  final Future<ProviderMediaPage> Function(int offset)? loadPage;
}

// --- Full Screen Routes ---

@TypedGoRoute<DetailsRoute>(path: '/details')
class DetailsRoute extends GoRouteData with $DetailsRoute {
  const DetailsRoute({required this.$extra});
  final DetailsRouteExtra $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return DetailsScreen(item: $extra.item, autoPlay: $extra.autoPlay);
  }
}


@TypedGoRoute<ViewAllRoute>(path: '/view-all')
class ViewAllRoute extends GoRouteData with $ViewAllRoute {
  const ViewAllRoute({required this.$extra});
  final ViewAllRouteExtra $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ViewAllScreen(
      title: $extra.title,
      initialMediaList: $extra.initialMediaList,
      category: $extra.category,
      onTap: $extra.onTap,
      loadPage: $extra.loadPage,
    );
  }
}

@TypedGoRoute<PlayerRoute>(path: '/player')
class PlayerRoute extends GoRouteData with $PlayerRoute {
  const PlayerRoute({required this.$extra});
  final PlayerRouteExtra $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return PlayerScreen(
      item: $extra.item,
      videoUrl: $extra.videoUrl,
      episode: $extra.episode,
    );
  }
}

// --- GoRouter Definition ---

final rootNavigatorKey = GlobalKey<NavigatorState>();

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final repository = ref.read(settingsRepositoryProvider);
  final initial = resolveInitialTaskbarRoute(
    repository.getDefaultHomeScreen(),
    repository.getTaskbarOrder(),
    repository.getHiddenTaskbarItems(),
  );

  return GoRouter(
    initialLocation: initial,
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: kDebugMode,
    routes: $appRoutes,
  );
}

// End of Routes
