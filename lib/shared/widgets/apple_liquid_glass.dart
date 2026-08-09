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


const _appleSearchGlassActionsViewType =
    'dev.akash.skystream/search_glass_actions';
const _appleLiquidGlassPresenterChannel = MethodChannel(
  'dev.akash.skystream/liquid_glass_presenter',
);

/// Returns true only when iOS is using Apple's iOS 26+ Liquid Glass APIs.
Future<bool> appleNativeLiquidGlassAvailable() async {
  if (!_usesNativeAppleLiquidGlass) return false;
  try {
    return await _appleLiquidGlassPresenterChannel.invokeMethod<bool>(
          'isAvailable',
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Presents the sort picker as a fully native SwiftUI Liquid Glass overlay.
Future<String?> showAppleNativeSearchSort({
  required String initialValue,
  required List<Map<String, String>> items,
  required bool isArabic,
}) async {
  return _appleLiquidGlassPresenterChannel.invokeMethod<String>(
    'showSearchSort',
    <String, Object?>{
      'initialValue': initialValue,
      'items': items,
      'isArabic': isArabic,
    },
  );
}

/// Presents the full search filter UI inside the native iOS view hierarchy.
///
/// Keeping the labels and controls in the same native hierarchy as the glass
/// is important: Apple's Liquid Glass also applies foreground treatment to the
/// content above the material, which a background-only Flutter platform view
/// cannot reproduce.
Future<Map<String, dynamic>?> showAppleNativeSearchFilters({
  required Map<String, Object?> options,
  required Map<String, Object?> initialValue,
  required bool isArabic,
}) async {
  final response = await _appleLiquidGlassPresenterChannel.invokeMethod<Object?>(
    'showSearchFilters',
    <String, Object?>{
      'options': options,
      'initialValue': initialValue,
      'isArabic': isArabic,
    },
  );
  if (response == null) return null;
  if (response is Map) return Map<String, dynamic>.from(response);
  return null;
}

/// Two search actions rendered entirely by UIKit.
///
/// On iOS 26+ each action is its own UIGlassEffect and both are placed inside
/// one UIGlassContainerEffect so Apple owns sampling, refraction, merging,
/// native SF Symbols, and the interactive press response. Flutter only receives
/// semantic callbacks from the native controls.
class AppleSearchGlassActions extends StatefulWidget {
  const AppleSearchGlassActions({
    super.key,
    required this.onSortPressed,
    required this.onFilterPressed,
    required this.sortAccessibilityLabel,
    required this.filterAccessibilityLabel,
    this.filterCount = 0,
    this.isFilterLoading = false,
    this.isArabic = false,
    this.height = 44,
  });

  final VoidCallback onSortPressed;
  final VoidCallback onFilterPressed;
  final String sortAccessibilityLabel;
  final String filterAccessibilityLabel;
  final int filterCount;
  final bool isFilterLoading;
  final bool isArabic;
  final double height;

  @override
  State<AppleSearchGlassActions> createState() =>
      _AppleSearchGlassActionsState();
}

class _AppleSearchGlassActionsState extends State<AppleSearchGlassActions> {
  MethodChannel? _channel;

  Map<String, Object?> get _state => <String, Object?>{
    'filterCount': widget.filterCount,
    'filterLoading': widget.isFilterLoading,
    'isArabic': widget.isArabic,
    'sortAccessibilityLabel': widget.sortAccessibilityLabel,
    'filterAccessibilityLabel': widget.filterAccessibilityLabel,
  };

  @override
  void didUpdateWidget(covariant AppleSearchGlassActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterCount != widget.filterCount ||
        oldWidget.isFilterLoading != widget.isFilterLoading ||
        oldWidget.isArabic != widget.isArabic ||
        oldWidget.sortAccessibilityLabel != widget.sortAccessibilityLabel ||
        oldWidget.filterAccessibilityLabel != widget.filterAccessibilityLabel) {
      _channel?.invokeMethod<void>('update', _state);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel(
      'dev.akash.skystream/search_glass_actions/$id',
    );
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sortPressed':
          widget.onSortPressed();
          break;
        case 'filterPressed':
          widget.onFilterPressed();
          break;
      }
    });
    _channel = channel;
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    if (_usesNativeAppleLiquidGlass) {
      return SizedBox(
        width: height * 2 + 8,
        height: height,
        child: UiKitView(
          viewType: _appleSearchGlassActionsViewType,
          layoutDirection: TextDirection.ltr,
          creationParams: _state,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }

    return AppleLiquidGlassActionGroup(
      height: height,
      children: [
        AppleLiquidGlassToolbarButton(
          width: height,
          icon: Icons.sort_rounded,
          tooltip: widget.sortAccessibilityLabel,
          onPressed: widget.onSortPressed,
        ),
        AppleLiquidGlassToolbarButton(
          width: height,
          icon: Icons.tune_rounded,
          tooltip: widget.filterAccessibilityLabel,
          onPressed: widget.isFilterLoading ? null : widget.onFilterPressed,
        ),
      ],
    );
  }
}
