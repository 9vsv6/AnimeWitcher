import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter, FontFeature;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';

import '../player_controller.dart';
import '../../../details/presentation/playback_launcher.dart';
import 'hotstar_player_style.dart';
import 'player_utils.dart';

import 'package:skystream/core/utils/localized_text.dart';
import 'package:skystream/core/utils/episode_label.dart';
const List<Shadow> _kGlassTextShadow = [
  Shadow(color: Colors.black54, offset: Offset(0, 1.5), blurRadius: 3.0),
];

/// A reusable right-anchored drawer shell for the player.
///
/// Layout is a pure [Row] — an [Expanded] scrim on the left, the drawer surface
/// on the right — so there is no inner [Stack] and no magic-offset [Positioned].
/// The parent mounts it via a single `Positioned.fill` in the one overlay layer
/// that already sits over the video.
///
/// Visibility animates the drawer width (0 → [panel width]); the content is held
/// at full width by an [OverflowBox] pinned to the right edge, so it slides
/// cleanly from the right in both directions while staying mounted. Mounting
/// persists so the content can drive focus on open. While closed it ignores
/// pointers and is excluded from focus, so taps and D-pad fall through to the
/// chrome below.
class PlayerSidePanel extends StatelessWidget {
  final bool isVisible;
  final bool isTv;
  final VoidCallback onDismiss;
  final Widget child;

