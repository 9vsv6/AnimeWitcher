import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _appleLiquidGlassViewType = 'dev.akash.skystream/liquid_glass';
const _appleNativeGlassButtonViewType =
    'dev.akash.skystream/native_glass_button';
const _appleNativeToolbarViewType = 'dev.akash.skystream/native_toolbar';
const _appleNativeMenuButtonViewType =
    'dev.akash.skystream/native_menu_button';

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

    final effectiveOnPressed =
        onPressed ?? () => Navigator.of(context).maybePop();
    final effectiveTooltip =
        tooltip ?? MaterialLocalizations.of(context).backButtonTooltip;

    if (_usesNativeAppleLiquidGlass) {
      return Center(
        child: _AppleNativeGlassIconButton(
          systemName: 'chevron.left',
          onPressed: effectiveOnPressed,
          size: size,
          color: effectiveForeground,
          accessibilityLabel: effectiveTooltip,
        ),
      );
    }

    return Center(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: effectiveFallback,
            borderRadius: radius,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: IconButton(
            tooltip: effectiveTooltip,
            onPressed: effectiveOnPressed,
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
    if (_usesNativeAppleLiquidGlass &&
        children.isNotEmpty &&
        children.every((child) => child is AppleLiquidGlassToolbarButton)) {
      final buttons = children.cast<AppleLiquidGlassToolbarButton>();
      final canUseNative = buttons.every(
        (button) => _appleSystemSymbolForIcon(button.icon) != null,
      );
      if (canUseNative) {
        return _AppleNativeToolbar(buttons: buttons, height: height);
      }
    }

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
  final List<AppleNativeMenuItem> menuItems;
  final String? selectedMenuValue;
  final ValueChanged<String>? onMenuSelected;

  const AppleLiquidGlassToolbarButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
    this.width = 46,
    this.menuItems = const <AppleNativeMenuItem>[],
    this.selectedMenuValue,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    final nativeSymbol = _appleSystemSymbolForIcon(icon);
    if (_usesNativeAppleLiquidGlass && nativeSymbol != null) {
      if (menuItems.isNotEmpty && onMenuSelected != null) {
        return AppleNativeMenuButton(
          items: menuItems,
          onSelected: onMenuSelected!,
          accessibilityLabel: tooltip ?? '',
          systemImage: nativeSymbol,
          selectedValue: selectedMenuValue,
          fallbackIcon: icon,
          size: width,
        );
      }
      return _AppleNativeGlassIconButton(
        systemName: nativeSymbol,
        onPressed: onPressed,
        size: width,
        color: effectiveColor,
        accessibilityLabel: tooltip,
      );
    }

    return SizedBox(
      width: width,
      height: double.infinity,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: effectiveColor,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, color: color),
      ),
    );
  }
}
\n\nString? _appleSystemSymbolForIcon(IconData icon) {
  if (icon == Icons.chat_bubble_outline_rounded ||
      icon == Icons.chat_bubble_outline) {
    return 'bubble.left';
  }
  if (icon == Icons.favorite_rounded || icon == Icons.favorite) {
    return 'heart.fill';
  }
  if (icon == Icons.favorite_border_rounded ||
      icon == Icons.favorite_border) {
    return 'heart';
  }
  if (icon == Icons.bookmark_rounded || icon == Icons.bookmark) {
    return 'bookmark.fill';
  }
  if (icon == Icons.bookmark_border_rounded ||
      icon == Icons.bookmark_border) {
    return 'bookmark';
  }
  if (icon == Icons.sort_rounded || icon == Icons.sort) {
    return 'arrow.up.arrow.down';
  }
  if (icon == Icons.tune_rounded || icon == Icons.tune) {
    return 'slider.horizontal.3';
  }
  if (icon == Icons.refresh_rounded || icon == Icons.refresh) {
    return 'arrow.clockwise';
  }
  if (icon == Icons.close_rounded || icon == Icons.close) {
    return 'xmark';
  }
  if (icon == Icons.more_horiz_rounded || icon == Icons.more_horiz) {
    return 'ellipsis';
  }
  if (icon == Icons.download_rounded || icon == Icons.download) {
    return 'arrow.down';
  }
  if (icon == Icons.delete_outline_rounded || icon == Icons.delete_outline) {
    return 'trash';
  }
  if (icon == Icons.share_outlined || icon == Icons.share) {
    return 'square.and.arrow.up';
  }
  if (icon == Icons.link_rounded || icon == Icons.link) {
    return 'link';
  }
  if (icon == Icons.visibility_outlined || icon == Icons.visibility) {
    return 'eye';
  }
  if (icon == Icons.schedule_rounded || icon == Icons.schedule) {
    return 'clock';
  }
  return null;
}

