import 'package:flutter/material.dart';

import '../../../../shared/widgets/apple_liquid_glass.dart';

/// Sort + filter controls — bare icons (no pill / circle chrome).
///
/// Layout is always [sort | filter] left-to-right. Opening sort hides the sort
/// icon with the same fade/scale/slide motion as the library category picker.
class SearchActionButtons extends StatefulWidget {
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

  /// Sort + filter tap targets (no divider chrome).
  static double groupWidthForHeight(double height) => height * 2;

  @override
  State<SearchActionButtons> createState() => _SearchActionButtonsState();
}

class _SearchActionButtonsState extends State<SearchActionButtons> {
  static const _hideDuration = Duration(milliseconds: 160);
  static const _showDuration = Duration(milliseconds: 200);

  bool _sortMenuOpen = false;

  void _setSortMenuOpen(bool open) {
    if (!mounted || _sortMenuOpen == open) return;
    setState(() => _sortMenuOpen = open);
  }

  void _onSortSelected(String value) {
    _setSortMenuOpen(false);
    widget.onSortSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tintColor ?? Theme.of(context).colorScheme.primary;
    final height = widget.height;

    return SizedBox(
      width: SearchActionButtons.groupWidthForHeight(height),
      height: height,
      // Keep sort on the left and filter on the right in Arabic and English.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: _buildSortControl(tint)),
            Expanded(
              child: _ActionIcon(
                tooltip: widget.filterTooltip,
                icon: Icons.tune_rounded,
                color: tint,
                size: height,
                onPressed:
                    widget.isFilterLoading ? null : widget.onFilterPressed,
                isLoading: widget.isFilterLoading,
                badgeCount: widget.filterCount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortIcon(Color tint) {
    final visible = !_sortMenuOpen;
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
          child: Icon(
            Icons.swap_vert_rounded,
            size: 22,
            color: tint,
          ),
        ),
      ),
    );
  }

  Widget _buildSortControl(Color tint) {
    final height = widget.height;
    final sortIcon = _buildSortIcon(tint);

    if (appleUsesPersistentLiquidGlassHeader) {
      return Semantics(
        button: true,
        label: widget.sortTooltip,
        child: SizedBox(
          width: height,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              sortIcon,
              Positioned.fill(
                child: AppleNativeMenuButton(
                  invisibleAnchor: true,
                  items: widget.sortItems,
                  onSelected: _onSortSelected,
                  onMenuOpened: () => _setSortMenuOpen(true),
                  onMenuClosed: () => _setSortMenuOpen(false),
                  accessibilityLabel: widget.sortTooltip,
                  systemImage: 'arrow.up.arrow.down',
                  fallbackIcon: Icons.swap_vert_rounded,
                  selectedValue: widget.sortValue,
                  width: height,
                  size: height,
                  tintColor: tint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: widget.sortTooltip,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 8),
      onOpened: () => _setSortMenuOpen(true),
      onCanceled: () => _setSortMenuOpen(false),
      onSelected: _onSortSelected,
      itemBuilder: (context) => [
        for (final item in widget.sortItems)
          PopupMenuItem<String>(
            value: item.value,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: widget.sortValue == item.value
                      ? Icon(Icons.check_rounded, size: 20, color: tint)
                      : Icon(
                          item.icon ?? Icons.swap_vert_rounded,
                          size: 18,
                          color: tint,
                        ),
                ),
                Expanded(child: Text(item.label)),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: height,
        height: height,
        child: Center(child: sortIcon),
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
                    Icon(icon, size: 22, color: color),
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
