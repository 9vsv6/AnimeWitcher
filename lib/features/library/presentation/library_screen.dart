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
      LibraryCategory.onHold => isArabic ? 'مؤجل' : 'On Hold',
      LibraryCategory.notInterested =>
        isArabic ? 'لا أرغب بمشاهدته' : 'Not Interested',
    };
  }

  Widget _categorySelector(
    BuildContext context,
    WidgetRef ref,
    LibraryCategory selected,
  ) {
    final textStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return PopupMenuButton<LibraryCategory>(
      tooltip: Localizations.localeOf(context).languageCode == 'ar'
          ? 'اختر قائمة'
          : 'Choose list',
      initialValue: selected,
      onSelected: (category) {
        ref.read(libraryProvider.notifier).selectCategory(category);
      },
      itemBuilder: (context) => LibraryCategory.values
          .map(
            (category) => PopupMenuItem<LibraryCategory>(
              value: category,
              child: Row(
                children: [
                  Expanded(child: Text(_categoryLabel(context, category))),
                  if (category == selected)
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_categoryLabel(context, selected), style: textStyle),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
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
