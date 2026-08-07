import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../home/presentation/widgets/provider_search_filter_dialog.dart';
import 'search_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/search_result_section.dart';
import 'widgets/search_header_bar.dart';
import 'widgets/bouncy_entry_animation.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';

import 'package:skystream/core/utils/localized_text.dart';
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _clearButtonFocusNode = FocusNode();
  final FocusNode _firstSuggestionFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  bool _isLoadingProviderFilters = false;
  int _lastFocusRequest = 0;
  int _lastClearRequest = 0;

  @override
  void initState() {
    super.initState();
    // Restore any previously committed query into the text field.
    _controller.text = ref.read(searchQueryProvider);
    _lastFocusRequest = ref.read(searchFocusRequestProvider);
    _lastClearRequest = ref.read(searchClearRequestProvider);
    _controller.addListener(_onTextChanged);
    _resultsScrollController.addListener(_onResultsScroll);
    ref.read(searchFilterProvider.notifier).set(SearchFilter.content);

    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_controller.text.isNotEmpty &&
              _controller.selection.extentOffset == _controller.text.length) {
            _clearButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final suggestionState = ref.read(searchSuggestionControllerProvider);
          final hasSuggestions = suggestionState.query.trim().length >= 2 &&
              (suggestionState.isLoading || suggestionState.suggestions.isNotEmpty);
          if (hasSuggestions) {
            _firstSuggestionFocusNode.requestFocus();
          } else {
            _firstResultFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _clearButtonFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _focusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final suggestionState = ref.read(searchSuggestionControllerProvider);
          final hasSuggestions = suggestionState.query.trim().length >= 2 &&
              (suggestionState.isLoading || suggestionState.suggestions.isNotEmpty);
          if (hasSuggestions) {
            _firstSuggestionFocusNode.requestFocus();
          } else {
            _firstResultFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };





    _firstResultFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }


  void _onResultsScroll() {
    if (!_resultsScrollController.hasClients) return;
    if (_resultsScrollController.position.extentAfter < 600) {
      ref.read(searchPagedResultsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _resultsScrollController.removeListener(_onResultsScroll);
    _resultsScrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _clearButtonFocusNode.dispose();
    _firstSuggestionFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showSearchFilters() async {
    if (_isLoadingProviderFilters) return;
    final providers = ref
        .read(extensionManagerProvider.notifier)
        .getAllProviders();
    if (providers.isEmpty) return;

    setState(() => _isLoadingProviderFilters = true);
    try {
      final options = await providers.first.getSearchFilterOptions();
      if (!mounted) return;
      if (options.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode == 'ar'
                    ? 'لا توجد فلاتر متاحة'
                    : 'No filters available',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      final selected = await showDialog<ProviderSearchFilters>(
        context: context,
        builder: (_) => ProviderSearchFilterDialog(
          options: options,
          initialValue: ref.read(searchProviderFiltersProvider),
        ),
      );
      if (selected != null && mounted) {
        ref.read(searchProviderFiltersProvider.notifier).set(selected);
        ref.read(searchFilterProvider.notifier).set(SearchFilter.content);
      }
    } finally {
      if (mounted) setState(() => _isLoadingProviderFilters = false);
    }
  }

  void _submitSearch(String val) {
    final trimmed = val.trim();
    _controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    ref.read(searchSuggestionControllerProvider.notifier).clear();
    ref.read(searchQueryProvider.notifier).set(trimmed);
    // Dismiss keyboard after submitting, just like YouTube / browser.
    _focusNode.unfocus();
  }

  void _fillSuggestion(String suggestion) {
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    ref
        .read(searchSuggestionControllerProvider.notifier)
        .onQueryChanged(suggestion);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final clearRequest = ref.watch(searchClearRequestProvider);
    if (clearRequest != _lastClearRequest) {
      _lastClearRequest = clearRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.clear();
      });
    }

    final focusRequest = ref.watch(searchFocusRequestProvider);
    if (focusRequest != _lastFocusRequest) {
      _lastFocusRequest = focusRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        final textLength = _controller.text.length;
        _controller.selection = TextSelection.collapsed(offset: textLength);
      });
    }

    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isWidescreen) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Cinematic Background Image - Local Asset (Dark Mode only)
            if (isDark)
              Positioned.fill(
                child: Image.asset(
                  'assets/images/search_background.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            // Rich Architectural Stage Overlay (Vignette + Dark overlay - Dark Mode only)
            if (isDark)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: 0.7,
                    ), // Rich dark overlay
                  ),
                ),
              ),
            // Radial Vignette Overlay centered on search area (Dark Mode only)
            if (isDark)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.1,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.98),
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            // Left-to-right fade to blend backdrop image with the sidebar / background (Dark Mode only)
            if (isDark)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 320, // Wide fanning width to ease the transition
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.50),
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25, 0.55, 0.8, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            // Top-to-bottom edge vignette to mask out top/bottom image boundaries/black letterboxing (Dark Mode only)
            if (isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                          Colors.transparent,
                          Colors.transparent,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                          theme.scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.08, 0.2, 0.8, 0.92, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            // Focus Spotlight (Stage Lighting - Soft fanning semi-circle)
            Positioned(
              top:
                  76, // Anchored immediately below the search bar (24 top padding + 52 height)
              left: 0,
              right: 0,
              height: 250,
              child: ListenableBuilder(
                listenable: _focusNode,
                builder: (context, child) {
                  if (!_focusNode.hasFocus) return const SizedBox.shrink();
                  final spotlightColor = isDark
                      ? const Color(0xFF1E40AF)
                      : theme.colorScheme.primary;
                  return IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 900, // Broader fanning footprint
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment
                                .topCenter, // Fanning downward from the bottom edge of the search bar
                            radius: 1.3,
                            colors: [
                              spotlightColor.withValues(
                                alpha: isDark ? 0.35 : 0.22,
                              ), // Soft center source point
                              spotlightColor.withValues(
                                alpha: isDark ? 0.18 : 0.10,
                              ), // Smooth bleed
                              spotlightColor.withValues(
                                alpha: isDark ? 0.06 : 0.03,
                              ), // Gentle falloff
                              spotlightColor.withValues(
                                alpha: 0.0,
                              ), // Fade to transparent
                            ],
                            stops: const [0.0, 0.35, 0.70, 1.0],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Content layout in Column: Still header and Body directly below it
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  SearchHeaderBar(
                    textController: _controller,
                    searchFocusNode: _focusNode,
                    clearButtonFocusNode: _clearButtonFocusNode,
                    isCompact: false,
                    onShowFilters: _showSearchFilters,
                    activeFilterCount: ref.watch(searchProviderFiltersProvider).count,
                    isFilterLoading: _isLoadingProviderFilters,
                    onSubmitted: _submitSearch,
                    onChanged: (val) {
                      ref
                          .read(searchSuggestionControllerProvider.notifier)
                          .onQueryChanged(val);
                    },
                  ),
                  Expanded(
                    child: Padding(
                      // Fixed top padding below the top search bar (24px)
                      padding: const EdgeInsets.only(top: 24.0),
                      child: _buildBody(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile layout: existing AppBar
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final searchResultsState = ref.watch(searchPagedResultsProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Builder(
              builder: (context) {
                final activeFilters = ref.watch(searchProviderFiltersProvider);
                final isActive = activeFilters.isNotEmpty;
                return IconButton(
                  tooltip: appText(context, english: 'Filters', arabic: 'الفلاتر'),
                  onPressed: _isLoadingProviderFilters ? null : _showSearchFilters,
                  style: IconButton.styleFrom(
                    backgroundColor: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    foregroundColor: isActive
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                  icon: _isLoadingProviderFilters
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.tune_rounded, size: 20),
                            if (isActive)
                              Positioned(
                                right: -7,
                                top: -7,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onPrimary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${activeFilters.count}',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
        title: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 42,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final isSearching = searchResultsState.isLoading;

                Widget? suffix;
                if (isSearching) {
                  suffix = Padding(
                    padding: const EdgeInsets.all(12),
                    child: AppLoadingIndicator(
                      color: theme.colorScheme.primary,
                      constraints: BoxConstraints.tight(const Size(18, 18)),
                    ),
                  );
                } else if (value.text.isNotEmpty) {
                  suffix = IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _controller.clear();
                      ref
                          .read(searchSuggestionControllerProvider.notifier)
                          .clear();
                      ref.read(searchQueryProvider.notifier).set('');
                    },
                  );
                }

                return TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: false,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  textInputAction: TextInputAction.search,
                  onChanged: (val) {
                    ref
                        .read(searchSuggestionControllerProvider.notifier)
                        .onQueryChanged(val);
                  },
                  onSubmitted: _submitSearch,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 42,
                    ),
                    suffixIcon: suffix,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 42,
                      minHeight: 42,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = ref.watch(searchPagedResultsProvider);
    final suggestionState = ref.watch(searchSuggestionControllerProvider);
    final typedLongEnough = suggestionState.query.trim().length >= 2;
    final hasSuggestionContent =
        suggestionState.isLoading || suggestionState.suggestions.isNotEmpty;
    final showSuggestions = typedLongEnough && hasSuggestionContent;

    if (showSuggestions) {
      return _buildSuggestionsView(context, suggestionState);
    }

    final allResults = state.results.expand((entry) => entry.results).toList();
    if (allResults.isEmpty && state.isLoading) {
      return _buildLoadingSkeleton(context);
    }
    if (allResults.isEmpty) {
      return _buildEmptyState(context);
    }

    return RepaintBoundary(
      child: ListView.builder(
        controller: _resultsScrollController,
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: state.results.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.results.length) {
            return _buildLoadingMoreSkeleton(context);
          }
          final pResult = state.results[index];
          return SearchResultSection(
            key: ValueKey(pResult.providerId),
            providerName: pResult.providerName,
            providerId: pResult.providerId,
            results: pResult.results,
            firstCardFocusNode: index == 0 ? _firstResultFocusNode : null,
          );
        },
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    final isLarge = context.isTabletOrLarger;
    return GridView.builder(
      controller: _resultsScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      gridDelegate: isLarge
          ? const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.56,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            )
          : const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.56,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
      itemCount: isLarge ? 12 : 9,
      itemBuilder: (context, index) =>
          ShimmerPlaceholder(borderRadius: 12),
    );
  }

  Widget _buildLoadingMoreSkeleton(BuildContext context) {
    final spacing = context.isTabletOrLarger ? 16.0 : 10.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Row(
        children: List.generate(3, (index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: index == 2 ? 0 : spacing,
              ),
              child: AspectRatio(
                aspectRatio: 0.56,
                child: ShimmerPlaceholder(borderRadius: 12),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSuggestionsView(
    BuildContext context,
    SearchSuggestionState suggestionState,
  ) {
    if (suggestionState.isLoading) {
      return _buildLoadingSkeleton(context);
    }

    if (suggestionState.suggestions.isEmpty) {
      return Center(
        child: Text(
          appText(context, english: 'No results found', arabic: 'لم يتم العثور على نتائج'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestionState.suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestionState.suggestions[index];
        return BouncyEntryAnimation(
          delay: Duration(milliseconds: index * 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _SuggestionCard(
              suggestion: suggestion,
              focusNode: index == 0 ? _firstSuggestionFocusNode : null,
              isFirst: index == 0,
              onFocusSearch: () => _focusNode.requestFocus(),
              onTap: () => _submitSearch(suggestion),
              onFill: () => _fillSuggestion(suggestion),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);
    final isInputEmpty = _controller.text.trim().isEmpty;

    if (query.isEmpty || isInputEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            const SizedBox(height: LayoutConstants.spacingMd),
            Text(
              l10n.searchFavoriteContent,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pressSearchOrEnter,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final nativeFont = Theme.of(context).textTheme.bodyLarge?.fontFamily;
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final imageWidth = isWidescreen ? 320.0 : 200.0;

    // No search results found: display No Results Found text and the image grouped vertically
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            appText(context, english: 'No Results Found', arabic: 'لم يتم العثور على نتائج'),
            style: TextStyle(
              fontFamily: nativeFont,
              fontSize: 16.0,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Image.asset(
            'assets/images/no_results.png',
            fit: BoxFit.contain,
            width: imageWidth,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  final String suggestion;
  final VoidCallback onTap;
  final VoidCallback onFill;
  final FocusNode? focusNode;
  final bool isFirst;
  final VoidCallback onFocusSearch;

  const _SuggestionCard({
    required this.suggestion,
    required this.onTap,
    required this.onFill,
    required this.isFirst,
    required this.onFocusSearch,
    this.focusNode,
  });

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _isBodyHovered = false;
  bool _isButtonHovered = false;

  late final FocusNode _bodyNode;
  late final FocusNode _buttonNode;

  @override
  void initState() {
    super.initState();
    _bodyNode = widget.focusNode ?? FocusNode();
    _bodyNode.addListener(_onFocusChange);
    _buttonNode = FocusNode();
    _buttonNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _bodyNode.dispose();
    } else {
      if (_bodyNode.hasFocus) {
        _bodyNode.unfocus();
      }
      _bodyNode.removeListener(_onFocusChange);
    }
    _buttonNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nativeFont = theme.textTheme.bodyLarge?.fontFamily;

    final isBodyHighlighted = _isBodyHovered || _bodyNode.hasFocus;
    final isButtonHighlighted = _isButtonHovered || _buttonNode.hasFocus;
    final isAnyHighlighted = isBodyHighlighted || isButtonHighlighted;

    final baseBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : theme.colorScheme.outlineVariant;
    final highlightColor = isDark
        ? const Color(0xFF1F80E0)
        : theme.colorScheme.primary;

    final borderColor = isAnyHighlighted
        ? highlightColor.withValues(alpha: 0.85)
        : baseBorderColor;

    final cardBgColor = isDark
        ? Colors.black.withValues(alpha: 0.65)
        : theme.colorScheme.surfaceContainer;

    final bodyHighlightBg = isDark
        ? const Color(0xFF1F80E0).withValues(alpha: 0.25)
        : theme.colorScheme.primary.withValues(alpha: 0.12);

    final buttonHighlightBg = isDark
        ? const Color(0xFF1F80E0).withValues(alpha: 0.35)
        : theme.colorScheme.primary.withValues(alpha: 0.18);

    final iconColor = isDark
        ? Colors.white70
        : theme.colorScheme.onSurfaceVariant;

    final textColor = isDark ? Colors.white : theme.colorScheme.onSurface;

    final buttonIconColor = isDark
        ? Colors.white54
        : theme.colorScheme.onSurfaceVariant;

    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : theme.colorScheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: cardBgColor, // Theme-aware card background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: isAnyHighlighted
            ? [
                BoxShadow(
                  color: highlightColor.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Main Body Focus (Search text)
          Expanded(
            child: Focus(
              focusNode: _bodyNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.isFirst) {
                    widget.onFocusSearch();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _buttonNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    widget.onTap();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: MouseRegion(
                onEnter: (_) => setState(() => _isBodyHovered = true),
                onExit: (_) => setState(() => _isBodyHovered = false),
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isBodyHighlighted
                          ? bodyHighlightBg
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(11),
                        bottomLeft: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: isBodyHighlighted ? highlightColor : iconColor,
                          size: 20,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            widget.suggestion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: nativeFont,
                              color: textColor,
                              fontSize: 16.0,
                              fontWeight: isBodyHighlighted
                                  ? FontWeight.w500
                                  : FontWeight.w400,
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
          // Vertical divider line between text block and arrow button
          Container(width: 1.0, height: 24.0, color: dividerColor),
          // Fill Button Focus (Arrow icon button)
          Focus(
            focusNode: _buttonNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                    widget.isFirst) {
                  widget.onFocusSearch();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _bodyNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  widget.onFill();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: MouseRegion(
              onEnter: (_) => setState(() => _isButtonHovered = true),
              onExit: (_) => setState(() => _isButtonHovered = false),
              child: GestureDetector(
                onTap: widget.onFill,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isButtonHighlighted
                        ? buttonHighlightBg
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(11),
                      bottomRight: Radius.circular(11),
                    ),
                  ),
                  child: Icon(
                    Icons.north_west_rounded,
                    color: isButtonHighlighted
                        ? highlightColor
                        : buttonIconColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
