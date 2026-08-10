import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _appleLiquidGlassViewType = 'dev.akash.skystream/liquid_glass';
const _appleNativeGlassButtonViewType =
    'dev.akash.skystream/native_glass_button';
const _appleNativeToolbarViewType = 'dev.akash.skystream/native_toolbar';
const _appleNativeSearchFieldViewType =
    'dev.akash.skystream/native_search_field';
const _appleNativeMenuButtonViewType =
    'dev.akash.skystream/native_menu_button';

bool get _usesNativeAppleLiquidGlass =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;


/// True on iOS where SkyStream hosts the native Liquid Glass controls.
/// Screens use this to hand their header actions to the persistent overlay
/// instead of creating route-local platform views that slide with transitions.
bool get appleUsesPersistentLiquidGlassHeader => _usesNativeAppleLiquidGlass;

class ApplePersistentGlassHeaderConfig {
  ApplePersistentGlassHeaderConfig({
    required this.owner,
    this.route,
    this.onBack,
    this.backTooltip,
    this.backForegroundColor,
    this.backFallbackColor,
    this.trailing,
    this.trailingButtons,
    this.branchIndex,
  });

  final Object owner;
  ModalRoute<dynamic>? route;
  VoidCallback? onBack;
  String? backTooltip;
  Color? backForegroundColor;
  Color? backFallbackColor;
  Widget? trailing;
  List<AppleLiquidGlassToolbarButton>? trailingButtons;
  int? branchIndex;

  bool visuallyMatches(ApplePersistentGlassHeaderConfig other) {
    final sameCustomTrailing = trailing == null && other.trailing == null ||
        identical(trailing, other.trailing);
    return (onBack != null) == (other.onBack != null) &&
        backTooltip == other.backTooltip &&
        backForegroundColor == other.backForegroundColor &&
        backFallbackColor == other.backFallbackColor &&
        branchIndex == other.branchIndex &&
        sameCustomTrailing &&
        _sameToolbarButtons(trailingButtons, other.trailingButtons);
  }

  void updateFrom(ApplePersistentGlassHeaderConfig other) {
    route = other.route;
    onBack = other.onBack;
    backTooltip = other.backTooltip;
    backForegroundColor = other.backForegroundColor;
    backFallbackColor = other.backFallbackColor;
    trailing = other.trailing;
    trailingButtons = other.trailingButtons;
    branchIndex = other.branchIndex;
  }
}

class ApplePersistentGlassHeaderController
    extends ValueNotifier<ApplePersistentGlassHeaderConfig?> {
  ApplePersistentGlassHeaderController() : super(null);

  // Mirrors UINavigationController's navigation-item stack: screens keep one
  // registered item while the single physical Liquid Glass chrome stays above
  // the Navigator. Rebuilding a covered route updates its item in place rather
  // than moving it to the top and stealing the visible controls.
  final List<ApplePersistentGlassHeaderConfig> _routeStack =
      <ApplePersistentGlassHeaderConfig>[];
  int? _activeBranchIndex;

  bool _belongsToActiveBranch(ApplePersistentGlassHeaderConfig config) =>
      config.branchIndex == null ||
      _activeBranchIndex == null ||
      config.branchIndex == _activeBranchIndex;

  bool _isCurrent(ApplePersistentGlassHeaderConfig config) =>
      _belongsToActiveBranch(config) &&
      (config.route == null || config.route!.isCurrent);

  bool _isActive(ApplePersistentGlassHeaderConfig config) =>
      _belongsToActiveBranch(config) &&
      (config.route == null || config.route!.isActive);

  void setActiveBranch(int index) {
    if (_activeBranchIndex == index) return;
    _activeBranchIndex = index;
    _syncVisibleItem();
  }

  void _syncVisibleItem() {
    ApplePersistentGlassHeaderConfig? next;

    // Prefer the navigation item owned by the current route. During an iOS
    // push/pop transition there can be a short interval where neither route
    // reports isCurrent. Falling back to the newest still-active route keeps
    // the single physical Liquid Glass back button mounted and only rebinds
    // its action, matching a UINavigationBar instead of fading/recreating it.
    for (final entry in _routeStack.reversed) {
      if (_isCurrent(entry)) {
        next = entry;
        break;
      }
    }
    if (next == null) {
      for (final entry in _routeStack.reversed) {
        if (_isActive(entry)) {
          next = entry;
          break;
        }
      }
    }

    if (!identical(value, next)) value = next;
  }

  void show(ApplePersistentGlassHeaderConfig config) {
    final existingIndex = _routeStack.indexWhere(
      (entry) => identical(entry.owner, config.owner),
    );
    if (existingIndex < 0) {
      _routeStack.add(config);
      _syncVisibleItem();
      return;
    }

    final existing = _routeStack[existingIndex];
    final wasVisible = identical(value, existing);
    final visualChanged = !existing.visuallyMatches(config);

    // Rebuilds from async details/search state frequently recreate callbacks even
    // when the visible Liquid Glass chrome is identical. Mutate the registered
    // navigation item in place so those rebuilds don't force the platform view
    // through another composition/layout pass during a route transition.
    existing.updateFrom(config);
    _syncVisibleItem();

    if (wasVisible && identical(value, existing) && visualChanged) {
      notifyListeners();
    }
  }

  void hide(Object owner) {
    _routeStack.removeWhere((entry) => identical(entry.owner, owner));
    _syncVisibleItem();
  }
}

