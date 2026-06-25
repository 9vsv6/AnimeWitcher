import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../search_provider.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/cards_wrapper.dart';

class WaveformEqualizer extends StatefulWidget {
  final bool isActive;
  const WaveformEqualizer({super.key, required this.isActive});

  @override
  State<WaveformEqualizer> createState() => _WaveformEqualizerState();
}

class _WaveformEqualizerState extends State<WaveformEqualizer>
    with TickerProviderStateMixin {
  late final AnimationController _anim1;
  late final AnimationController _anim2;
  late final AnimationController _anim3;

  @override
  void initState() {
    super.initState();
    _anim1 = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat(reverse: true);
    _anim2 = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    )..repeat(reverse: true);
    _anim3 = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) => Container(
          width: 2,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(0.5),
          ),
        )),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildBar(_anim1, 4, 12),
        _buildBar(_anim2, 6, 14),
        _buildBar(_anim3, 3, 10),
      ],
    );
  }

  Widget _buildBar(Animation<double> anim, double minH, double maxH) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final h = minH + (maxH - minH) * anim.value;
        return Container(
          width: 2,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(0.5),
          ),
        );
      },
    );
  }
}

/// A custom Scope Pill Switcher with animated sliding fill between states.
class SearchScopeSwitcher extends StatefulWidget {
  final SearchFilter value;
  final FocusNode moviesShowsFocusNode;
  final FocusNode liveTvFocusNode;
  final ValueChanged<SearchFilter> onChanged;

  const SearchScopeSwitcher({
    super.key,
    required this.value,
    required this.moviesShowsFocusNode,
    required this.liveTvFocusNode,
    required this.onChanged,
  });

  @override
  State<SearchScopeSwitcher> createState() => _SearchScopeSwitcherState();
}

class _SearchScopeSwitcherState extends State<SearchScopeSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = widget.value == SearchFilter.live;
    final nativeFont = theme.textTheme.bodyLarge?.fontFamily;

    return Container(
      width: 280,
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Stack(
        children: [
          // Sliding indicator pill
          AnimatedAlign(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack, // Bouncy overshoot slide
            alignment: isLive ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8), // Premium Navy Blue indicator
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                      blurRadius: 5,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Buttons
          Row(
            children: [
              Expanded(
                child: CardsWrapper(
                  focusNode: widget.moviesShowsFocusNode,
                  onTap: () => widget.onChanged(SearchFilter.content),
                  borderRadius: BorderRadius.circular(18),
                  scaleFactor: 1.0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => widget.onChanged(SearchFilter.content),
                    child: Container(
                      height: 34,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_library_rounded,
                            size: 14,
                            color: !isLive
                                ? Colors.white
                                : Colors.white60,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Movies & Shows',
                            style: TextStyle(
                              fontFamily: nativeFont,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w400,
                              color: !isLive
                                  ? Colors.white
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CardsWrapper(
                  focusNode: widget.liveTvFocusNode,
                  onTap: () => widget.onChanged(SearchFilter.live),
                  borderRadius: BorderRadius.circular(18),
                  scaleFactor: 1.0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => widget.onChanged(SearchFilter.live),
                    child: Container(
                      height: 34,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          WaveformEqualizer(isActive: isLive),
                          const SizedBox(width: 8),
                          Text(
                            'Live TV',
                            style: TextStyle(
                              fontFamily: nativeFont,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w400,
                              color: isLive
                                  ? Colors.white
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Redesigned static widescreen/desktop search control bar.
class SearchHeaderBar extends ConsumerStatefulWidget {
  final TextEditingController textController;
  final FocusNode searchFocusNode;
  final FocusNode clearButtonFocusNode;
  final FocusNode moviesShowsFocusNode;
  final FocusNode liveTvFocusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final bool isCompact;

  const SearchHeaderBar({
    super.key,
    required this.textController,
    required this.searchFocusNode,
    required this.clearButtonFocusNode,
    required this.moviesShowsFocusNode,
    required this.liveTvFocusNode,
    required this.onSubmitted,
    required this.onChanged,
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
    final filter = ref.watch(searchFilterProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final isCompact = widget.isCompact;

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
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
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
                          constraints: BoxConstraints.tight(const Size(20, 20)),
                        ),
                      ),
                    );
                  } else if (value.text.isNotEmpty) {
                    suffix = AnimatedBuilder(
                      animation: widget.clearButtonFocusNode,
                      builder: (context, child) {
                        final isFocused = widget.clearButtonFocusNode.hasFocus;
                        return IconButton(
                          focusNode: widget.clearButtonFocusNode,
                          icon: Icon(
                            Icons.clear_rounded,
                            size: 18,
                            color: isFocused ? const Color(0xFF1F80E0) : Colors.white70,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: isFocused
                                ? const Color(0xFF1F80E0).withValues(alpha: 0.2)
                                : Colors.transparent,
                          ),
                          onPressed: () {
                            widget.textController.clear();
                            ref
                                .read(searchSuggestionControllerProvider.notifier)
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
                    : SearchScopeSwitcher(
                        value: filter,
                        moviesShowsFocusNode: widget.moviesShowsFocusNode,
                        liveTvFocusNode: widget.liveTvFocusNode,
                        onChanged: (val) {
                          ref.read(searchFilterProvider.notifier).set(val);
                          // Sync current text to search query instantly on scope switch
                          final text = widget.textController.text.trim();
                          ref.read(searchQueryProvider.notifier).set(text);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