class _AppleNativeGlassIconButton extends StatefulWidget {
  const _AppleNativeGlassIconButton({
    required this.systemName,
    required this.onPressed,
    required this.size,
    required this.color,
    this.accessibilityLabel,
  });

  final String systemName;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  final String? accessibilityLabel;

  @override
  State<_AppleNativeGlassIconButton> createState() =>
      _AppleNativeGlassIconButtonState();
}

class _AppleNativeGlassIconButtonState
    extends State<_AppleNativeGlassIconButton> {
  MethodChannel? _channel;

  Map<String, Object?> get _state => <String, Object?>{
    'systemName': widget.systemName,
    'enabled': widget.onPressed != null,
    'color': widget.color.toARGB32(),
    'accessibilityLabel': widget.accessibilityLabel,
  };

  @override
  void didUpdateWidget(covariant _AppleNativeGlassIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.systemName != widget.systemName ||
        oldWidget.onPressed != widget.onPressed ||
        oldWidget.color != widget.color ||
        oldWidget.accessibilityLabel != widget.accessibilityLabel) {
      _channel?.invokeMethod<void>('update', _state);
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel(
      'dev.akash.skystream/native_glass_button/$id',
    );
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed') widget.onPressed?.call();
    });
    _channel = channel;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: UiKitView(
        viewType: _appleNativeGlassButtonViewType,
        layoutDirection: TextDirection.ltr,
        creationParams: _state,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}

class _AppleNativeToolbar extends StatefulWidget {
  const _AppleNativeToolbar({required this.buttons, required this.height});

  final List<AppleLiquidGlassToolbarButton> buttons;
  final double height;

  @override
  State<_AppleNativeToolbar> createState() => _AppleNativeToolbarState();
}

class _AppleNativeToolbarState extends State<_AppleNativeToolbar> {
  MethodChannel? _channel;

  Map<String, Object?> get _state => <String, Object?>{
    'actions': <Map<String, Object?>>[
      for (final button in widget.buttons)
        <String, Object?>{
          'systemName': _appleSystemSymbolForIcon(button.icon),
          'enabled': button.onPressed != null ||
              (button.menuItems.isNotEmpty && button.onMenuSelected != null),
          'color': (button.color ?? Theme.of(context).colorScheme.onSurface)
              .toARGB32(),
          'accessibilityLabel': button.tooltip,
          'selectedValue': button.selectedMenuValue,
          'menuItems': button.menuItems
              .map((item) => item.toPlatformValue())
              .toList(growable: false),
        },
    ],
  };

  @override
  void didUpdateWidget(covariant _AppleNativeToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _channel?.invokeMethod<void>('update', _state);
    });
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('dev.akash.skystream/native_toolbar/$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed') {
        final index = call.arguments as int?;
        if (index == null || index < 0 || index >= widget.buttons.length) return;
        widget.buttons[index].onPressed?.call();
        return;
      }
      if (call.method == 'selected' && call.arguments is Map) {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final index = args['index'] as int?;
        final value = args['value'] as String?;
        if (index == null || value == null || index < 0 || index >= widget.buttons.length) {
          return;
        }
        widget.buttons[index].onMenuSelected?.call(value);
      }
    });
    _channel = channel;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.height * widget.buttons.length,
      height: widget.height,
      child: UiKitView(
        viewType: _appleNativeToolbarViewType,
        layoutDirection: Directionality.of(context),
        creationParams: _state,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}


class AppleNativeMenuItem {
  const AppleNativeMenuItem({
    required this.value,
    required this.label,
    this.systemImage,
    this.destructive = false,
  });

  final String value;
  final String label;
  final String? systemImage;
  final bool destructive;

  Map<String, Object?> toPlatformValue() => <String, Object?>{
    'value': value,
    'label': label,
    'systemImage': systemImage,
    'destructive': destructive,
  };
}

