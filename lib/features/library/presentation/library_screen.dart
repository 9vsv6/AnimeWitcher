import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_info_provider.dart';
import '../../../core/storage/library_category.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
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
      LibraryCategory.planToWatch => Icons.schedule_rounded,
      LibraryCategory.completed => Icons.check_circle_rounded,
      LibraryCategory.notInterested => Icons.block_rounded,
    };
  }

  Widget _categorySelector(
    BuildContext context,
    WidgetRef ref,
    LibraryCategory selected,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

    return PopupMenuButton<LibraryCategory>(
      tooltip: isArabic ? 'اختر قائمة' : 'Choose list',
      initialValue: selected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 14,
      color: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 310),
      onSelected: (category) {
        ref.read(libraryProvider.notifier).selectCategory(category);
      },
      itemBuilder: (context) => LibraryCategory.values
          .map(
            (category) => PopupMenuItem<LibraryCategory>(
              value: category,
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: category == selected
                      ? colors.primaryContainer.withValues(alpha: 0.72)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: category == selected
                            ? colors.primary.withValues(alpha: 0.14)
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _categoryIcon(category),
                        size: 19,
                        color: category == selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _categoryLabel(context, category),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: category == selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (category == selected)
                      Icon(Icons.check_rounded, size: 21, color: colors.primary),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_categoryIcon(selected), size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Text(_categoryLabel(context, selected), style: textStyle),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 21,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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
