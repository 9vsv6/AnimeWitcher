import 'dart:async';

import 'package:flutter/material.dart';

/// One segment for [UnderlineSegmentTabs].
class UnderlineSegmentTab {
  const UnderlineSegmentTab({
    required this.label,
    this.icon,
    this.leading,
  });

  final String label;
  final IconData? icon;

  /// Optional custom leading widget (e.g. a loading spinner).
  /// Takes priority over [icon] when non-null.
  final Widget? leading;
}

/// Search-filter style tabs: gold label + underline when selected,
/// muted text when idle. Replaces the yellow pill chips.
class UnderlineSegmentTabs extends StatefulWidget {
  const UnderlineSegmentTabs({
    super.key,
    required this.selectedIndex,
    required this.tabs,
    required this.onSelected,
    this.isScrollable = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final int selectedIndex;
  final List<UnderlineSegmentTab> tabs;
  final ValueChanged<int> onSelected;
  final bool isScrollable;
  final EdgeInsetsGeometry padding;

  @override
  State<UnderlineSegmentTabs> createState() => _UnderlineSegmentTabsState();
}

class _UnderlineSegmentTabsState extends State<UnderlineSegmentTabs> {
  final GlobalKey _viewportKey = GlobalKey();
  late List<GlobalKey> _itemKeys;
  bool _visibilityCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = List<GlobalKey>.generate(
      widget.tabs.length,
      (_) => GlobalKey(),
    );
    _scheduleSelectedVisibility();
  }

  @override
  void didUpdateWidget(covariant UnderlineSegmentTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _itemKeys = List<GlobalKey>.generate(
        widget.tabs.length,
        (_) => GlobalKey(),
      );
    }
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.tabs.length != widget.tabs.length) {
      _scheduleSelectedVisibility();
    }
  }

  void _scheduleSelectedVisibility() {
    if (!widget.isScrollable || _visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      _revealSelectedIfNeeded();
    });
  }

  void _revealSelectedIfNeeded() {
    final index = widget.selectedIndex;
    if (index < 0 || index >= _itemKeys.length) return;

    final viewportContext = _viewportKey.currentContext;
    final itemContext = _itemKeys[index].currentContext;
    final viewportBox = viewportContext?.findRenderObject();
    final itemBox = itemContext?.findRenderObject();
    if (viewportBox is! RenderBox ||
        itemBox is! RenderBox ||
        !viewportBox.hasSize ||
        !itemBox.hasSize ||
        itemContext == null) {
      return;
    }

    final viewportOrigin = viewportBox.localToGlobal(Offset.zero);
    final itemOrigin = itemBox.localToGlobal(Offset.zero);
    final viewportLeft = viewportOrigin.dx + 4;
    final viewportRight = viewportOrigin.dx + viewportBox.size.width - 4;
    final itemLeft = itemOrigin.dx;
    final itemRight = itemOrigin.dx + itemBox.size.width;
    if (itemLeft >= viewportLeft && itemRight <= viewportRight) return;

    unawaited(
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;

    final row = Row(
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          widget.isScrollable
              ? _buildTab(context, i, colors)
              : Expanded(child: _buildTab(context, i, colors)),
      ],
    );

    final content = widget.isScrollable
        ? SingleChildScrollView(
            key: _viewportKey,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: row,
          )
        : Padding(
            key: _viewportKey,
            padding: widget.padding,
            child: row,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: dividerColor.withValues(alpha: 0.55)),
        ),
      ),
      child: content,
    );
  }

  Widget _buildTab(BuildContext context, int index, ColorScheme colors) {
    final tab = widget.tabs[index];
    final selected = widget.selectedIndex == index;
    final foreground =
        selected ? colors.primary : colors.onSurfaceVariant;

    Widget? leading = tab.leading;
    if (leading == null && tab.icon != null) {
      leading = Icon(tab.icon, size: 20, color: foreground);
    } else if (leading != null) {
      leading = IconTheme(
        data: IconThemeData(color: foreground, size: 20),
        child: leading,
      );
    }

    return KeyedSubtree(
      key: _itemKeys[index],
      child: InkWell(
        onTap: () => widget.onSelected(index),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
