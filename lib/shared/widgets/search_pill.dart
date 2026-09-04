import 'package:flutter/material.dart';

import '../../core/utils/layout_constants.dart';
import '../../l10n/generated/app_localizations.dart';

/// The capsule that opens search, drawn the same way everywhere.
///
/// It reads as one control across the app: the same fill, the same hairline
/// and the same hint on a phone as on a desktop window. The keyboard hint is
/// the only part that differs, since there is no `/` key to press on a phone.
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.onTap,
    this.showShortcutHint = false,
    this.height = 38,
  });

  final VoidCallback onTap;

  /// Draws the `/` key badge. Only worth showing where there is a keyboard.
  final bool showShortcutHint;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // The hint follows the app's language while the row itself stays
    // left-to-right, so the magnifier is always on the leading edge.
    final contentDirection = Directionality.of(context);

    return Container(
      height: height,
      padding: EdgeInsets.only(left: 16, right: showShortcutHint ? 6 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
        border: Border.all(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
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
          if (showShortcutHint) ...[
            const SizedBox(width: 8),
            const SearchShortcutBadge(),
          ],
        ],
      ),
    );
  }
}

/// The `/` key, drawn the way a key is rather than as more placeholder text.
class SearchShortcutBadge extends StatelessWidget {
  const SearchShortcutBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.18),
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
    );
  }
}
