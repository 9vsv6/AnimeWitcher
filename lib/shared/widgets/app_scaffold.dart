import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/navigation/taskbar_destination.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';

import '../../features/settings/presentation/general_settings_provider.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  void _onItemTapped(int index, BuildContext context) {
    if (appleUsesPersistentLiquidGlassHeader) {
      applePersistentGlassHeaderController.setActiveBranch(index);
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  int _getRouteIndex(String route) {
    return taskbarDestinationForRoute(route)?.branchIndex ??
        TaskbarDestination.home.branchIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (appleUsesPersistentLiquidGlassHeader) {
      final activeBranch = widget.navigationShell.currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          applePersistentGlassHeaderController.setActiveBranch(activeBranch);
        }
      });
    }

    final generalSettings = ref.watch(generalSettingsProvider);
    final defaultIndex = _getRouteIndex(generalSettings.defaultHomeScreen);
    final taskbarDestinations = visibleTaskbarDestinations(
      generalSettings.taskbarOrder,
      generalSettings.hiddenTaskbarItems,
    );
    final isAtDefaultHome = widget.navigationShell.currentIndex == defaultIndex;

    return PopScope(
      canPop: isAtDefaultHome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          widget.navigationShell.goBranch(defaultIndex);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBody: true,
        body: widget.navigationShell,
        bottomNavigationBar: CustomBottomNavBar.usesNativeAppleTabBar
            ? CustomBottomNavBar(
                currentBranchIndex: widget.navigationShell.currentIndex,
                destinations: taskbarDestinations,
                onTap: (destination) =>
                    _onItemTapped(destination.branchIndex, context),
              )
            : Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: CustomBottomNavBar.bottomInsetFor(context),
                ),
                child: CustomBottomNavBar(
                  currentBranchIndex: widget.navigationShell.currentIndex,
                  destinations: taskbarDestinations,
                  onTap: (destination) =>
                      _onItemTapped(destination.branchIndex, context),
                ),
              ),
      ),
    );
  }
}