/// A system UIButton whose primary action is a UIMenu.
///
/// This is the same UIKit menu path used by Apple apps: the menu is attached
/// to the button with `menu` + `showsMenuAsPrimaryAction`, so iOS owns the
/// presentation, Liquid Glass material, morphing, selection checkmark, and
/// dismissal behavior. No Flutter dialog or custom blur is involved on iOS.
class AppleNativeMenuButton extends StatefulWidget {
  const AppleNativeMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    required this.accessibilityLabel,
    required this.systemImage,
    this.selectedValue,
    this.title,
    this.width,
    this.fallbackIcon = Icons.sort_rounded,
    this.size = 44,
    this.enabled = true,
  });

  final List<AppleNativeMenuItem> items;
  final ValueChanged<String> onSelected;
  final String accessibilityLabel;
  final String systemImage;
  final String? selectedValue;
  final String? title;
  final double? width;
  final IconData fallbackIcon;
  final double size;
  final bool enabled;

  @override
  State<AppleNativeMenuButton> createState() => _AppleNativeMenuButtonState();
}

class _AppleNativeMenuButtonState extends State<AppleNativeMenuButton> {
  MethodChannel? _channel;

  Map<String, Object?> get _state => <String, Object?>{
    'systemImage': widget.systemImage,
    'selectedValue': widget.selectedValue,
    'title': widget.title,
    'isRtl': Directionality.of(context) == TextDirection.rtl,
    'accessibilityLabel': widget.accessibilityLabel,
    'enabled': widget.enabled,
    'items': widget.items
        .map((item) => item.toPlatformValue())
        .toList(growable: false),
  };

  @override
  void didUpdateWidget(covariant AppleNativeMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _channel?.invokeMethod<void>('update', _state);
    });
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel(
      'dev.akash.skystream/native_menu_button/$id',
    );
    channel.setMethodCallHandler((call) async {
      if (call.method != 'selected') return;
      final value = call.arguments as String?;
      if (value != null) widget.onSelected(value);
    });
    _channel = channel;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? widget.size;
    if (_usesNativeAppleLiquidGlass) {
      return SizedBox(
        width: width,
        height: widget.size,
        child: UiKitView(
          viewType: _appleNativeMenuButtonViewType,
          layoutDirection: Directionality.of(context),
          creationParams: _state,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }

    return SizedBox(
      width: width,
      height: widget.size,
      child: PopupMenuButton<String>(
        enabled: widget.enabled,
        tooltip: widget.accessibilityLabel,
        onSelected: widget.onSelected,
        itemBuilder: (context) => [
          for (final item in widget.items)
            PopupMenuItem<String>(
              value: item.value,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: widget.selectedValue == item.value
                        ? const Icon(Icons.check_rounded, size: 20)
                        : Icon(widget.fallbackIcon, size: 18),
                  ),
                  Expanded(child: Text(item.label)),
                ],
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(widget.size / 2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.fallbackIcon, size: 19),
                if (widget.title != null && widget.title!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
              ],
            ),
          ),
        ),
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
    required this.onSortSelected,
    required this.onFilterPressed,
    required this.sortValue,
    required this.sortItems,
    required this.sortAccessibilityLabel,
    required this.filterAccessibilityLabel,
    this.filterCount = 0,
    this.isFilterLoading = false,
    this.isArabic = false,
    this.height = 44,
  });

  /// Fallback used outside iOS, where the existing Flutter sort dialog remains.
  final VoidCallback onSortPressed;
  final ValueChanged<String> onSortSelected;
  final VoidCallback onFilterPressed;
  final String sortValue;
  final List<AppleNativeMenuItem> sortItems;
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
    'sortValue': widget.sortValue,
    'sortItems': widget.sortItems
        .map((item) => item.toPlatformValue())
        .toList(growable: false),
    'sortAccessibilityLabel': widget.sortAccessibilityLabel,
    'filterAccessibilityLabel': widget.filterAccessibilityLabel,
  };

  @override
  void didUpdateWidget(covariant AppleSearchGlassActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _channel?.invokeMethod<void>('update', _state);
    });
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
        case 'sortSelected':
          final value = call.arguments as String?;
          if (value != null) widget.onSortSelected(value);
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
          layoutDirection: Directionality.of(context),
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
