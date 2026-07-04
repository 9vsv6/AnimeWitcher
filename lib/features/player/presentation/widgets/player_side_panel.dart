import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter, FontFeature;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_view/video_view.dart' as vv;
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import '../../../settings/presentation/player_settings_provider.dart';
import '../player_controller.dart';
import 'hotstar_player_style.dart';
import 'player_bottom_sheets.dart';
import 'player_utils.dart';
import 'subtitle_sync_dialog.dart';
import 'subtitle_appearance_dialog.dart';

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
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(-12, 0),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. BACKGROUND LAYER: Deep ambient glow mesh to ensure the frost has texture to refract
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.16),
                    Colors.blue.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.orange.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  center: Alignment.bottomRight,
                  radius: 1.3,
                ),
              ),
            ),
          ),
          // 2. FROST FILTER + 3. TINTED OVERLAY
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xC70E1013), // 0.78 opacity tinted overlay
                ),
              ),
            ),
          ),
          // 4. BORDER LIGHT (1px rim highlight simulating catching light on inner rim edge)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1.0,
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

/// Content for the sources side panel: a [TabBar] (Sources · Audio · Subtitles)
/// over a single-tab body. D-pad is two clean axes — Left/Right switch tabs,
/// Up/Down move through the rows of the active tab. Every selection applies
/// instantly: tapping a source switches playback immediately; tapping an
/// audio/subtitle track applies it right away. No Apply button, no pause/resume.
class PlayerSourcesPanel extends ConsumerStatefulWidget {
  final Player player;
  final vv.VideoController? videoViewController;
  final bool isTv;
  final VoidCallback onClose;

  const PlayerSourcesPanel({
    super.key,
    required this.player,
    required this.onClose,
    this.videoViewController,
    this.isTv = false,
  });

  @override
  ConsumerState<PlayerSourcesPanel> createState() => _PlayerSourcesPanelState();
}

