import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/library_category.dart';
import '../../../../shared/widgets/apple_liquid_glass.dart';
import '../library_provider.dart';

/// Library category picker — solid icon + label + chevron (no liquid glass).
///
/// On iPhone the visible chrome stays Material; tapping opens the native
/// UIMenu with Liquid Glass via an invisible [AppleNativeMenuButton] anchor.
/// While the menu is open, the label/icons animate out and back in on dismiss.
class LibraryCategorySelector extends ConsumerStatefulWidget {
  const LibraryCategorySelector({
    super.key,
    required this.selected,
    required this.counts,
  });

  final LibraryCategory selected;
  final Map<LibraryCategory, int> counts;

  @override
  ConsumerState<LibraryCategorySelector> createState() =>
      _LibraryCategorySelectorState();
}

class _LibraryCategorySelectorState
    extends ConsumerState<LibraryCategorySelector> {
  static const _hideDuration = Duration(milliseconds: 160);
  static const _showDuration = Duration(milliseconds: 200);

  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (!mounted || _menuOpen == open) return;
    setState(() => _menuOpen = open);
  }

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
    return '${_categoryLabel(context, category)} (${widget.counts[category] ?? 0})';
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
        ),
    ];
  }

  void _selectCategory(String value, LibraryCategory current) {
    final category = LibraryCategory.values.firstWhere(
      (candidate) => candidate.storageKey == value,
      orElse: () => current,
    );
    if (category != current) {
      ref.read(libraryProvider.notifier).selectCategory(category);
    }
  }

  Widget _buildAnimatedContent({
    required Color primary,
    required String label,
  }) {
    final visible = !_menuOpen;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: visible ? _showDuration : _hideDuration,
      curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
      child: AnimatedScale(
        scale: visible ? 1 : 0.88,
        duration: visible ? _showDuration : _hideDuration,
        curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -0.18),
          duration: visible ? _showDuration : _hideDuration,
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_categoryIcon(widget.selected), color: primary, size: 22),
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
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: primary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final primary = Theme.of(context).colorScheme.primary;
    final label = _categoryLabelWithCount(context, widget.selected);
    final width = isArabic ? 240.0 : 224.0;
    final menuItems = _menuItems(context);
    final accessibilityLabel = isArabic ? 'اختر قائمة' : 'Choose list';
    final content = _buildAnimatedContent(primary: primary, label: label);

    if (!appleUsesPersistentLiquidGlassHeader) {
      return _MaterialCategoryMenu(
        selected: widget.selected,
        menuItems: menuItems,
        tintColor: primary,
        accessibilityLabel: accessibilityLabel,
        iconForValue: (value) {
          final category = LibraryCategory.values.firstWhere(
            (candidate) => candidate.storageKey == value,
            orElse: () => widget.selected,
          );
          return _categoryIcon(category);
        },
        onOpened: () => _setMenuOpen(true),
        onClosed: () => _setMenuOpen(false),
        onSelected: (value) {
          _selectCategory(value, widget.selected);
          _setMenuOpen(false);
        },
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
                onSelected: (value) {
                  _selectCategory(value, widget.selected);
                  _setMenuOpen(false);
                },
                onMenuOpened: () => _setMenuOpen(true),
                onMenuClosed: () => _setMenuOpen(false),
                accessibilityLabel: accessibilityLabel,
                systemImage: _categorySystemImage(widget.selected),
                fallbackIcon: _categoryIcon(widget.selected),
                selectedValue: widget.selected.storageKey,
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
    required this.onOpened,
    required this.onClosed,
    required this.child,
  });

  final LibraryCategory selected;
  final List<AppleNativeMenuItem> menuItems;
  final Color tintColor;
  final String accessibilityLabel;
  final IconData Function(String value) iconForValue;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpened;
  final VoidCallback onClosed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: accessibilityLabel,
      onOpened: onOpened,
      onCanceled: onClosed,
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
