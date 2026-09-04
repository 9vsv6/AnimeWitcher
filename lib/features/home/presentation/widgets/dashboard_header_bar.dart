import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animewitcher/core/utils/layout_constants.dart';
import 'package:animewitcher/core/utils/window_controls_inset.dart';
import 'package:animewitcher/shared/widgets/cards_wrapper.dart';
import 'package:animewitcher/shared/widgets/search_pill.dart';

/// A custom header bar for the widescreen dashboard layout.
///
/// Holds the capsule search, centred in the strip that the window's own
/// controls are painted over.
class DashboardHeaderBar extends ConsumerWidget {
  final FocusNode searchFocusNode;
  final VoidCallback onShowSearch;

  const DashboardHeaderBar({
    super.key,
    required this.searchFocusNode,
    required this.onShowSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The window's own controls are painted over this same strip. Both sides
    // are reserved equally rather than only the side in use, so the search
    // stays centred in the window while still clearing them.
    return Container(
      height: LayoutConstants.dashboardHeaderHeight,
      padding: EdgeInsets.symmetric(
        horizontal:
            LayoutConstants.dashboardContentPadding +
            windowControlsSymmetricInset,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            // Capsule search bar, centred in the bar rather than filling it, so
            // it stays put as the controls on either side change width.
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: CardsWrapper(
                    scaleFactor: 1.01,
                    focusNode: searchFocusNode,
                    onTap: onShowSearch,
                    borderRadius: BorderRadius.circular(
                      LayoutConstants.radiusPill,
                    ),
                    child: SearchPill(
                      onTap: onShowSearch,
                      showShortcutHint: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