class _PlayerSourcesPanelState extends ConsumerState<PlayerSourcesPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Root node holds focus only as a fallback (e.g. a tab with no rows) so
  // Left/Right tab-switching and Back still work; skipTraversal keeps it out of
  // the normal Up/Down path.
  final FocusNode _rootNode = FocusNode(
    debugLabel: 'sources_panel_root',
    skipTraversal: true,
  );
  // Attached to the active tab's current (or first) row — the open/switch focus
  // target.
  final FocusNode _anchorNode = FocusNode(debugLabel: 'sources_panel_anchor');

  // True while focus is on the header (tabs/close). There, Left/Right move
  // between tab headers (default focus traversal); in the body they trigger the
  // quick tab-switch QoL instead.
  bool _headerFocused = false;

  // Optimistic local selection so the checkmark moves the instant a row is
  // tapped, before the engine's track stream ticks back with the real state.
  String? _audioId;
  String? _subtitleId;
  bool _subtitlesOff = false;

  // The row that owns [_anchorNode] (the open/tab-switch focus target). Captured
  // when the panel opens or the tab changes and then held STABLE — it must not
  // follow the live selection, or selecting a row would move the anchor onto it,
  // swap that row's focus node, and bounce focus to the next item.
  static const String _kOffId = '__subtitles_off__';
  String? _anchorId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: ref
          .read(playerControllerProvider)
          .sourcesPanelTab
          .clamp(0, 2),
    );
    _tabController.addListener(_onTabChanged);
    _syncFromSnapshot();
    _anchorId = _activeSelectedId();
    // If (re)mounted while already open — e.g. a blocking loading/error phase
    // tore down and rebuilt the controls subtree — restore D-pad focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(playerControllerProvider).showSourcesPanel) {
        _focusActiveTab();
      }
    });
  }

  void _onTabChanged() {
    if (!mounted) return;
    // Re-anchor to the new tab's current selection, then refocus it.
    setState(() => _anchorId = _activeSelectedId());
    _focusActiveTab();
  }

  String _sourceKey(StreamResult s) => '${s.source} ${s.url}';

  /// The id of the active tab's current selection — used to capture a stable
  /// anchor row. Returns null when nothing is selected (anchor falls to row 0).
  String? _activeSelectedId() {
    switch (_tabController.index) {
      case 1:
        return _audioId;
      case 2:
        return _subtitlesOff ? _kOffId : _subtitleId;
      default:
        final cur = ref.read(playerControllerProvider).currentStream;
        return cur != null ? _sourceKey(cur) : null;
    }
  }

  void _syncFromSnapshot() {
    final snapshot = ref
        .read(playerControllerProvider.notifier)
        .getTrackSelectionSnapshot();
    _audioId = snapshot.audioTracks.firstWhereOrNull((t) => t.selected)?.id;
    _subtitlesOff = snapshot.subtitlesOffSelected;
    _subtitleId = _subtitlesOff
        ? null
        : snapshot.subtitleTracks.firstWhereOrNull((t) => t.selected)?.id;
  }

  /// Focus the active tab's anchor row (the current selection, or the first
  /// row) and scroll it to the centre so it's never left off-screen after a tab
  /// switch. Falls back to the root if the tab has no focusable row (e.g. an
  /// empty audio list) so the remote isn't stranded.
  void _focusActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(playerControllerProvider).showSourcesPanel) {
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
      } else {
        _rootNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _rootNode.dispose();
    _anchorNode.dispose();
    super.dispose();
  }

  KeyEventResult _handlePanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // Back/escape is intentionally NOT handled here. It bubbles to the player's
    // root key handler, which closes the panel through a single guarded path —
    // so the duplicate Back delivery on some TVs (KeyEvent + route-pop) can't
    // double-act and walk past the panel into exiting the player.
    // Left/Right quick-switch tabs from the BODY (QoL). When focus is on the
    // header we let them through so directional traversal moves between the tab
    // headers and the close button as normal. Up/Down always fall through to
    // traversal within the active tab's list.
    if (!_headerFocused) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_tabController.index > 0) {
          _tabController.animateTo(_tabController.index - 1);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_tabController.index < _tabController.length - 1) {
          _tabController.animateTo(_tabController.index + 1);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // When the panel opens, jump to the requested tab, refresh selection, and
    // hand focus to the active tab.
    ref.listen(playerControllerProvider.select((s) => s.showSourcesPanel), (
      prev,
      next,
    ) {
      if (next == true && prev != true && mounted) {
        final tab = ref
            .read(playerControllerProvider)
            .sourcesPanelTab
            .clamp(0, 2);
        if (_tabController.index != tab) _tabController.index = tab;
        setState(() {
          _syncFromSnapshot();
          _anchorId = _activeSelectedId();
        });
        _focusActiveTab();
      }
    });
    // A source change loads its own track set — old ids no longer apply.
    ref.listen(playerControllerProvider.select((s) => s.currentStreamIndex), (
      prev,
      next,
    ) {
      if (prev != next && mounted) setState(_syncFromSnapshot);
    });

    final l10n = AppLocalizations.of(context)!;

    return Focus(
      focusNode: _rootNode,
      onKeyEvent: _handlePanelKey,
      // left: false — the drawer is right-anchored, so the device's left cutout
      // inset (landscape) must not phantom-indent the content.
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: tabs + close. Fully focusable (default behaviour) — D-pad
            // Up from the body reaches the tabs/close, OK activates them. The
            // wrapper tracks header focus so Left/Right move *between* tab
            // headers there, while in the body Left/Right keep the quick
            // tab-switch QoL. Non-scrollable so 3 tabs fit without a horizontal
            // Scrollable that would trap directional focus.
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (v) => _headerFocused = v,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: false,
                        // Tight label padding so "Audio Tracks" fits the three
                        // equal-width tabs without clipping.
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        indicatorColor: HotstarPlayerStyle.accent,
                        indicatorWeight: 2.5,
                        dividerColor: Colors.transparent,
                        labelColor: HotstarPlayerStyle.primaryText,
                        unselectedLabelColor: HotstarPlayerStyle.mutedText,
                        labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          shadows: _kGlassTextShadow,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          shadows: _kGlassTextShadow,
                        ),
                        tabs: [
                          Tab(text: l10n.sources),
                          Tab(text: l10n.audioTracks),
                          Tab(text: l10n.subtitles),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
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
            ),
            const Divider(color: HotstarPlayerStyle.divider, height: 1),
            Expanded(child: _buildActiveTab(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab(AppLocalizations l10n) {
    // Distinct keys per tab so switching gives each a fresh ListView (starting
    // at the top) instead of inheriting the previous tab's scroll offset.
    switch (_tabController.index) {
      case 1:
        return KeyedSubtree(
          key: const ValueKey('panel_tab_audio'),
          child: _buildTrackTab(l10n, isAudio: true),
        );
      case 2:
        return KeyedSubtree(
          key: const ValueKey('panel_tab_subtitles'),
          child: _buildTrackTab(l10n, isAudio: false),
        );
      default:
        return KeyedSubtree(
          key: const ValueKey('panel_tab_sources'),
          child: _buildSourcesTab(l10n),
        );
    }
  }

  Widget _buildSourcesTab(AppLocalizations l10n) {
    final streams = ref.watch(
      playerControllerProvider.select((s) => s.streams),
    );
    final currentStream = ref.watch(
      playerControllerProvider.select((s) => s.currentStream),
    );

    if (streams.isEmpty) {
      return _EmptyHint(text: l10n.noResultsFound);
    }

    return _OptionList(
      children: streams.mapIndexed((index, stream) {
        final selected =
            currentStream != null &&
            currentStream.url == stream.url &&
            currentStream.source == stream.source;
        final isAnchor =
            _sourceKey(stream) == _anchorId ||
            (_anchorId == null && index == 0);
        return _PanelOptionRow(
          label: stream.source,
          selected: selected,
          isTv: widget.isTv,
          focusNode: isAnchor ? _anchorNode : null,
          onTap: () {
            if (selected) return;
            ref
                .read(playerControllerProvider.notifier)
                .changeStream(stream, manualSelection: true);
          },
        );
      }).toList(),
    );
  }

  /// Audio + Subtitles share a layout; both rebuild on engine track changes so a
  /// freshly loaded source's tracks appear without reopening the panel.
  Widget _buildTrackTab(AppLocalizations l10n, {required bool isAudio}) {
    final useExoPlayer = ref.watch(
      playerControllerProvider.select((s) => s.useExoPlayer),
    );
    if (useExoPlayer && widget.videoViewController != null) {
      return ListenableBuilder(
        listenable: widget.videoViewController!.mediaInfo,
        builder: (context, _) =>
            isAudio ? _buildAudioBody(l10n) : _buildSubtitleBody(l10n),
      );
    }
    return StreamBuilder<Tracks>(
      stream: widget.player.stream.tracks,
      builder: (context, _) =>
          isAudio ? _buildAudioBody(l10n) : _buildSubtitleBody(l10n),
    );
  }

  Widget _buildAudioBody(AppLocalizations l10n) {
    final tracks = ref
        .read(playerControllerProvider.notifier)
        .getTrackSelectionSnapshot()
        .audioTracks;
    if (tracks.isEmpty) return _EmptyHint(text: l10n.noAudioTracks);
    return _OptionList(
      children: tracks.mapIndexed((index, track) {
        final selected = _audioId == track.id;
        final isAnchor =
            track.id == _anchorId || (_anchorId == null && index == 0);
        return _PanelOptionRow(
          label: track.label,
          metadata: track.subtitle,
          selected: selected,
          isTv: widget.isTv,
          focusNode: isAnchor ? _anchorNode : null,
          onTap: () {
            setState(() => _audioId = track.id);
            ref
                .read(playerControllerProvider.notifier)
                .selectAudioTrack(track.id);
          },
        );
      }).toList(),
    );
  }

  // Palettes mirrored from the legacy subtitle-style dialog.
  static const List<int> _textColors = [
    0xFFFFFFFF,
    0xFFFFFF00,
    0xFF00FFFF,
    0xFFFF00FF,
    0xFF00FF00,
    0xFFFF0000,
    0xFF2196F3,
    0xFFFF9800,
  ];
  static const List<int> _bgColors = [
    0x00000000,
    0xFF000000,
    0xFF333333,
    0xFF1A1A1A,
    0xFF001F3F,
  ];

  Widget _buildSubtitleBody(AppLocalizations l10n) {
    final controller = ref.read(playerControllerProvider.notifier);
    final settingsNotifier = ref.read(playerSettingsProvider.notifier);

    final supportsExternal = ref.watch(
      playerControllerProvider.select((s) => s.supportsExternalSubtitleLoading),
    );
    final supportsDelay = ref.watch(
      playerControllerProvider.select((s) => s.supportsSubtitleDelay),
    );
    final supportsStyling = ref.watch(
      playerControllerProvider.select((s) => s.supportsSubtitleStyling),
    );
    final settings =
        ref.watch(playerSettingsProvider).asData?.value ??
        const PlayerSettings();

    final tracks = controller.getTrackSelectionSnapshot().subtitleTracks;

    void applyStyle({double? size, int? color, int? bg, double? opacity}) {
      settingsNotifier.setSubtitleSettings(
        size ?? settings.subtitleSize,
        color ?? settings.subtitleColor,
        bg ?? settings.subtitleBackgroundColor,
        opacity ?? settings.subtitleBackgroundOpacity,
      );
      controller.applySubtitleSettings();
    }

    final rows = <Widget>[
      // Track selection (Off + available tracks) first. Anchor stays on the
      // active choice so the panel opens focused on it.
      _PanelOptionRow(
        label: l10n.off,
        selected: _subtitlesOff,
        isTv: widget.isTv,
        focusNode: (_anchorId == _kOffId || _anchorId == null)
            ? _anchorNode
            : null,
        onTap: () {
          setState(() {
            _subtitlesOff = true;
            _subtitleId = null;
          });
          controller.selectSubtitleTrack(null);
        },
      ),
      ...tracks.map((track) {
        final selected = !_subtitlesOff && _subtitleId == track.id;
        return _PanelOptionRow(
          label: track.label,
          metadata: track.subtitle,
          selected: selected,
          isTv: widget.isTv,
          focusNode: track.id == _anchorId ? _anchorNode : null,
          onTap: () {
            setState(() {
              _subtitlesOff = false;
              _subtitleId = track.id;
            });
            controller.selectSubtitleTrack(track.id);
          },
        );
      }),

      // Add-subtitle actions, after the list (gated on engine support).
      _PanelOptionRow(
        label: l10n.loadFromDevice,
        leadingIcon: Icons.file_open_outlined,
        selected: false,
        isTv: widget.isTv,
        enabled: supportsExternal,
        onTap: () => controller.loadExternalSubtitleFile(),
      ),
      _PanelOptionRow(
        label: l10n.searchOnline,
        leadingIcon: Icons.search_rounded,
        selected: false,
        isTv: widget.isTv,
        enabled: supportsExternal,
        onTap: () => PlayerBottomSheets.showSubtitleSearch(context),
      ),

      // Sync (timing) — opens the fullscreen synchronization dialog
      if (supportsDelay) ...[
        _PanelSubheader(title: l10n.subtitleSync),
        _PanelOptionRow(
          label: l10n.syncDelay,
          leadingIcon: Icons.sync,
          selected: false,
          isTv: widget.isTv,
          onTap: () {
            // Dismiss the side panel first
            widget.onClose();
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SubtitleSyncDialog(wasPlaying: controller.isPlaying),
              ),
            );
          },
        ),
      ],
      if (supportsStyling) ...[
        _PanelSubheader(title: l10n.styleSettings),
        _PanelOptionRow(
          label: "Subtitle Appearance",
          leadingIcon: Icons.palette_outlined,
          selected: false,
          isTv: widget.isTv,
          onTap: () {
            // Dismiss the side panel first
            widget.onClose();
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SubtitleAppearanceDialog(wasPlaying: controller.isPlaying),
                fullscreenDialog: true,
              ),
            );
          },
        ),
      ],
    ];

    return _OptionList(children: rows);
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
    final episodes = widget.item.episodes ?? const <Episode>[];
    final currentUrl =
        ref.watch(
          playerControllerProvider.select((s) => s.currentStream?.url),
        ) ??
        ref.read(playerControllerProvider.notifier).currentEpisodeUrl;
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
            onTap: () =>
                ref.read(playerControllerProvider.notifier).loadEpisode(ep),
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
                        Text(
                          'S${ep.season} : E${ep.episode}',
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

/// Content (torrent file picker) side panel — same right-drawer shell and row
/// styling as the other panels. Single D-pad list of the torrent's files; the
/// first row is the focus anchor. Selecting a file switches playback to it and
/// closes the pane.
class PlayerContentPanel extends ConsumerStatefulWidget {
  final bool isTv;
  final ValueChanged<int> onFileSelected;
  final VoidCallback onClose;

  const PlayerContentPanel({
    super.key,
    required this.onFileSelected,
    required this.onClose,
    this.isTv = false,
  });

  @override
  ConsumerState<PlayerContentPanel> createState() => _PlayerContentPanelState();
}

class _PlayerContentPanelState extends ConsumerState<PlayerContentPanel> {
  final FocusNode _anchorNode = FocusNode(debugLabel: 'content_panel_anchor');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(playerControllerProvider).showContentPanel) {
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
      if (!mounted || !ref.read(playerControllerProvider).showContentPanel) {
        return;
      }
      if (_anchorNode.context != null) _anchorNode.requestFocus();
    });
  }

  bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mkv') ||
        p.endsWith('.avi') ||
        p.endsWith('.mov') ||
        p.endsWith('.webm') ||
        p.endsWith('.m4v');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerControllerProvider.select((s) => s.showContentPanel), (
      prev,
      next,
    ) {
      if (next == true && prev != true && mounted) _focusAnchor();
    });

    final l10n = AppLocalizations.of(context)!;
    final torrentStatus = ref.watch(
      playerControllerProvider.select((s) => s.torrentStatus),
    );
    final files =
        (torrentStatus?.data['file_stats'] as List<dynamic>?) ??
        const <dynamic>[];

    final rows = <Widget>[];
    for (var index = 0; index < files.length; index++) {
      final file = Map<String, dynamic>.from(files[index] as Map);
      final path = file['path'] as String? ?? l10n.unknown;
      final length = file['length'] as int? ?? 0;
      final id = file['id'] as int? ?? (index + 1);
      rows.add(
        _PanelOptionRow(
          label: path.split('/').last,
          metadata: formatBytes(length),
          leadingIcon: _isVideo(path)
              ? Icons.movie_outlined
              : Icons.insert_drive_file_outlined,
          selected: false,
          isTv: widget.isTv,
          focusNode: index == 0 ? _anchorNode : null,
          onTap: () {
            widget.onFileSelected(id);
            widget.onClose();
          },
        ),
      );
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
                  Icons.folder_outlined,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.content,
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
            child: files.isEmpty
                ? _EmptyHint(text: l10n.noResultsFound)
                : _OptionList(children: rows),
          ),
        ],
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
        scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
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
class _PanelOptionRow extends StatefulWidget {
  final String label;
  final String? metadata;
  final bool selected;
  final bool isTv;
  final bool enabled;
  final FocusNode? focusNode;
  final IconData? leadingIcon;
  final VoidCallback onTap;

