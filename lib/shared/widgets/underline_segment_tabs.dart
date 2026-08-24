import 'package:flutter/material.dart';

/// One tab for [FilterStyleTabBar], matching search-filter icon+label tabs.
class FilterStyleTab extends StatelessWidget {
  const FilterStyleTab({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.showDot = false,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null || icon != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                leading ?? Icon(icon, size: 20),
                if (showDot)
                  const Positioned(
                    right: -3,
                    top: -3,
                    child: CircleAvatar(
                      radius: 4,
                      backgroundColor: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          if (leading != null || icon != null) const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }
}

/// Exact same chrome as the search-filter [TabBar]: gold label/underline
/// that slides smoothly with [TabController] / [TabBarView].
class FilterStyleTabBar extends StatelessWidget implements PreferredSizeWidget {
  const FilterStyleTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.isScrollable = true,
    this.onTap,
  });

  final TabController controller;
  final List<Widget> tabs;
  final bool isScrollable;
  final ValueChanged<int>? onTap;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TabBar(
      controller: controller,
      isScrollable: isScrollable,
      tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
      indicatorColor: colors.primary,
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      onTap: onTap,
      tabs: tabs,
    );
  }
}

/// Keeps a [TabBar] indicator sliding in sync with a lazy [PageView.builder],
/// matching filter-dialog motion without mounting every page eagerly.
mixin FilterStyleTabPageSync<T extends StatefulWidget> on State<T> {
  TabController get filterTabController;
  PageController get filterPageController;

  bool _syncingFromTab = false;
  bool _syncingFromPage = false;

  void attachFilterStyleTabPageSync() {
    filterTabController.addListener(_handleFilterTabTick);
    filterPageController.addListener(_handleFilterPageTick);
  }

  void detachFilterStyleTabPageSync() {
    filterTabController.removeListener(_handleFilterTabTick);
    filterPageController.removeListener(_handleFilterPageTick);
  }

  void _handleFilterTabTick() {
    if (_syncingFromPage || !filterTabController.indexIsChanging) return;
    final target = filterTabController.index;
    if (!filterPageController.hasClients) return;
    final current = filterPageController.page?.round() ??
        filterPageController.initialPage;
    if (current == target) return;
    _syncingFromTab = true;
    filterPageController
        .animateToPage(
          target,
          duration: kTabScrollDuration,
          curve: Curves.ease,
        )
        .whenComplete(() {
      _syncingFromTab = false;
    });
  }

  void _handleFilterPageTick() {
    if (_syncingFromTab ||
        !filterPageController.hasClients ||
        filterTabController.indexIsChanging) {
      return;
    }
    final page = filterPageController.page;
    if (page == null) return;
    final offset = (page - filterTabController.index).clamp(-1.0, 1.0);
    if ((filterTabController.offset - offset).abs() > 0.0001) {
      _syncingFromPage = true;
      filterTabController.offset = offset.toDouble();
      _syncingFromPage = false;
    }
  }

  void onFilterPageChanged(int index) {
    if (filterTabController.index == index) return;
    _syncingFromPage = true;
    filterTabController.index = index;
    _syncingFromPage = false;
  }
}
