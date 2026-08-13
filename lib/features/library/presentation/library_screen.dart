import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/navigation/taskbar_destination.dart';

import '../../../core/providers/device_info_provider.dart';
import '../../../core/storage/library_category.dart';
import '../../../core/storage/library_repository.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/apple_liquid_glass.dart';
import 'library_provider.dart';
import 'widgets/bookmarks_tab.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  String _categoryLabel(BuildContext context, LibraryCategory category) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    return switch (category) {
      LibraryCategory.favorite => isArabic ? 'المفضلة' : 'Favorites',
      LibraryCategory.watching => isArabic ? 'أشاهده حاليًا' : 'Watching',
      LibraryCategory.continueLater =>
        isArabic ? 'أكملها لاحقًا' : 'Continue Later',
      LibraryCategory.planToWatch =>
        isArabic ? 'أرغب بمشاهدته' : 'Plan to Watch',
      LibraryCategory.completed => isArabic ? 'تمت مشاهدته' : 'Completed',
      LibraryCategory.notInterested =>
        isArabic ? 'لا أرغب بمشاهدته' : 'Not Interested',
    };
  }

  String _categoryLabelWithCount(
    BuildContext context,
    LibraryCategory category,
    Map<LibraryCategory, int> counts,
  ) {
    return '${_categoryLabel(context, category)} (${counts[category] ?? 0})';
  }

  IconData _categoryIcon(LibraryCategory category) {
    return switch (category) {
      LibraryCategory.favorite => Icons.favorite_rounded,
      LibraryCategory.watching => Icons.play_circle_fill_rounded,
      LibraryCategory.continueLater => Icons.pause_circle_filled_rounded,
      LibraryCategory.planToWatch => Icons.schedule_rounded,
      LibraryCategory.completed => Icons.check_circle_rounded,
      LibraryCategory.notInterested => Icons.block_rounded,
    };
  }


  String _categorySystemImage(LibraryCategory category) {
    return switch (category) {
      LibraryCategory.favorite => 'heart.fill',
      LibraryCategory.watching => 'play.circle.fill',
      LibraryCategory.continueLater => 'pause.circle.fill',
      LibraryCategory.planToWatch => 'clock',
      LibraryCategory.completed => 'checkmark.circle.fill',
      LibraryCategory.notInterested => 'xmark.circle.fill',
    };
  }

  Widget _categorySelector(
    BuildContext context,
    WidgetRef ref,
    LibraryCategory selected,
    Map<LibraryCategory, int> counts,
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final label = _categoryLabelWithCount(context, selected, counts);

    return AppleNativeMenuButton(
      accessibilityLabel: isArabic ? 'اختر قائمة' : 'Choose list',
      systemImage: _categorySystemImage(selected),
      fallbackIcon: _categoryIcon(selected),
      title: label,
      width: isArabic ? 240 : 224,
      size: 44,
      tintColor: Theme.of(context).colorScheme.primary,
      selectedValue: selected.storageKey,
      items: <AppleNativeMenuItem>[
        for (final category in LibraryCategory.values)
          AppleNativeMenuItem(
            value: category.storageKey,
            label: _categoryLabelWithCount(context, category, counts),
            systemImage: _categorySystemImage(category),
          ),
      ],
      onSelected: (value) {
        final category = LibraryCategory.values.firstWhere(
          (candidate) => candidate.storageKey == value,
          orElse: () => selected,
        );
        if (category != selected) {
          ref.read(libraryProvider.notifier).selectCategory(category);
        }
      },
    );
  }

  AppleLiquidGlassToolbarButton _persistentCategoryButton(
    BuildContext context,
    WidgetRef ref,
    LibraryCategory selected,
    Map<LibraryCategory, int> counts,
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final primary = Theme.of(context).colorScheme.primary;

    return AppleLiquidGlassToolbarButton(
      icon: _categoryIcon(selected),
      title: _categoryLabelWithCount(context, selected, counts),
      titleOnly: true,
      width: isArabic ? 240 : 224,
      tooltip: isArabic ? 'اختر قائمة' : 'Choose list',
      color: primary,
      menuTintColor: primary,
      onPressed: null,
      selectedMenuValue: selected.storageKey,
      menuItems: <AppleNativeMenuItem>[
        for (final category in LibraryCategory.values)
          AppleNativeMenuItem(
            value: category.storageKey,
            label: _categoryLabelWithCount(context, category, counts),
            systemImage: _categorySystemImage(category),
          ),
      ],
      onMenuSelected: (value) {
        final category = LibraryCategory.values.firstWhere(
          (candidate) => candidate.storageKey == value,
          orElse: () => selected,
        );
        if (category != selected) {
          ref.read(libraryProvider.notifier).selectCategory(category);
        }
      },
    );
  }

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

    if (isWidescreen) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: LayoutConstants.dashboardHeaderHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.dashboardContentPadding,
                ),
                alignment: Alignment.centerLeft,
                child: _categorySelector(context, ref, selectedCategory, categoryCounts),
              ),
            ),
            const Expanded(child: BookmarksTab()),
          ],
        ),
      );
    }

    final usePersistentGlass = appleUsesPersistentLiquidGlassHeader;
    final mobileScaffold = Scaffold(
      appBar: AppBar(
        title: usePersistentGlass
            ? const SizedBox.shrink()
            : _categorySelector(context, ref, selectedCategory, categoryCounts),
        actions: usePersistentGlass
            ? const <Widget>[SizedBox(width: 250)]
            : null,
      ),
      body: const BookmarksTab(),
    );

    if (!usePersistentGlass) return mobileScaffold;
    return ApplePersistentGlassHeaderScope(
      branchIndex: TaskbarDestination.library.branchIndex,
      trailingButtons: <AppleLiquidGlassToolbarButton>[
        _persistentCategoryButton(context, ref, selectedCategory, categoryCounts),
      ],
      child: mobileScaffold,
    );
  }
}