  const _PanelOptionRow({
    required this.label,
    required this.selected,
    required this.isTv,
    required this.onTap,
    this.metadata,
    this.focusNode,
    this.leadingIcon,
    this.enabled = true,
  });

  @override
  State<_PanelOptionRow> createState() => _PanelOptionRowState();
}

class _PanelOptionRowState extends State<_PanelOptionRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final showHighlight = enabled && (_focused || _hovered);
    final meta = widget.metadata?.trim();
    final hasMeta = meta != null && meta.isNotEmpty;
    final labelColor = !enabled
        ? HotstarPlayerStyle.mutedText
        : (widget.selected
              ? HotstarPlayerStyle.primaryText
              : HotstarPlayerStyle.secondaryText);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            if (enabled) widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: HotstarPlayerStyle.fastMotionDuration,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: _panelRowDecoration(
                focusedOnTv: enabled && _focused && widget.isTv,
                selected: widget.selected,
                hovered: showHighlight,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: widget.leadingIcon != null
                        ? Icon(
                            widget.leadingIcon,
                            color: enabled
                                ? HotstarPlayerStyle.secondaryText
                                : HotstarPlayerStyle.mutedText,
                            size: 20,
                          )
                        : (widget.selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: HotstarPlayerStyle.accent,
                                  size: 20,
                                )
                              : null),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: widget.label,
                        children: [
                          if (hasMeta)
                            TextSpan(
                              text: '   $meta',
                              style: const TextStyle(
                                color: HotstarPlayerStyle.mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                shadows: _kGlassTextShadow,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 15,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        shadows: _kGlassTextShadow,
                      ),
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

/// Small uppercase group label between sections inside a tab.
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

/// A settings row adjusted with Left/Right (D-pad/keyboard) while focused — it
/// consumes those keys so the panel doesn't treat them as tab switches — and
/// with the inline −/+ buttons for touch/mouse. Up/Down still traverse rows.
/// Shows either a [valueText] or a colour [swatch].
class _SubtitleAdjusterRow extends StatefulWidget {
  final String label;
  final String valueText;
  final bool isTv;
  final IconData decreaseIcon;
  final IconData increaseIcon;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _SubtitleAdjusterRow({
    required this.label,
    required this.isTv,
    required this.valueText,
    required this.onDecrease,
    required this.onIncrease,
    this.decreaseIcon = Icons.remove_rounded,
    this.increaseIcon = Icons.add_rounded,
  });

  @override
  State<_SubtitleAdjusterRow> createState() => _SubtitleAdjusterRowState();
}

class _SubtitleAdjusterRowState extends State<_SubtitleAdjusterRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showHighlight = _focused || _hovered;
    return Semantics(
      label: widget.label,
      value: widget.valueText,
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          // Capture Left/Right so the panel doesn't switch tabs while a value
          // is being adjusted. Up/Down fall through to row traversal.
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onDecrease();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onIncrease();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: HotstarPlayerStyle.fastMotionDuration,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: _panelRowDecoration(
              focusedOnTv: _focused && widget.isTv,
              selected: false,
              hovered: showHighlight,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HotstarPlayerStyle.secondaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      shadows: _kGlassTextShadow,
                    ),
                  ),
                ),
                // −/value/+ cluster: tappable for touch, not separately
                // focusable so D-pad treats the whole row as one stop.
                ExcludeFocus(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepButton(
                        icon: widget.decreaseIcon,
                        onTap: widget.onDecrease,
                      ),
                      SizedBox(width: 56, child: Center(child: _buildValue())),
                      _StepButton(
                        icon: widget.increaseIcon,
                        onTap: widget.onIncrease,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValue() {
    return Text(
      widget.valueText,
      maxLines: 1,
      style: const TextStyle(
        color: HotstarPlayerStyle.primaryText,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
        shadows: _kGlassTextShadow,
      ),
    );
  }
}

/// Compact −/+ tap target for adjuster rows (touch/mouse). Not focusable; the
/// parent row owns D-pad focus.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: HotstarPlayerStyle.primaryText, size: 22),
      ),
    );
  }
}

