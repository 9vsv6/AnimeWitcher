import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/notification_service.dart';
import '../../../settings/presentation/player_settings_provider.dart';
import '../player_controller.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../shared/widgets/custom_widgets.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../subtitle_search_provider.dart';
import '../../domain/entity/subtitle_model.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'hotstar_player_style.dart';
import 'subtitle_sync_dialog.dart';
import 'subtitle_appearance_dialog.dart';
import 'player_ltr.dart';

import 'package:skystream/core/utils/localized_text.dart';
class PlayerBottomSheets {
  static void showSpeedSelection({
    required BuildContext context,
    required double currentSpeed,
    required double maxSpeed,
    required void Function(double) onSpeedSelected,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final sliderMax = maxSpeed < 3.0 ? maxSpeed : 3.0;
    final speeds = [
      0.25,
      1.0,
      1.25,
      1.5,
      2.0,
    ].where((speed) => speed <= sliderMax + 0.001).toList();
    final sliderDivisions = ((sliderMax - 0.25) / 0.05).round();
    double selectedSpeed = currentSpeed.clamp(0.25, sliderMax).toDouble();

    showPlayerDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            void setSpeed(double value) {
              final next = value.clamp(0.25, sliderMax).toDouble();
              setState(() => selectedSpeed = next);
              onSpeedSelected(next);
            }

            final size = MediaQuery.sizeOf(context);
            final isCompact = size.shortestSide < 600;
            final compactWidth = (size.width - 32)
                .clamp(280.0, 360.0)
                .toDouble();
            final maxWidth = size.width >= 900 ? 520.0 : compactWidth;
            final compactHeight = (size.height * (isCompact ? 0.58 : 0.68))
                .clamp(isCompact ? 260.0 : 340.0, isCompact ? 340.0 : 420.0)
                .toDouble();

            return Dialog(
              backgroundColor: HotstarPlayerStyle.background,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 16,
                vertical: isCompact ? 16 : 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isCompact ? 14 : 20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: compactHeight,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    brightness: Brightness.dark,
                    colorScheme: const ColorScheme.dark(
                      primary: HotstarPlayerStyle.accent,
                      surface: HotstarPlayerStyle.background,
                      onSurface: HotstarPlayerStyle.primaryText,
                    ),
                    chipTheme: ChipThemeData(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      selectedColor: HotstarPlayerStyle.accent.withValues(
                        alpha: 0.22,
                      ),
                      disabledColor: Colors.white.withValues(alpha: 0.04),
                      labelStyle: const TextStyle(
                        color: HotstarPlayerStyle.secondaryText,
                      ),
                      secondaryLabelStyle: const TextStyle(
                        color: HotstarPlayerStyle.primaryText,
                      ),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompact ? 16 : 24,
                      isCompact ? 12 : 18,
                      isCompact ? 16 : 24,
                      isCompact ? 16 : 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.playbackSpeed,
                                style: TextStyle(
                                  color: HotstarPlayerStyle.primaryText,
                                  fontSize: isCompact ? 15 : 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                              color: HotstarPlayerStyle.secondaryText,
                              autofocus: true,
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 10 : 20),
                        Text(
                          _formatSpeed(selectedSpeed),
                          style: TextStyle(
                            color: HotstarPlayerStyle.primaryText,
                            fontSize: isCompact ? 23 : 28,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: isCompact ? 14 : 24),
                        Row(
                          children: [
                            _speedStepButton(
                              icon: Icons.remove,
                              onPressed: () => setSpeed(selectedSpeed - 0.1),
                              compact: isCompact,
                            ),
                            SizedBox(width: isCompact ? 10 : 18),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: isCompact ? 10 : 18,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                  thumbColor: Colors.white,
                                  overlayColor: HotstarPlayerStyle.accent
                                      .withValues(alpha: 0.12),
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                  trackShape:
                                      const RoundedRectSliderTrackShape(),
                                ),
                                child: CustomSlider(
                                  value: selectedSpeed,
                                  min: 0.25,
                                  max: sliderMax,
                                  step: 0.05,
                                  divisions: sliderDivisions > 0
                                      ? sliderDivisions
                                      : null,
                                  // Pure visual indicator on TV — the −/+
                                  // buttons adjust it. Keeping it out of focus
                                  // traversal means D-pad Up/Down isn't trapped
                                  // and moves between the buttons and presets.
                                  focusable: false,
                                  onChanged: setSpeed,
                                ),
                              ),
                            ),
                            SizedBox(width: isCompact ? 10 : 18),
                            _speedStepButton(
                              icon: Icons.add,
                              onPressed: () => setSpeed(selectedSpeed + 0.1),
                              compact: isCompact,
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 14 : 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: isCompact ? 7 : 10,
                          runSpacing: isCompact ? 7 : 10,
                          children: speeds.map((speed) {
                            final isSelected =
                                (selectedSpeed - speed).abs() < 0.01;
                            return _SpeedPresetChip(
                              speed: speed,
                              isSelected: isSelected,
                              isCompact: isCompact,
                              onTap: () => setSpeed(speed),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _formatSpeed(double speed) {
    return '${speed.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '')}x';
  }

  static Widget _speedStepButton({
    required IconData icon,
    required VoidCallback? onPressed,
    bool compact = false,
  }) {
    return _SpeedStepButton(icon: icon, onPressed: onPressed, compact: compact);
  }

  static Widget _fullscreenShell({
    required BuildContext context,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Dialog.fullscreen(
      backgroundColor: HotstarPlayerStyle.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 18, 48, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppleLiquidGlassBackButton(
                    size: 48,
                    foregroundColor: HotstarPlayerStyle.secondaryText,
                    fallbackColor: Colors.transparent,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: HotstarPlayerStyle.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing else const SizedBox(width: 48),
                ],
              ),
              const Divider(color: HotstarPlayerStyle.divider, height: 28),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  /// Public entry point for the subtitle-options dialog (sync / styles /
  /// search / load external). Retained for callers that still want the legacy
  /// dialog; the sources side panel now inlines these controls instead.
  static void showSubtitleOptions(BuildContext context) =>
      _showSubtitleOptions(context);

  /// Public entry point for the online subtitle search dialog. The sources
  /// side panel's "Search online" row opens this directly (pending its own
  /// redesign).
  static void showSubtitleSearch(BuildContext context) =>
      _showSubtitleSearch(context);

  static void _showSubtitleOptions(BuildContext context) {
    final parentContext = context;
    showPlayerDialog<void>(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (dialogContext, ref, child) {
            final supportsExternalSubtitleLoading = ref.watch(
              playerControllerProvider.select(
                (s) => s.supportsExternalSubtitleLoading,
              ),
            );
            final l10n = AppLocalizations.of(dialogContext)!;

            Widget option({
              required IconData icon,
              required String label,
              required VoidCallback? onTap,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: onTap == null
                            ? HotstarPlayerStyle.mutedText
                            : HotstarPlayerStyle.secondaryText,
                        size: 24,
                      ),
                      const SizedBox(width: 22),
                      Text(
                        label,
                        style: TextStyle(
                          color: onTap == null
                              ? HotstarPlayerStyle.mutedText
                              : HotstarPlayerStyle.primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Dialog.fullscreen(
              backgroundColor: HotstarPlayerStyle.background,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 18, 48, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.subtitleOptions,
                              style: const TextStyle(
                                color: HotstarPlayerStyle.primaryText,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                            color: Colors.white,
                            iconSize: 36,
                            tooltip: l10n.cancel,
                          ),
                        ],
                      ),
                      const Divider(
                        color: HotstarPlayerStyle.divider,
                        height: 28,
                      ),
                      if (!supportsExternalSubtitleLoading)
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.orange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.hlsSubtitleWarning,
                                  style: TextStyle(
                                    color: Colors.orange.shade200,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      option(
                        icon: Icons.file_open_outlined,
                        label: l10n.loadFromDevice,
                        onTap: !supportsExternalSubtitleLoading
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .loadExternalSubtitleFile();
                              },
                      ),
                      option(
                        icon: Icons.sync,
                        label: l10n.syncDelay,
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (parentContext.mounted) {
                              _showSubtitleSync(parentContext);
                            }
                          });
                        },
                      ),
                      option(
                        icon: Icons.style,
                        label: l10n.styleSettings,
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (parentContext.mounted) {
                              _showSubtitleStyles(parentContext);
                            }
                          });
                        },
                      ),
                      option(
                        icon: Icons.search,
                        label: l10n.searchOnline,
                        onTap: !supportsExternalSubtitleLoading
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (parentContext.mounted) {
                                    _showSubtitleSearch(parentContext);
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showSubtitleSync(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Consumer(
          builder: (context, ref, child) {
            final controller = ref.read(playerControllerProvider.notifier);
            final wasPlaying = controller.isPlaying;
            return SubtitleSyncDialog(wasPlaying: wasPlaying);
          },
        ),
      ),
    );
  }

  static void _showSubtitleStyles(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Consumer(
          builder: (context, ref, child) {
            final controller = ref.read(playerControllerProvider.notifier);
            final wasPlaying = controller.isPlaying;
            return SubtitleAppearanceDialog(wasPlaying: wasPlaying);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  static void _showSubtitleSearch(BuildContext context) {
    final parentContext = context;
    final TextEditingController queryController = TextEditingController();

    final scrollController = ScrollController();

    showPlayerDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final l10n = AppLocalizations.of(ctx)!;
        final dialogSize = MediaQuery.sizeOf(ctx);
        final isCompact = dialogSize.shortestSide < 600;
        final horizontalPadding = isCompact ? 20.0 : 48.0;
        return _fullscreenShell(
          context: ctx,
          title: l10n.searchOnline,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  12 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Consumer(
                  builder: (context, ref, child) {
                    final playerState = ref.read(playerControllerProvider);
                    final selectedLang = ref.read(subtitleLanguageProvider);

                    // Initial population and auto-search
                    if (queryController.text.isEmpty &&
                        playerState.playerTitle.isNotEmpty) {
                      queryController.text = playerState.playerTitle;
                      Future.microtask(() {
                        if (ref.read(subtitleSearchProvider) is! AsyncLoading) {
                          ref
                              .read(subtitleSearchProvider.notifier)
                              .search(
                                query: queryController.text,
                                imdbId: playerState.imdbId,
                                tmdbId: playerState.tmdbId,
                                language: selectedLang,
                              );
                        }
                      });
                    }

                    return TextField(
                      controller: queryController,
                      autofocus: true,
                      style: const TextStyle(
                        color: HotstarPlayerStyle.primaryText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.searchSubtitleNameHint,
                        hintStyle: const TextStyle(
                          color: HotstarPlayerStyle.mutedText,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: HotstarPlayerStyle.secondaryText,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (queryController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  queryController.clear();
                                  final playerState = ref.read(
                                    playerControllerProvider,
                                  );
                                  final selectedLang = ref.read(
                                    subtitleLanguageProvider,
                                  );
                                  ref
                                      .read(subtitleSearchProvider.notifier)
                                      .search(
                                        query: "",
                                        imdbId: playerState.imdbId,
                                        tmdbId: playerState.tmdbId,
                                        language: selectedLang,
                                      );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () {
                                final playerState = ref.read(
                                  playerControllerProvider,
                                );
                                final selectedLang = ref.read(
                                  subtitleLanguageProvider,
                                );
                                ref
                                    .read(subtitleSearchProvider.notifier)
                                    .search(
                                      query: queryController.text,
                                      imdbId: playerState.imdbId,
                                      tmdbId: playerState.tmdbId,
                                      language: selectedLang,
                                    );
                              },
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (val) {
                        final playerState = ref.read(playerControllerProvider);
                        final selectedLang = ref.read(subtitleLanguageProvider);
                        ref
                            .read(subtitleSearchProvider.notifier)
                            .search(
                              query: val,
                              imdbId: playerState.imdbId,
                              tmdbId: playerState.tmdbId,
                              language: selectedLang,
                            );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Language Selector (Targeted Consumer)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Consumer(
                  builder: (context, ref, child) {
                    final selectedLang = ref.watch(subtitleLanguageProvider);
                    return DesktopScrollWrapper(
                      controller: scrollController,
                      isCompact: true,
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          scrollDirection: Axis.horizontal,
                          itemCount: subtitleLanguages.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final entry = subtitleLanguages.entries.elementAt(
                              index,
                            );
                            final isSelected = entry.value == selectedLang;
                            return ChoiceChip(
                              label: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white
                                      : HotstarPlayerStyle.secondaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  ref
                                      .read(subtitleLanguageProvider.notifier)
                                      .set(entry.value);
                                  final playerState = ref.read(
                                    playerControllerProvider,
                                  );
                                  ref
                                      .read(subtitleSearchProvider.notifier)
                                      .search(
                                        query: queryController.text,
                                        imdbId: playerState.imdbId,
                                        tmdbId: playerState.tmdbId,
                                        language: entry.value,
                                      );
                                }
                              },
                              selectedColor: HotstarPlayerStyle.accent,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.06,
                              ),
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final searchState = ref.watch(subtitleSearchProvider);
                    return searchState.when(
                      data: (results) {
                        if (results == null) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.subtitles_rounded,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.enterSearchSubtitlePrompt,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (results.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.subtitles_off_rounded,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.noSubtitleResults,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: results.length,
                          separatorBuilder: (_, _) => Divider(
                            color: theme.dividerColor.withValues(alpha: 0.05),
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                          ),
                          itemBuilder: (context, index) {
                            final sub = results[index];
                            return _buildSubtitleCard(
                              context: context,
                              sub: sub,
                              onTap: () async {
                                ref
                                    .read(notificationServiceProvider)
                                    .showInfo(l10n.downloadingApplyingSubtitle);

                                final path = await ref
                                    .read(subtitleSearchProvider.notifier)
                                    .downloadAndPrepare(sub);

                                if (path != null) {
                                  unawaited(
                                    ref
                                        .read(playerControllerProvider.notifier)
                                        .loadExternalSubtitleFile(
                                          filePath: path,
                                        ),
                                  );
                                  if (context.mounted) Navigator.pop(ctx);
                                } else {
                                  if (context.mounted) {
                                    ref
                                        .read(notificationServiceProvider)
                                        .showError(
                                          l10n.failedToDownloadSubtitle,
                                        );
                                  }
                                }
                              },
                            );
                          },
                        );
                      },
                      loading: () => _buildShimmerLoading(context),
                      error: (err, stack) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            l10n.failedToLoadSubtitles,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildShimmerLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Shimmer.fromColors(
      baseColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
      highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 200,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 18,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSubtitleCard({
    required BuildContext context,
    required OnlineSubtitle sub,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final sourceColor = sub.source.toLowerCase().contains("subsource")
        ? Colors.blueAccent
        : (sub.source.toLowerCase().contains("opensubtitles")
              ? Colors.orangeAccent
              : theme.colorScheme.primary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sub.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HotstarPlayerStyle.primaryText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: sourceColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    sub.language.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: sourceColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  sub.source,
                  style: const TextStyle(
                    color: HotstarPlayerStyle.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (sub.isHearingImpaired)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.hearing,
                      size: 16,
                      color: theme.hintColor.withValues(alpha: 0.5),
                    ),
                  ),
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 20,
                  color: theme.hintColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedPresetChip extends StatefulWidget {
  final double speed;
  final bool isSelected;
  final bool isCompact;
  final VoidCallback onTap;

  const _SpeedPresetChip({
    required this.speed,
    required this.isSelected,
    required this.isCompact,
    required this.onTap,
  });

  @override
  State<_SpeedPresetChip> createState() => _SpeedPresetChipState();
}

class _SpeedPresetChipState extends State<_SpeedPresetChip> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final showHighlight = _isHovered || _isFocused;
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: HotstarPlayerStyle.fastMotionDuration,
            width: widget.isCompact ? 76 : 104,
            padding: EdgeInsets.symmetric(vertical: widget.isCompact ? 10 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? HotstarPlayerStyle.accent.withValues(alpha: 0.22)
                  : (showHighlight
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused
                    ? HotstarPlayerStyle.accent
                    : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: HotstarPlayerStyle.accent.withValues(
                          alpha: 0.25,
                        ),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              PlayerBottomSheets._formatSpeed(widget.speed),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: widget.isSelected
                    ? HotstarPlayerStyle.primaryText
                    : HotstarPlayerStyle.secondaryText,
                fontSize: widget.isCompact ? 13 : 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedStepButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool compact;

  const _SpeedStepButton({
    required this.icon,
    required this.onPressed,
    required this.compact,
  });

  @override
  State<_SpeedStepButton> createState() => _SpeedStepButtonState();
}

class _SpeedStepButtonState extends State<_SpeedStepButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      child: AnimatedScale(
        scale: _isFocused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: IconButton(
          onPressed: widget.onPressed,
          icon: Icon(widget.icon, size: widget.compact ? 20 : 24),
          color: HotstarPlayerStyle.primaryText,
          style: IconButton.styleFrom(
            backgroundColor: _isFocused
                ? HotstarPlayerStyle.accent.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            fixedSize: Size(widget.compact ? 42 : 56, widget.compact ? 42 : 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.compact ? 10 : 14),
              side: BorderSide(
                color: _isFocused
                    ? HotstarPlayerStyle.accent
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
