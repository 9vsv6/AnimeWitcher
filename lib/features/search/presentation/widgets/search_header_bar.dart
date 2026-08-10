import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../search_provider.dart';
import '../search_text_direction.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/apple_liquid_glass.dart';

import 'package:skystream/core/utils/localized_text.dart';
/// Redesigned static widescreen/desktop search control bar.
class SearchHeaderBar extends ConsumerStatefulWidget {
  final TextEditingController textController;
  final FocusNode searchFocusNode;
  final FocusNode clearButtonFocusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onShowFilters;
  final VoidCallback onShowSort;
  final ValueChanged<String> onSortSelected;
  final String sortValue;
  final List<AppleNativeMenuItem> sortItems;
  final String sortTooltip;
  final int activeFilterCount;
  final bool isFilterLoading;
  final bool isCompact;

  const SearchHeaderBar({
    super.key,
    required this.textController,
    required this.searchFocusNode,
    required this.clearButtonFocusNode,
    required this.onSubmitted,
    required this.onChanged,
    required this.onShowFilters,
    required this.onShowSort,
    required this.onSortSelected,
    required this.sortValue,
    required this.sortItems,
    required this.sortTooltip,
    required this.activeFilterCount,
    required this.isFilterLoading,
    this.isCompact = false,
  });

  @override
  ConsumerState<SearchHeaderBar> createState() => _SearchHeaderBarState();
}

class _SearchHeaderBarState extends ConsumerState<SearchHeaderBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final isCompact = widget.isCompact;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: isCompact ? 360 : 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Static Search Field (Wrapped in GestureDetector so tapping anywhere focuses the text field)
            GestureDetector(
              onTap: () {
                if (!widget.searchFocusNode.hasFocus) {
                  widget.searchFocusNode.requestFocus();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : theme.colorScheme.outlineVariant,
                    width: 1.2,
                  ),
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.textController,
                  builder: (context, value, child) {
                    final isSearching = searchResultsAsync.maybeWhen(
                      data: (state) => state.isLoading,
                      loading: () => true,
                      orElse: () => false,
                    );

                    Widget? suffix;
                    if (isSearching) {
                      suffix = Padding(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: AppLoadingIndicator(
                            color: theme.colorScheme.primary,
                            constraints: BoxConstraints.tight(
                              const Size(20, 20),
                            ),
                          ),
                        ),
                      );
                    } else if (value.text.isNotEmpty) {
                      suffix = AnimatedBuilder(
                        animation: widget.clearButtonFocusNode,
                        builder: (context, child) {
                          final isFocused =
                              widget.clearButtonFocusNode.hasFocus;
                          return IconButton(
                            focusNode: widget.clearButtonFocusNode,
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: isFocused
                                  ? theme.colorScheme.primary
                                  : (isDark
                                        ? Colors.white70
                                        : theme.colorScheme.onSurfaceVariant),
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: isFocused
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.transparent,
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              widget.textController.clear();
                              ref
                                  .read(
                                    searchSuggestionControllerProvider.notifier,
                                  )
                                  .clear();
                              ref.read(searchQueryProvider.notifier).set('');
                              widget.searchFocusNode.requestFocus();
                            },
                          );
                        },
                      );
                    }

                    return TextField(
                      controller: widget.textController,
                      focusNode: widget.searchFocusNode,
                      autofocus: false,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                      textDirection: searchTextDirection(
                        value.text,
                        fallback: Directionality.of(context),
                      ),
                      textAlign: TextAlign.start,
                      textAlignVertical: TextAlignVertical.center,
                      textInputAction: TextInputAction.search,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      decoration: InputDecoration(
                        hintText: l10n.searchHint,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 46,
                          minHeight: 48,
                        ),
                        suffixIcon: suffix,
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 46,
                          minHeight: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Toggle scope switcher below
            AnimatedOpacity(
              opacity: isCompact ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: isCompact ? 0 : 38,
                child: isCompact
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: AppleSearchGlassActions(
                          filterCount: widget.activeFilterCount,
                          isFilterLoading: widget.isFilterLoading,
                          isArabic: Localizations.localeOf(context)
                                  .languageCode
                                  .toLowerCase() ==
                              'ar',
                          sortValue: widget.sortValue,
                          sortItems: widget.sortItems,
                          sortAccessibilityLabel: widget.sortTooltip,
                          filterAccessibilityLabel: appText(
                            context,
                            english: 'Filters',
                            arabic: 'الفلاتر',
                          ),
                          onSortPressed: widget.onShowSort,
                          onSortSelected: widget.onSortSelected,
                          onFilterPressed: widget.onShowFilters,
                          height: 38,
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


class _SearchControlButton extends StatelessWidget {
  const _SearchControlButton({
    required this.tooltip,
    required this.onTap,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isLoading = false,
    this.count = 0,
  });

  final String tooltip;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isLoading;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isActive ? colors.primary : colors.onSurfaceVariant;
    final radius = BorderRadius.circular(20);

    return Tooltip(
      message: tooltip,
      child: AppleLiquidGlassSurface(
        borderRadius: radius,
        style: 'regular',
        interactive: true,
        fallbackColor: colors.surfaceContainerHigh.withValues(alpha: 0.92),
        fallbackBorder: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.30),
        ),
        child: CardsWrapper(
          scaleFactor: 1.0,
          onTap: () {
            if (!isLoading) onTap();
          },
          borderRadius: radius,
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 7),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
