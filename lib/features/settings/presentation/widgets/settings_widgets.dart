import 'package:flutter/material.dart';
import '../../../../core/utils/layout_constants.dart';

import 'package:animewitcher/core/utils/localized_text.dart';

/// A run of settings in one panel, under a quiet heading.
///
/// The same shape on the phone and the desktop: a small grey label naming the
/// group, then its settings as rows of one panel rather than a stack of
/// separate cards — eight cards down a page is eight objects to take in
/// before a word has been read, where one panel is a list.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutConstants.spacingMd,
              LayoutConstants.spacingLg,
              LayoutConstants.spacingMd,
              LayoutConstants.spacingXs,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutConstants.spacingMd,
          ),
          child: DecoratedBox(
            // A neutral grey, mixed from the page rather than taken from
            // surfaceContainerHighest: the scheme is seeded from the app's
            // amber, so that token carries a brown tint the mock did not.
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                colors.onSurface.withValues(alpha: 0.06),
                colors.surface,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(children: children),
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatefulWidget {
  final IconData icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;
  final bool isBeta;
  final FocusNode? focusNode;

  const SettingsTile({
    super.key,
    required this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isLast = false,
    this.isBeta = false,
    this.focusNode,
  });

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _isFocused = false;

  /// Longest a subtitle can be and still read as the setting's current value.
  ///
  /// "داكن", "10 ثانية", "3 دقيقة" are values and belong on the pill at the
  /// end of the row, where a column of them can be read down. A sentence
  /// explaining what a switch does is not a value and stays under its title,
  /// where it has the width to be read.
  static const int _valueLengthLimit = 28;

  bool get _showsValuePill {
    final subtitle = widget.subtitle?.trim();
    if (subtitle == null || subtitle.isEmpty) return false;
    // A row with its own control has its answer there already.
    if (widget.trailing != null) return false;
    return subtitle.length <= _valueLengthLimit && !subtitle.contains('\n');
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        Focus(
          // Passive observer — we want the inner ListTile's InkWell to remain
          // the actual focus target (it's what handles onTap when OK is
          // pressed). hasFocus on this node reflects "any descendant focused"
          // so onFocusChange still fires when the tile is reached.
          focusNode: widget.focusNode,
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) {
            setState(() => _isFocused = f);
            if (f) {
              // Center the focused setting row in the viewport.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final ctx = FocusManager.instance.primaryFocus?.context;
                final ro = ctx?.findRenderObject();
                if (ctx != null && ctx.mounted && ro != null) {
                  Scrollable.maybeOf(ctx)?.position.ensureVisible(
                    ro,
                    alignment: 0.5,
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.fastOutSlowIn,
                  );
                }
              });
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _isFocused
                  ? primary.withValues(alpha: 0.22)
                  : Colors.transparent,
              border: Border.all(
                color: _isFocused ? primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                focusColor: Colors.transparent,
                hoverColor: primary.withValues(alpha: 0.10),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spacingMd,
                  vertical: LayoutConstants.spacingXs,
                ),
                leading:
                    widget.leading ??
                    SizedBox.square(
                      dimension: 24,
                      child: Icon(widget.icon, color: primary, size: 21),
                    ),
                minLeadingWidth: 24,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                    ),
                    if (widget.isBeta) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          appText(context, english: 'BETA', arabic: 'تجريبي'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: _showsValuePill
                    ? null
                    : widget.subtitle != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      )
                    : null,
                trailing: _showsValuePill
                    ? _ValuePill(text: widget.subtitle!)
                    : widget.trailing ??
                          const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: widget.onTap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        if (!widget.isLast && !_isFocused)
          // Starting where the text starts, so the glyphs read as one column
          // rather than each row as a box of its own.
          Divider(
            height: 1,
            indent: 56,
            endIndent: LayoutConstants.spacingMd,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
      ],
    );
  }
}

/// A setting's current value, at the end of its row.
class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
