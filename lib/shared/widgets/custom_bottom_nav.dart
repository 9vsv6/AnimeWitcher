import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skystream/core/navigation/taskbar_destination.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentBranchIndex;
  final List<TaskbarDestination> destinations;
  final ValueChanged<TaskbarDestination> onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentBranchIndex,
    required this.destinations,
    required this.onTap,
  });

  static const double height = 64;

  static double bottomInsetFor(BuildContext context) =>
      math.max(MediaQuery.viewPaddingOf(context).bottom - 8, 12);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final count = destinations.length;
    final selectedIndex = destinations.indexWhere(
      (destination) => destination.branchIndex == currentBranchIndex,
    );
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final visualIndex = selectedIndex < 0
        ? 0
        : (isRtl ? count - 1 - selectedIndex : selectedIndex);

    final highlight = AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: selectedIndex < 0 ? 0 : 1,
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: count <= 1
            ? Alignment.center
            : Alignment(-1 + 2 * (visualIndex / (count - 1)), 0),
        child: FractionallySizedBox(
          widthFactor: count == 0 ? 1 : 1 / count,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular((height - 12) / 2),
                color: colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
      ),
    );

    final tabs = <Widget>[
      for (final destination in destinations)
        Expanded(
          child: _NavTabCell(
            destination: destination,
            label: destination.label(localizations),
            isSelected: destination.branchIndex == currentBranchIndex,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(destination);
            },
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth.clamp(0.0, 420.0);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: SizedBox(
            width: fullWidth,
            height: height,
            child: defaultTargetPlatform == TargetPlatform.iOS
                ? AppleLiquidGlassSurface(
                    borderRadius: BorderRadius.circular(height / 2),
                    interactive: true,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        highlight,
                        Row(children: tabs),
                      ],
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      border: Border.all(
                        color: isDark
                            ? theme.dividerColor.withValues(alpha: 0.3)
                            : colorScheme.outline.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.35 : 0.12,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(height / 2),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          height: height,
                          color: colorScheme.surface.withValues(alpha: 0.8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              highlight,
                              Row(children: tabs),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _NavTabCell extends StatefulWidget {
  final TaskbarDestination destination;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTabCell({
    required this.destination,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavTabCell> createState() => _NavTabCellState();
}

class _NavTabCellState extends State<_NavTabCell> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        child: Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: _isFocused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              focusColor: Colors.transparent,
              hoverColor: colorScheme.primary.withValues(alpha: 0.08),
              onTap: widget.onTap,
              child: Center(
                child: Icon(
                  widget.isSelected
                      ? widget.destination.selectedIcon
                      : widget.destination.icon,
                  color: widget.isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
