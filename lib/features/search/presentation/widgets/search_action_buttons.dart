import 'package:flutter/material.dart';

import '../../../../shared/widgets/apple_liquid_glass.dart';

/// Sort + filter controls for search — solid Material chrome (no liquid glass).
///
/// On iPhone the sort icon stays visible while an invisible native menu anchor
/// presents the system UIMenu with Liquid Glass. Other platforms use a popup
/// menu like the library category picker.
class SearchActionButtons extends StatelessWidget {
  const SearchActionButtons({
    super.key,
    required this.sortValue,
    required this.sortItems,
    required this.onSortSelected,
    required this.onFilterPressed,
    required this.sortTooltip,
    required this.filterTooltip,
    required this.sortIcon,
    required this.sortSystemImage,
    this.filterCount = 0,
    this.isFilterLoading = false,
    this.height = 42,
    this.tintColor,
  });

  final String sortValue;
  final List<AppleNativeMenuItem> sortItems;
  final ValueChanged<String> onSortSelected;
  final VoidCallback onFilterPressed;
  final String sortTooltip;
  final String filterTooltip;
  final IconData sortIcon;
  final String sortSystemImage;
  final int filterCount;
  final bool isFilterLoading;
  final double height;
  final Color? tintColor;

  /// Two square action buttons plus the divider between them.
  static double groupWidthForHeight(double height) => height * 2 + 1;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = tintColor ?? colors.primary;
    final radius = BorderRadius.circular(height / 2);
    final groupWidth = groupWidthForHeight(height);

    return SizedBox(
      width: groupWidth,
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(child: _buildSortControl(context, tint)),
              Container(
                width: 1,
                height: height * 0.48,
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
              Expanded(
                child: _ActionIcon(
                  tooltip: filterTooltip,
                  icon: Icons.tune_rounded,
                  color: tint,
                  size: height,
                  onPressed: isFilterLoading ? null : onFilterPressed,
                  isLoading: isFilterLoading,
                  badgeCount: filterCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortControl(BuildContext context, Color tint) {
    if (appleUsesPersistentLiquidGlassHeader) {
      return Semantics(
        button: true,
        label: sortTooltip,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(sortIcon, size: 20, color: tint),
            Positioned.fill(
              child: AppleNativeMenuButton(
                invisibleAnchor: true,
                items: sortItems,
                onSelected: onSortSelected,
                accessibilityLabel: sortTooltip,
                systemImage: sortSystemImage,
                fallbackIcon: sortIcon,
                selectedValue: sortValue,
                width: height,
                size: height,
                tintColor: tint,
              ),
            ),
          ],
        ),
      );
    }

    return _SortPopupMenu(
      sortItems: sortItems,
      sortValue: sortValue,
      sortIcon: sortIcon,
      sortTooltip: sortTooltip,
      tintColor: tint,
      height: height,
      onSortSelected: onSortSelected,
    );
  }
}

class _SortPopupMenu extends StatelessWidget {
  const _SortPopupMenu({
    required this.sortItems,
    required this.sortValue,
    required this.sortIcon,
    required this.sortTooltip,
    required this.tintColor,
    required this.height,
    required this.onSortSelected,
  });

  final List<AppleNativeMenuItem> sortItems;
  final String sortValue;
  final IconData sortIcon;
  final String sortTooltip;
  final Color tintColor;
  final double height;
  final ValueChanged<String> onSortSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: sortTooltip,
      onSelected: onSortSelected,
      itemBuilder: (context) => [
        for (final item in sortItems)
          PopupMenuItem<String>(
            value: item.value,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: sortValue == item.value
                      ? Icon(Icons.check_rounded, size: 20, color: tintColor)
                      : const SizedBox(width: 20, height: 20),
                ),
                Expanded(child: Text(item.label)),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: height,
        height: height,
        child: Icon(sortIcon, size: 20, color: tintColor),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
    this.isLoading = false,
    this.badgeCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onPressed;
  final bool isLoading;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showBadge = badgeCount > 0 && !isLoading;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: color,
            backgroundColor: Colors.transparent,
            minimumSize: Size(size, size),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: isLoading
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 20, color: color),
                    if (showBadge)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colors.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