/// A label followed by a wrapped grid of colour swatches. Swatches are real
/// focusable widgets in the panel's traversal group: Up/Down move between grid
/// rows (and out to other settings) geometrically, while each swatch consumes
/// Left/Right to step to the previous/next swatch in reading order — so the
/// panel never mistakes them for tab switches.
class _ColorGridRow extends StatelessWidget {
  final String label;
  final List<int> palette;
  final int selectedColor;
  final bool isTv;
  final ValueChanged<int> onSelected;

  const _ColorGridRow({
    required this.label,
    required this.palette,
    required this.selectedColor,
    required this.isTv,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            label,
            style: const TextStyle(
              color: HotstarPlayerStyle.secondaryText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              shadows: _kGlassTextShadow,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: palette
                .map(
                  (value) => _ColorSwatch(
                    colorValue: value,
                    selected: value == selectedColor,
                    isTv: isTv,
                    onSelect: () => onSelected(value),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatefulWidget {
  final int colorValue;
  final bool selected;
  final bool isTv;
  final VoidCallback onSelect;

  const _ColorSwatch({
    required this.colorValue,
    required this.selected,
    required this.isTv,
    required this.onSelect,
  });

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.colorValue);
    final isTransparent = color.a == 0;
    final ring = _focused && widget.isTv;
    final checkColor = color.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        // Step between swatches in reading order; consume so the panel doesn't
        // switch tabs. Up/Down bubble for vertical traversal.
        if (key == LogicalKeyboardKey.arrowLeft) {
          node.previousFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          node.nextFocus();
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
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: HotstarPlayerStyle.fastMotionDuration,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isTransparent ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: ring
                    ? HotstarPlayerStyle.accent
                    : (widget.selected
                          ? Colors.white
                          : (_hovered ? Colors.white70 : Colors.white24)),
                width: ring || widget.selected ? 3 : 1.5,
              ),
              boxShadow: ring
                  ? [
                      BoxShadow(
                        color: HotstarPlayerStyle.accent.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: widget.selected
                ? Icon(Icons.check_rounded, size: 20, color: checkColor)
                : (isTransparent
                      ? const Icon(
                          Icons.block_rounded,
                          size: 18,
                          color: Colors.white54,
                        )
                      : null),
          ),
        ),
      ),
    );
  }
}
