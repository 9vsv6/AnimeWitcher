import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_info_provider.dart';
import '../../../core/storage/library_category.dart';
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
  ) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final label = _categoryLabel(context, selected);

    return AppleNativeMenuButton(
      accessibilityLabel: isArabic ? 'اختر قائمة' : 'Choose list',
      systemImage: _categorySystemImage(selected),
      fallbackIcon: _categoryIcon(selected),
      title: label,
      width: isArabic ? 218 : 210,
      size: 44,
      tintColor: Theme.of(context).colorScheme.primary,
      selectedValue: selected.storageKey,
      items: <AppleNativeMenuItem>[
        for (final category in LibraryCategory.values)
          AppleNativeMenuItem(
            value: category.storageKey,
            label: _categoryLabel(context, category),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final selectedCategory = ref.watch(libraryProvider).category;

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
                child: _categorySelector(context, ref, selectedCategory),
              ),
            ),
            const Expanded(child: BookmarksTab()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _categorySelector(context, ref, selectedCategory),
      ),
      body: const BookmarksTab(),
    );
  }
}
