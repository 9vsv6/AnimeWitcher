import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../search_provider.dart';
import '../search_text_direction.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/apple_liquid_glass.dart';
import 'search_action_buttons.dart';

import 'package:skystream/core/utils/localized_text.dart';

/// Redesigned static widescreen/desktop search control bar.
class SearchHeaderBar extends ConsumerStatefulWidget {
  final TextEditingController textController;
  final FocusNode searchFocusNode;
  final FocusNode clearButtonFocusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onShowFilters;
  final ValueChanged<String> onSortSelected;
  final String sortValue;
  final List<AppleNativeMenuItem> sortItems;
  final IconData sortIcon;
  final String sortSystemImage;
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
    required this.onSortSelected,
    required this.sortValue,
    required this.sortItems,
    required this.sortIcon,
    required this.sortSystemImage,
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
    final searchHint =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar'
            ? 'Search...'
            : l10n.searchHint;

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: isCompact ? 360 : 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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
                    alpha: 0.92,
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
                      enableInteractiveSelection: true,
                      contextMenuBuilder: (context, editableTextState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: editableTextState.contextMenuButtonItems,
                        );
                      },
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      decoration: InputDecoration(
                        hintText: searchHint,
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
                          color: theme.colorScheme.primary,
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
                        child: SearchActionButtons(
                          filterCount: widget.activeFilterCount,
                          isFilterLoading: widget.isFilterLoading,
                          sortValue: widget.sortValue,
                          sortItems: widget.sortItems,
                          onSortSelected: widget.onSortSelected,
                          sortIcon: widget.sortIcon,
                          sortSystemImage: widget.sortSystemImage,
                          sortTooltip: widget.sortTooltip,
                          filterTooltip: appText(
                            context,
                            english: 'Filters',
                            arabic: 'الفلاتر',
                          ),
                          onFilterPressed: widget.onShowFilters,
                          tintColor: theme.colorScheme.primary,
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
