import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animewitcher/core/navigation/taskbar_destination.dart';

import '../../../core/providers/device_info_provider.dart';
import '../../../core/storage/library_category.dart';
import '../../../core/storage/library_repository.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/window_controls_inset.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/apple_liquid_glass.dart';
import 'library_provider.dart';
import 'widgets/bookmarks_tab.dart';
import 'widgets/library_category_selector.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final libraryState = ref.watch(libraryProvider);
    final selectedCategory = libraryState.category;
    final repository = ref.read(libraryRepositoryProvider);
    final categoryCounts = <LibraryCategory, int>{
      for (final category in LibraryCategory.values)
        category: repository.getLibraryItems(category: category).length,
    };

    final categorySelector = LibraryCategorySelector(
      selected: selectedCategory,
      counts: categoryCounts,
    );

    if (isWidescreen) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: LayoutConstants.dashboardHeaderHeight,
                // The window's caption buttons are painted over this same
                // corner, and the selector sits against the trailing edge in
                // Arabic — straight underneath them without this.
                padding: EdgeInsets.only(
                  left: LayoutConstants.dashboardContentPadding,
                  right:
                      LayoutConstants.dashboardContentPadding +
                      windowControlsTrailingInset,
                ),
                alignment: Alignment.centerRight,
                child: categorySelector,
              ),
            ),
            const Expanded(child: BookmarksTab()),
          ],
        ),
      );
    }

    final usePersistentGlass = appleUsesPersistentLiquidGlassHeader;
    final mobileScaffold = Scaffold(
      appBar: AppBar(title: categorySelector),
      body: const BookmarksTab(),
    );

    if (!usePersistentGlass) return mobileScaffold;
    return ApplePersistentGlassHeaderScope(
      branchIndex: TaskbarDestination.library.branchIndex,
      trailingButtons: const <AppleLiquidGlassToolbarButton>[],
      child: mobileScaffold,
    );
  }
}
