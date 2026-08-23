import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/library_category.dart';
import '../../../../shared/widgets/apple_liquid_glass.dart';
import '../library_provider.dart';

/// Library category picker — solid icon + label + list icon (no liquid glass).
///
/// On iPhone the visible chrome stays Material; tapping opens the native
/// UIMenu with Liquid Glass via an invisible [AppleNativeMenuButton] anchor.
class LibraryCategorySelector extends ConsumerWidget {
  const LibraryCategorySelector({
    super.key,
    required this.selected,
    required this.counts,
  });

  final LibraryCategory selected;
  final Map<LibraryCategory, int> counts;

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

  List<AppleNativeMenuItem> _menuItems(BuildContext context) {
    return <AppleNativeMenuItem>[
      for (final category in LibraryCategory.values)
        AppleNativeMenuItem(
          value: category.storageKey,
          label: _categoryLabelWithCount(context, category),
          systemImage: _categorySystemImage(category),
          icon: _categoryIcon(category),
        ),
    ];
  }

  void _selectCategory(WidgetRef ref, String value, LibraryCategory current) {
    final category = LibraryCategory.values.firstWhere(
      (candidate) => candidate.storageKey == value,
      orElse: () => current,
    );
    if (category != current) {
      ref.read(libraryProvider.notifier).selectCategory(category);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final primary = Theme.of(context).colorScheme.primary;
    final label = _categoryLabelWithCount(context, selected);
    final width = isArabic ? 240.0 : 224.0;
    final menuItems = _menuItems(context);
    final accessibilityLabel = isArabic ? 'اختر قائمة' : 'Choose list';

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_categoryIcon(selected), color: primary, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.format_list_bulleted_rounded, color: primary, size: 20),
      ],
    );

    if (!appleUsesPersistentLiquidGlassHeader) {
      return _MaterialCategoryMenu(
        selected: selected,
        menuItems: menuItems,
        tintColor: primary,
        accessibilityLabel: accessibilityLabel,
        iconForValue: (value) {
          final category = LibraryCategory.values.firstWhere(
            (candidate) => candidate.storageKey == value,
            orElse: () => selected,
          );
          return _categoryIcon(category);
        },
        onSelected: (value) => _selectCategory(ref, value, selected),
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: accessibilityLabel,
      child: SizedBox(
        width: width,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            content,
            Positioned.fill(
              child: AppleNativeMenuButton(
                invisibleAnchor: true,
                items: menuItems,
                onSelected: (value) => _selectCategory(ref, value, selected),
                accessibilityLabel: accessibilityLabel,
                systemImage: _categorySystemImage(selected),
                fallbackIcon: _categoryIcon(selected),
                selectedValue: selected.storageKey,
                width: width,
                size: 44,
                tintColor: primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialCategoryMenu extends StatelessWidget {
  const _MaterialCategoryMenu({
    required this.selected,
    required this.menuItems,
    required this.tintColor,
    required this.accessibilityLabel,
    required this.iconForValue,
    required this.onSelected,
    required this.child,
  });

  final LibraryCategory selected;
  final List<AppleNativeMenuItem> menuItems;
  final Color tintColor;
  final String accessibilityLabel;
  final IconData Function(String value) iconForValue;
  final ValueChanged<String> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: accessibilityLabel,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in menuItems)
          PopupMenuItem<String>(
            value: item.value,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: selected.storageKey == item.value
                      ? Icon(Icons.check_rounded, size: 20, color: tintColor)
                      : Icon(
                          iconForValue(item.value),
                          size: 18,
                          color: tintColor,
                        ),
                ),
                Expanded(child: Text(item.label)),
              ],
            ),
          ),
      ],
      child: child,
    );
  }
}