final applePersistentGlassHeaderController =
    ApplePersistentGlassHeaderController();

/// Registers one route's navigation item with the app-wide native Liquid Glass
/// header. The physical controls live above the Navigator; this scope only
/// changes their action/content as the top route changes.
class ApplePersistentGlassHeaderScope extends StatefulWidget {
  const ApplePersistentGlassHeaderScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.onBack,
    this.backTooltip,
    this.backForegroundColor,
    this.backFallbackColor,
    this.trailing,
    this.trailingButtons,
    this.branchIndex,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Color? backForegroundColor;
  final Color? backFallbackColor;
  final Widget? trailing;
  final List<AppleLiquidGlassToolbarButton>? trailingButtons;
  final int? branchIndex;

  @override
  State<ApplePersistentGlassHeaderScope> createState() =>
      _ApplePersistentGlassHeaderScopeState();
}

class _ApplePersistentGlassHeaderScopeState
    extends State<ApplePersistentGlassHeaderScope> {
  void _publish() {
    if (!mounted || !appleUsesPersistentLiquidGlassHeader || !widget.enabled) {
      applePersistentGlassHeaderController.hide(this);
      return;
    }
    final hasTrailing = widget.trailing != null ||
        (widget.trailingButtons?.isNotEmpty ?? false);
    if (widget.onBack == null && !hasTrailing) {
      applePersistentGlassHeaderController.hide(this);
      return;
    }
    applePersistentGlassHeaderController.show(
      ApplePersistentGlassHeaderConfig(
        owner: this,
        route: ModalRoute.of(context),
        onBack: widget.onBack,
        backTooltip: widget.backTooltip,
        backForegroundColor: widget.backForegroundColor,
        backFallbackColor: widget.backFallbackColor,
        trailing: widget.trailing,
        trailingButtons: widget.trailingButtons,
        branchIndex: widget.branchIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    return widget.child;
  }

  @override
  void dispose() {
    applePersistentGlassHeaderController.hide(this);
    super.dispose();
  }
}


/// A single route-independent Liquid Glass header layer.
///
/// It lives above the Navigator in MaterialApp.builder, so route transitions
/// never translate the actual UIKit platform views. Screens only replace the
/// callbacks/content. The back control therefore stays at one physical
/// position while its destination changes, and the trailing toolbar can morph
/// between page-specific actions without spawning a second glass control.
class ApplePersistentGlassHeaderOverlay extends StatefulWidget {
  const ApplePersistentGlassHeaderOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ApplePersistentGlassHeaderOverlay> createState() =>
      _ApplePersistentGlassHeaderOverlayState();
}

class _ApplePersistentGlassHeaderOverlayState
    extends State<ApplePersistentGlassHeaderOverlay> {
  ApplePersistentGlassHeaderConfig? _lastConfig;
  Widget? _lastTrailing;
  List<AppleLiquidGlassToolbarButton>? _lastTrailingButtons;

  @override
  Widget build(BuildContext context) {
    if (!_usesNativeAppleLiquidGlass) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: ValueListenableBuilder<ApplePersistentGlassHeaderConfig?>(
              valueListenable: applePersistentGlassHeaderController,
              builder: (context, config, _) {
                if (config != null) {
                  _lastConfig = config;
                  if (config.trailing != null) _lastTrailing = config.trailing;
                  if (config.trailingButtons != null) {
                    _lastTrailingButtons = config.trailingButtons;
                  }
                }
                final effective = config ?? _lastConfig;
                final visible = config != null;
                final leavingGlassChrome = !visible;
                final showBack = visible && effective?.onBack != null;
                final activeButtons = config?.trailingButtons;
                final hasNativeToolbar = activeButtons != null && activeButtons.isNotEmpty;
                final showTrailing = visible &&
                    (hasNativeToolbar || config?.trailing != null);

                // Keep the trailing control in one fixed 3-button-wide slot.
                // The UIKit toolbar inside this slot changes its own width/items,
                // which lets iOS animate the Liquid Glass capsule into the single
                // comments-sort circle without creating a second platform view.
                final toolbarButtons = activeButtons ??
                    _lastTrailingButtons ??
                    const <AppleLiquidGlassToolbarButton>[];

                return SizedBox(
                  height: kToolbarHeight,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 8,
                          top: (kToolbarHeight - 46) / 2,
                          child: AnimatedOpacity(
                            opacity: showBack ? 1 : 0,
                            duration: Duration(
                              milliseconds: leavingGlassChrome
                                  ? 35
                                  : (showBack ? 160 : 55),
                            ),
                            curve: Curves.easeOutCubic,
                            child: AnimatedScale(
                              // When leaving for a route with no Liquid Glass
                              // chrome, keep geometry fixed and fade only.
                              scale: leavingGlassChrome
                                  ? 1
                                  : (showBack ? 1 : 0.88),
                              duration: Duration(
                                milliseconds: leavingGlassChrome
                                    ? 0
                                    : (showBack ? 190 : 70),
                              ),
                              curve: Curves.easeOutBack,
                              child: AppleLiquidGlassBackButton(
                                key: const ValueKey('persistent-liquid-back'),
                                size: 46,
                                foregroundColor: effective?.backForegroundColor,
                                fallbackColor: effective?.backFallbackColor,
                                tooltip: effective?.backTooltip,
                                onPressed: effective?.onBack ?? () {},
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          // Mirror the back button's 8pt screen inset. The native
                          // UIToolbar already reserves its own system trailing margin,
                          // so this keeps both the 3-action capsule and its 1-action
                          // comments-sort state fully on-screen while moving the sort
                          // circle back to the visual right edge. The same platform view
                          // stays mounted, so the UIKit 3 -> 1 morph is untouched.
                          right: 8,
                          top: (kToolbarHeight - 46) / 2,
                          child: IgnorePointer(
                            ignoring: !showTrailing,
                            child: AnimatedOpacity(
                              opacity: showTrailing ? 1 : 0,
                              duration: Duration(
                                milliseconds: leavingGlassChrome
                                    ? 35
                                    : (showTrailing ? 150 : 80),
                              ),
                              curve: Curves.easeOutCubic,
                              child: AnimatedScale(
                              alignment: Alignment.centerRight,
                              // Same fast fade-only exit as the back button.
                              scale: leavingGlassChrome
                                  ? 1
                                  : (showTrailing ? 1 : 0.94),
                              duration: Duration(
                                milliseconds: leavingGlassChrome
                                    ? 0
                                    : (showTrailing ? 180 : 95),
                              ),
                              curve: Curves.easeOutCubic,
                              child: hasNativeToolbar || _lastTrailingButtons != null
                                  ? AppleLiquidGlassActionGroup(
                                      key: const ValueKey('persistent-native-toolbar'),
                                      height: 46,
                                      minimumCapacity: 5,
                                      children: toolbarButtons,
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('persistent-custom-trailing'),
                                      child: config?.trailing ??
                                          _lastTrailing ??
                                          const SizedBox.shrink(),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

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
  final bool collapsed;
  final String collapsedSystemImage;
  final int minimumCapacity;

  const AppleLiquidGlassActionGroup({
    super.key,
    required this.children,
    this.height = 46,
    this.fallbackColor,
    this.collapsed = false,
    this.collapsedSystemImage = 'arrow.up.arrow.down',
    this.minimumCapacity = 0,
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
        return _AppleNativeToolbar(
          buttons: buttons,
          height: height,
          collapsed: collapsed,
          collapsedSystemImage: collapsedSystemImage,
          minimumCapacity: minimumCapacity,
        );
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
  final String? title;
  final double width;
  final List<AppleNativeMenuItem> menuItems;
  final String? selectedMenuValue;
  final ValueChanged<String>? onMenuSelected;
  final Color? menuTintColor;

  const AppleLiquidGlassToolbarButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
    this.title,
    this.width = 46,
    this.menuItems = const <AppleNativeMenuItem>[],
    this.selectedMenuValue,
    this.onMenuSelected,
    this.menuTintColor,
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
          title: title,
          selectedValue: selectedMenuValue,
          fallbackIcon: icon,
          size: width,
          tintColor: menuTintColor ?? effectiveColor,
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



bool _sameToolbarButtons(
  List<AppleLiquidGlassToolbarButton>? a,
  List<AppleLiquidGlassToolbarButton>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.icon != right.icon ||
        left.color != right.color ||
        left.tooltip != right.tooltip ||
        left.title != right.title ||
        left.width != right.width ||
        left.selectedMenuValue != right.selectedMenuValue ||
        left.menuTintColor != right.menuTintColor ||
        (left.onPressed != null) != (right.onPressed != null) ||
        (left.onMenuSelected != null) != (right.onMenuSelected != null) ||
        !_sameMenuItems(left.menuItems, right.menuItems)) {
      return false;
    }
  }
  return true;
}

bool _sameMenuItems(List<AppleNativeMenuItem> a, List<AppleNativeMenuItem> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.value != right.value ||
        left.label != right.label ||
        left.systemImage != right.systemImage ||
        left.destructive != right.destructive) {
      return false;
    }
  }
  return true;
}

String? _appleSystemSymbolForIcon(IconData icon) {
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
  if (icon == Icons.search_rounded || icon == Icons.search) {
    return 'magnifyingglass';
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
  if (icon == Icons.play_circle_fill_rounded ||
      icon == Icons.play_circle_fill) {
    return 'play.circle.fill';
  }
  if (icon == Icons.pause_circle_filled_rounded ||
      icon == Icons.pause_circle_filled) {
    return 'pause.circle.fill';
  }
  if (icon == Icons.check_circle_rounded || icon == Icons.check_circle) {
    return 'checkmark.circle.fill';
  }
  if (icon == Icons.block_rounded || icon == Icons.block) {
    return 'xmark.circle.fill';
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
  const _AppleNativeToolbar({
    required this.buttons,
    required this.height,
    required this.collapsed,
    required this.collapsedSystemImage,
    required this.minimumCapacity,
  });

  final List<AppleLiquidGlassToolbarButton> buttons;
  final double height;
  final bool collapsed;
  final String collapsedSystemImage;
  final int minimumCapacity;

  @override
  State<_AppleNativeToolbar> createState() => _AppleNativeToolbarState();
}

class _AppleNativeToolbarState extends State<_AppleNativeToolbar> {
  MethodChannel? _channel;
  String? _lastSentStateSignature;

  Map<String, Object?> get _state => <String, Object?>{
    'collapsed': widget.collapsed,
    'collapsedSystemImage': widget.collapsedSystemImage,
    'itemExtent': widget.height,
    'hostWidth': widget.height *
            (widget.minimumCapacity > widget.buttons.length
                ? widget.minimumCapacity
                : widget.buttons.length) +
        32,
    'actions': <Map<String, Object?>>[
      for (final button in widget.buttons)
        <String, Object?>{
          'systemName': _appleSystemSymbolForIcon(button.icon),
          'title': button.title,
          'enabled': button.onPressed != null ||
              (button.menuItems.isNotEmpty && button.onMenuSelected != null),
          'color': (button.color ?? Theme.of(context).colorScheme.onSurface)
              .toARGB32(),
          'accessibilityLabel': button.tooltip,
          'selectedValue': button.selectedMenuValue,
          'menuTintColor': button.menuTintColor?.toARGB32(),
          'menuItems': button.menuItems
              .map((item) => item.toPlatformValue())
              .toList(growable: false),
        },
    ],
  };

  String get _stateSignature => jsonEncode(_state);

  void _sendStateIfChanged() {
    if (!mounted || _channel == null) return;
    final signature = _stateSignature;
    if (signature == _lastSentStateSignature) return;
    _lastSentStateSignature = signature;
    _channel?.invokeMethod<void>('update', _state);
  }

  @override
  void didUpdateWidget(covariant _AppleNativeToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stateSignature == _lastSentStateSignature) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendStateIfChanged());
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
    // creationParams already contain the current state; don't immediately
    // replay it as an animated update when the first Flutter rebuild arrives.
    _lastSentStateSignature = _stateSignature;
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UIToolbar keeps a small system inset around grouped bar items on
    // iOS 26. Reserve it in Flutter so the trailing bookmark is never clipped
    // by the screen edge while keeping the native glass group intact.
    final capacity = widget.minimumCapacity > widget.buttons.length
        ? widget.minimumCapacity
        : widget.buttons.length;
    final nativeWidth = widget.height * capacity + 32;
    return SizedBox(
      width: nativeWidth,
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



/// A native iOS search field backed by Apple's UIGlassEffect + UISearchTextField.
/// The entire editable control is one UIKit platform view, so the system glass
/// and text input are composited together instead of stacking a Flutter field
/// over a separate blur surface.
class AppleNativeGlassSearchField extends StatefulWidget {
  const AppleNativeGlassSearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    required this.onSubmitted,
    required this.tintColor,
    required this.textColor,
    required this.placeholderColor,
    this.focusRequest = 0,
    this.loading = false,
    this.textDirection = TextDirection.ltr,
    this.height = 42,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final Color tintColor;
  final Color textColor;
  final Color placeholderColor;
  final int focusRequest;
  final bool loading;
  final TextDirection textDirection;
  final double height;

  @override
  State<AppleNativeGlassSearchField> createState() =>
      _AppleNativeGlassSearchFieldState();
}

class _AppleNativeGlassSearchFieldState
    extends State<AppleNativeGlassSearchField> {
  MethodChannel? _channel;
  bool _updatingFromNative = false;
  String? _lastSentSignature;

  Map<String, Object?> get _state => <String, Object?>{
        'text': widget.controller.text,
        'placeholder': widget.placeholder,
        'tintColor': widget.tintColor.toARGB32(),
        'textColor': widget.textColor.toARGB32(),
        'placeholderColor': widget.placeholderColor.toARGB32(),
        'rtl': widget.textDirection == TextDirection.rtl,
        'loading': widget.loading,
        'height': widget.height,
      };

  String get _signature => jsonEncode(_state);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppleNativeGlassSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    _sendStateIfChanged();
    if (oldWidget.focusRequest != widget.focusRequest && widget.focusRequest > 0) {
      _channel?.invokeMethod<void>('focus');
    }
  }

  void _controllerChanged() {
    if (_updatingFromNative) return;
    _sendStateIfChanged();
  }

  void _sendStateIfChanged() {
    if (!mounted || _channel == null) return;
    final signature = _signature;
    if (signature == _lastSentSignature) return;
    _lastSentSignature = signature;
    _channel?.invokeMethod<void>('update', _state);
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('dev.akash.skystream/native_search_field/$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && call.arguments is String) {
        final text = call.arguments as String;
        _updatingFromNative = true;
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _updatingFromNative = false;
        _lastSentSignature = _signature;
        widget.onChanged(text);
        return;
      }
      if (call.method == 'submitted' && call.arguments is String) {
        widget.onSubmitted(call.arguments as String);
      }
    });
    _channel = channel;
    _lastSentSignature = _signature;
    if (widget.focusRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _channel?.invokeMethod<void>('focus');
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNativeAppleLiquidGlass) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        viewType: _appleNativeSearchFieldViewType,
        layoutDirection: widget.textDirection,
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
    this.tintColor,
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
  final Color? tintColor;

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
    'tintColor': widget.tintColor?.toARGB32(),
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
                        ? Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: widget.tintColor,
                          )
                        : Icon(
                            widget.fallbackIcon,
                            size: 18,
                            color: widget.tintColor,
                          ),
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
                Icon(widget.fallbackIcon, size: 19, color: widget.tintColor),
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
  required Color tintColor,
}) async {
  return _appleLiquidGlassPresenterChannel.invokeMethod<String>(
    'showSearchSort',
    <String, Object?>{
      'initialValue': initialValue,
      'items': items,
      'isArabic': isArabic,
      'tintColor': tintColor.toARGB32(),
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
  required Color tintColor,
}) async {
  final response = await _appleLiquidGlassPresenterChannel.invokeMethod<Object?>(
    'showSearchFilters',
    <String, Object?>{
      'options': options,
      'initialValue': initialValue,
      'isArabic': isArabic,
      'tintColor': tintColor.toARGB32(),
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
    this.height = 42,
    this.tintColor,
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
  final Color? tintColor;

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
    'tintColor': (widget.tintColor ?? Theme.of(context).colorScheme.primary)
        .toARGB32(),
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
      // AppBar gives leading/actions its full toolbar height. Keep the native
      // controls in an Align so UIKit receives the requested square height
      // instead of being stretched vertically into rounded rectangles.
      return Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: height * 2 + 8,
          height: height,
          child: UiKitView(
            viewType: _appleSearchGlassActionsViewType,
            layoutDirection: Directionality.of(context),
            creationParams: _state,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
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
          color: widget.tintColor ?? Theme.of(context).colorScheme.primary,
          onPressed: widget.onSortPressed,
        ),
        AppleLiquidGlassToolbarButton(
          width: height,
          icon: Icons.tune_rounded,
          tooltip: widget.filterAccessibilityLabel,
          color: widget.tintColor ?? Theme.of(context).colorScheme.primary,
          onPressed: widget.isFilterLoading ? null : widget.onFilterPressed,
        ),
      ],
    );
  }
}
