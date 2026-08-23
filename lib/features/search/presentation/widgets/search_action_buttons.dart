import 'package:flutter/material.dart';

/// Sort + filter controls for search — solid Material chrome (no liquid glass).
///
/// Sort still opens the existing liquid-glass sort menu via [onSortPressed].
/// Filter shows a small count badge when [filterCount] is greater than zero.
class SearchActionButtons extends StatelessWidget {
  const SearchActionButtons({
    super.key,
    required this.onSortPressed,
    required this.onFilterPressed,
    required this.sortTooltip,
    required this.filterTooltip,
    this.filterCount = 0,
    this.isFilterLoading = false,
    this.height = 42,
    this.tintColor,
  });

  final VoidCallback onSortPressed;
  final VoidCallback onFilterPressed;
  final String sortTooltip;
  final String filterTooltip;
  final int filterCount;
  final bool isFilterLoading;
  final double height;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = tintColor ?? colors.primary;
    final radius = BorderRadius.circular(height / 2);

    return Material(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionIcon(
              tooltip: sortTooltip,
              icon: Icons.star_rounded,
              color: tint,
              size: height,
              onPressed: onSortPressed,
            ),
            Container(
              width: 1,
              height: height * 0.48,
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
            _ActionIcon(
              tooltip: filterTooltip,
              icon: Icons.tune_rounded,
              color: tint,
              size: height,
              onPressed: isFilterLoading ? null : onFilterPressed,
              isLoading: isFilterLoading,
              badgeCount: filterCount,
            ),
          ],
        ),
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
