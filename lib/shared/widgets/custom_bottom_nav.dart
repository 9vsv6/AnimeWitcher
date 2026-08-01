import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

const _liquidGlassTabBarViewType =
    'dev.akash.skystream/liquid_glass_tab_bar';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final destinations = <_BottomNavDestination>[
      _BottomNavDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: localizations.home,
      ),
      _BottomNavDestination(
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        label: localizations.search,
      ),
      _BottomNavDestination(
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        label: localizations.explore,
      ),
      _BottomNavDestination(
        icon: Icons.video_library_outlined,
        selectedIcon: Icons.video_library,
        label: localizations.library,
      ),
      _BottomNavDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: localizations.settings,
      ),
    ];

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _NativeLiquidGlassBottomNavBar(
        currentIndex: currentIndex,
        labels: destinations.map((destination) => destination.label).toList(),
        onTap: onTap,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: colorScheme.surface),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.15),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 65,
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(
                destination.selectedIcon,
                color: colorScheme.primary,
              ),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _NativeLiquidGlassBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final List<String> labels;
  final ValueChanged<int> onTap;

  const _NativeLiquidGlassBottomNavBar({
    required this.currentIndex,
    required this.labels,
    required this.onTap,
  });

  @override
  State<_NativeLiquidGlassBottomNavBar> createState() =>
      _NativeLiquidGlassBottomNavBarState();
}

class _NativeLiquidGlassBottomNavBarState
    extends State<_NativeLiquidGlassBottomNavBar> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant _NativeLiquidGlassBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _channel?.invokeMethod<void>('setSelectedIndex', widget.currentIndex);
    }
  }

  void _onPlatformViewCreated(int viewId) {
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('${_liquidGlassTabBarViewType}_$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap') {
        final index = call.arguments as int?;
        if (index != null && mounted) {
          widget.onTap(index);
        }
      }
    });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final textDirection = Directionality.of(context);
    final appearanceKey = Object.hash(
      theme.brightness,
      accentColor.toARGB32(),
      textDirection,
      Object.hashAll(widget.labels),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: SizedBox(
        height: 72,
        child: UiKitView(
          key: ValueKey(appearanceKey),
          viewType: _liquidGlassTabBarViewType,
          creationParams: <String, Object>{
            'selectedIndex': widget.currentIndex,
            'labels': widget.labels,
            'accentColor': accentColor.toARGB32(),
            'brightness': theme.brightness.name,
            'textDirection': textDirection.name,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      ),
    );
  }
}

class _BottomNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _BottomNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
