import 'package:flutter/material.dart';

import '../../../../shared/widgets/apple_liquid_glass.dart';

/// Shared geometry for the editable search field and its action capsule.
class SearchGlassSurface extends StatelessWidget {
  const SearchGlassSurface({super.key, required this.child});

  static const double height = 48;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AppleLiquidGlassSurface(
                borderRadius: BorderRadius.circular(height / 2),
                fallbackColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                fallbackBorder: BorderSide(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.12),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