  const PlayerSidePanel({
    super.key,
    required this.isVisible,
    required this.onDismiss,
    required this.child,
    this.isTv = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.shortestSide < 600;
    final panelWidth = isCompact
        ? (size.width * 0.8).clamp(260.0, 380.0)
        : 350.0;

    return IgnorePointer(
      ignoring: !isVisible,
      child: ExcludeFocus(
        excluding: !isVisible,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scrim — tap (or click) anywhere outside the drawer to dismiss.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: AnimatedContainer(
                  duration: HotstarPlayerStyle.controlFadeDuration,
                  color: Colors.black.withValues(alpha: isVisible ? 0.45 : 0.0),
                ),
              ),
            ),
            // The drawer — width animates for a slide-from-right reveal while
            // the content is pinned to full width by the OverflowBox.
            ClipRect(
              child: AnimatedContainer(
                duration: HotstarPlayerStyle.panelMotionDuration,
                curve: Curves.fastOutSlowIn,
                width: isVisible ? panelWidth : 0,
                child: OverflowBox(
                  alignment: Alignment.centerRight,
                  minWidth: panelWidth,
                  maxWidth: panelWidth,
                  child: _PanelSurface(
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: child,
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

/// Dark surface for the drawer: solid scrim-coloured background + a soft shadow
/// down the left edge to lift it off the video. No blur (keeps it cheap and
/// identical across platforms).
class _PanelSurface extends StatelessWidget {
  final Widget child;

  const _PanelSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 50,
            spreadRadius: 0,
            offset: const Offset(-8, 0),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. LAYERED TRANSLUCENT OBSIDIAN/CHARCOAL BLACK BASE WITH BACKDROP BLUR
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22.0, sigmaY: 22.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(
                    0xA6060608,
                  ), // Frosted glass obsidian tint (65% opacity)
                ),
              ),
            ),
          ),
          // 2. SOFT AMBIENT GLOSS
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(
                        alpha: 0.04,
                      ), // soft mirror-like reflection
                      Colors.white.withValues(alpha: 0.01),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 3. REALISTIC LIGHT DIFFUSION (Soft ambient lighting texture)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.7),
                    radius: 1.5,
                    colors: [
                      Colors.white.withValues(alpha: 0.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 4. FRESNEL EDGE HIGHLIGHTS WITH SOFT GRADIENT BLENDING (Left and Right)
          Positioned.fill(
            child: IgnorePointer(
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.15, 0.85, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 5. INNER RIM HIGHLIGHT WITH SOFT GRADIENT BLENDING (Left and Right)
          Positioned.fill(
            child: IgnorePointer(
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.20, 0.80, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.04),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Main content
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Content for the episodes side panel — the same right-drawer shell and row
/// styling as the sources/tracks panel, but a single vertical list (episodes
/// grouped under `Season N` subheaders). Pure Up/Down D-pad; the current episode
/// is the focus anchor and is centred on open. Selecting an episode loads it and
/// closes the pane. No dropdown, no scroll-jump animation.
class PlayerEpisodesPanel extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool isTv;
  final VoidCallback onClose;

  const PlayerEpisodesPanel({
    super.key,
    required this.item,
    required this.onClose,
    this.isTv = false,
  });

  @override
  ConsumerState<PlayerEpisodesPanel> createState() =>
      _PlayerEpisodesPanelState();
}

class _PlayerEpisodesPanelState extends ConsumerState<PlayerEpisodesPanel> {
  final FocusNode _anchorNode = FocusNode(debugLabel: 'episodes_panel_anchor');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(playerControllerProvider).showEpisodeList) {
        _focusAnchor();
      }
    });
  }

  @override
  void dispose() {
    _anchorNode.dispose();
    super.dispose();
  }

  void _focusAnchor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(playerControllerProvider).showEpisodeList) {
        return;
      }
      final ctx = _anchorNode.context;
      if (ctx != null) {
        _anchorNode.requestFocus();
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Restore focus to the current episode whenever the pane opens.
    ref.listen(playerControllerProvider.select((s) => s.showEpisodeList), (
      prev,
      next,
    ) {
      if (next == true && prev != true && mounted) _focusAnchor();
    });

    final l10n = AppLocalizations.of(context)!;
    final currentUrl =
        ref.watch(
          playerControllerProvider.select((s) => s.currentStream?.url),
        ) ??
        ref.read(playerControllerProvider.notifier).currentEpisodeUrl;
    var episodes = widget.item.episodes ?? const <Episode>[];
    final currentEpisode = episodes.firstWhereOrNull(
      (e) => e.url == currentUrl,
    );
    final isSeries =
        widget.item.contentType == MultimediaContentType.series ||
        widget.item.contentType == MultimediaContentType.anime;
    if (isSeries &&
        currentEpisode != null &&
        currentEpisode.dubStatus != DubStatus.none) {
      episodes = episodes
          .where((e) => e.dubStatus == currentEpisode.dubStatus)
          .toList();
    }
    final historyRepo = ref.read(historyRepositoryProvider);

    final seasons = episodes.map((e) => e.season).toSet().toList()..sort();
    final multiSeason = seasons.length > 1;

    final rows = <Widget>[];
    var anchorAssigned = false;
    for (final season in seasons) {
      final seasonEps = episodes.where((e) => e.season == season).toList();
      if (multiSeason) {
        rows.add(_PanelSubheader(title: l10n.seasonWithNumber(season)));
      }
      for (final ep in seasonEps) {
        final isCurrent = ep.url == currentUrl;
        final isAnchor = isCurrent && !anchorAssigned;
        if (isAnchor) anchorAssigned = true;
        final pos = historyRepo.getEpisodePosition(
          ep.url,
          mainUrl: widget.item.url,
          season: ep.season,
          episode: ep.episode,
        );
        final dur = historyRepo.getEpisodeDuration(
          ep.url,
          mainUrl: widget.item.url,
          season: ep.season,
          episode: ep.episode,
        );
        rows.add(
          _EpisodeRow(
            episode: ep,
            isCurrent: isCurrent,
            progress: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0,
            isTv: widget.isTv,
            focusNode: isAnchor ? _anchorNode : null,
            onTap: () async {
              widget.onClose();
              final selected = await ref
                  .read(playbackLauncherProvider)
                  .chooseSourceForItem(
                    context,
                    widget.item,
                    ep.url,
                    episode: ep,
                  );
              if (selected == null || !mounted) return;
              await ref
                  .read(playerControllerProvider.notifier)
                  .loadEpisode(ep, selectedSource: selected);
            },
          ),
        );
      }
    }
    // If nothing is currently playing from this list, anchor the first row.
    if (!anchorAssigned && rows.isNotEmpty) {
      final firstEpIndex = rows.indexWhere((w) => w is _EpisodeRow);
      if (firstEpIndex != -1) {
        final r = rows[firstEpIndex] as _EpisodeRow;
        rows[firstEpIndex] = _EpisodeRow(
          episode: r.episode,
          isCurrent: r.isCurrent,
          progress: r.progress,
          isTv: r.isTv,
          focusNode: _anchorNode,
          onTap: r.onTap,
        );
      }
    }

    return SafeArea(
      left: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.video_library_outlined,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.episodes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HotstarPlayerStyle.primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      shadows: _kGlassTextShadow,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  icon: const Icon(Icons.close_rounded),
                  color: HotstarPlayerStyle.secondaryText,
                ),
              ],
            ),
          ),
          const Divider(color: HotstarPlayerStyle.divider, height: 1),
          Expanded(
            child: episodes.isEmpty
                ? _EmptyHint(text: l10n.noEpisodesFound)
                : _OptionList(children: rows),
          ),
        ],
      ),
    );
  }
}

