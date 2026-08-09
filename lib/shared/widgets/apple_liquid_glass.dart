import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _appleLiquidGlassViewType = 'dev.akash.skystream/liquid_glass';

bool get _usesNativeAppleLiquidGlass =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// A real iOS Liquid Glass surface backed by UIKit's UIGlassEffect on iOS 26+.
///
/// Flutter only owns the content drawn above this surface. The material itself
/// is rendered by UIKit. Older iOS versions fall back to Apple's system blur.
class AppleLiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final String style;
  final bool interactive;
  final Color fallbackColor;
  final BorderSide? fallbackBorder;

  const AppleLiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.style = 'regular',
    this.interactive = false,
    this.fallbackColor = Colors.transparent,
    this.fallbackBorder,
  });

  @override
  Widget build(BuildContext context) {
    if (!_usesNativeAppleLiquidGlass) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fallbackColor,
          borderRadius: borderRadius,
          border: fallbackBorder == null ? null : Border.fromBorderSide(fallbackBorder!),
        ),
        child: child,
      );
    }

    final cornerRadius = borderRadius.topLeft.x;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: UiKitView(
                viewType: _appleLiquidGlassViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: <String, Object?>{
                  'style': style,
                  'interactive': interactive,
                  'cornerRadius': cornerRadius,
                },
                creationParamsCodec: const StandardMessageCodec(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AppleLiquidGlassBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final Color? foregroundColor;
  final Color? fallbackColor;
  final String? tooltip;

  const AppleLiquidGlassBackButton({
    super.key,
    this.onPressed,
    this.size = 46,
    this.foregroundColor,
    this.fallbackColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveForeground = foregroundColor ?? colors.onSurface;
    final effectiveFallback = fallbackColor ?? colors.surfaceContainerHigh;
    final radius = BorderRadius.circular(size / 2);

    return Center(
      child: SizedBox.square(
        dimension: size,
        child: AppleLiquidGlassSurface(
          borderRadius: radius,
          interactive: true,
          fallbackColor: effectiveFallback,
          fallbackBorder: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.28),
          ),
          child: IconButton(
            tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: effectiveForeground,
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(
              Icons.arrow_back_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}

class AppleLiquidGlassActionGroup extends StatelessWidget {
  final List<Widget> children;
  final double height;
  final Color? fallbackColor;

  const AppleLiquidGlassActionGroup({
    super.key,
    required this.children,
    this.height = 46,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppleLiquidGlassSurface(
      borderRadius: BorderRadius.circular(height / 2),
      interactive: true,
      fallbackColor: fallbackColor ?? colors.surfaceContainerHigh,
      fallbackBorder: BorderSide(
        color: colors.outlineVariant.withValues(alpha: 0.28),
      ),
      child: SizedBox(
        height: height,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class AppleLiquidGlassToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;
  final double width;

  const AppleLiquidGlassToolbarButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
    this.width = 46,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: double.infinity,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, color: color),
      ),
    );
  }
}
