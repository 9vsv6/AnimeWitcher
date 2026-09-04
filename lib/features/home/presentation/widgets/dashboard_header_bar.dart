import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animewitcher/core/utils/layout_constants.dart';
import 'package:animewitcher/core/utils/window_controls_inset.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/cards_wrapper.dart';

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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final contentDirection = Directionality.of(context);

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
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 16, right: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(
                          LayoutConstants.radiusPill,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.searchHint,
                              textDirection: contentDirection,
                              textAlign: contentDirection == TextDirection.rtl
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // The keyboard shortcut that opens search, shown the
                          // way a key is drawn rather than as more placeholder
                          // text.
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              '/',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
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