/// A single episode row: focusable (same accent border/glow cue, no scale),
/// shows "S·E", the title, a slim progress bar, and a play marker for the
/// episode that's currently active.
class _EpisodeRow extends StatefulWidget {
  final Episode episode;
  final bool isCurrent;
  final double progress;
  final bool isTv;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _EpisodeRow({
    required this.episode,
    required this.isCurrent,
    required this.progress,
    required this.isTv,
    required this.onTap,
    this.focusNode,
  });

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final showHighlight = _focused || _hovered;
    final ring = _focused && widget.isTv;
    const accent = HotstarPlayerStyle.accent;
    return Semantics(
      button: true,
      selected: widget.isCurrent,
      label: ep.name,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: HotstarPlayerStyle.fastMotionDuration,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: _panelRowDecoration(
                focusedOnTv: ring,
                selected: widget.isCurrent,
                hovered: showHighlight,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _EpisodeThumbnail(
                    posterUrl: ep.posterUrl,
                    isCurrent: widget.isCurrent,
                    progress: widget.progress,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              formatEpisodeLabel(
                                episode: ep.episode,
                                isArabic: Localizations.localeOf(context)
                                        .languageCode ==
                                    'ar',
                              ),
                              style: TextStyle(
                                color: widget.isCurrent
                                    ? accent
                                    : HotstarPlayerStyle.mutedText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                shadows: _kGlassTextShadow,
                              ),
                            ),
                            if (ep.dubStatus != DubStatus.none) ...[
                              const SizedBox(width: 6),
                              _DubBadge(
                                dubStatus: ep.dubStatus,
                                isCurrent: widget.isCurrent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ep.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.isCurrent
                                ? HotstarPlayerStyle.primaryText
                                : HotstarPlayerStyle.secondaryText,
                            fontSize: 14,
                            fontWeight: widget.isCurrent
                                ? FontWeight.w800
                                : FontWeight.w600,
                            shadows: _kGlassTextShadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Claymorphism badge showing SUB or DUB next to the episode number.
/// Soft inner shadow + subtle highlight simulates a pressed-clay look on the
/// frosted-glass panel surface. Colour-coded: blue-ish for SUB, warm amber for DUB.
class _DubBadge extends StatelessWidget {
  final DubStatus dubStatus;
  final bool isCurrent;

  const _DubBadge({required this.dubStatus, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final isSub = dubStatus == DubStatus.subbed;
    final label = isSub
        ? AppLocalizations.of(context)!.sub.toUpperCase()
        : AppLocalizations.of(context)!.dub.toUpperCase();
    // SUB = cool blue tint, DUB = warm amber tint.
    final tint = isSub ? const Color(0xFF64B5F6) : const Color(0xFFFFB74D);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        // Claymorphism: translucent tinted fill.
        color: tint.withValues(alpha: isCurrent ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(4),
        // Soft outer shadow (depth) + inner highlight (clay press).
        boxShadow: [
          // Outer shadow — subtle depth lift.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          // Inner highlight — top-left light catch.
          BoxShadow(
            color: tint.withValues(alpha: 0.18),
            offset: const Offset(0, -0.5),
            blurRadius: 1,
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: tint.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isCurrent ? tint : tint.withValues(alpha: 0.85),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          height: 1.2,
          shadows: _kGlassTextShadow,
        ),
      ),
    );
  }
}

/// Episode thumbnail: poster image (or a placeholder), a play overlay for the
/// current episode, and a watch-progress bar along the bottom. The small inner
/// [Stack] is a leaf decoration on the image — not chrome layout.
class _EpisodeThumbnail extends StatelessWidget {
  final String? posterUrl;
  final bool isCurrent;
  final double progress;

  const _EpisodeThumbnail({
    required this.posterUrl,
    required this.isCurrent,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    final hasProgress = progress > 0.02 && progress < 0.98;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 104,
        height: 58,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPoster)
              Image.network(
                posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _ThumbPlaceholder(),
              )
            else
              const _ThumbPlaceholder(),
            if (isCurrent)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                child: const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            if (hasProgress)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    HotstarPlayerStyle.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x14FFFFFF),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: HotstarPlayerStyle.mutedText,
          size: 22,
        ),
      ),
    );
  }
}

/// A focus-traversal group wrapping a scrollable list of option rows. Up/Down
/// move between rows geometrically; horizontal arrows are left for the panel to
/// handle as tab switches.
class _OptionList extends StatelessWidget {
  final List<Widget> children;

  const _OptionList({required this.children});

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        // Build a generous off-screen window so the selected (anchor) row is
        // laid out even when it starts below the fold — required for the
        // open/tab-switch ensureVisible() to be able to scroll to it.
        cacheExtent: 1200,
        children: children,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;

  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Text(
        text,
        style: const TextStyle(
          color: HotstarPlayerStyle.mutedText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          shadows: _kGlassTextShadow,
        ),
      ),
    );
  }
}

/// Shared decoration for focusable panel rows. On TV focus the row lights up
/// with an accent fill + border + soft glow — the same treatment as the
/// play/pause and action buttons — so the focused item is clearly visible
/// rather than a faint dark tint.
BoxDecoration _panelRowDecoration({
  required bool focusedOnTv,
  required bool selected,
  required bool hovered,
}) {
  const accent = HotstarPlayerStyle.accent;
  final Color bg;
  if (focusedOnTv) {
    bg = accent.withValues(alpha: 0.30);
  } else if (selected) {
    bg = accent.withValues(alpha: 0.14);
  } else if (hovered) {
    bg = Colors.white.withValues(alpha: 0.08);
  } else {
    bg = Colors.transparent;
  }
  return BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: focusedOnTv ? accent : Colors.transparent,
      width: 2,
    ),
    boxShadow: focusedOnTv
        ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 12)]
        : null,
  );
}

/// One selectable row. Focus lights it up like the player buttons (see
/// [_panelRowDecoration]). Activates on tap and on D-pad/keyboard
/// select/enter/space; directional movement between rows is handled natively by
/// the enclosing traversal group.
class _PanelSubheader extends StatelessWidget {
  final String title;

  const _PanelSubheader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: HotstarPlayerStyle.mutedText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: _kGlassTextShadow,
        ),
      ),
    );
  }
}
