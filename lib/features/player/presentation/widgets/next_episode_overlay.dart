import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/shared/widgets/thumbnail_error_placeholder.dart';
import 'hotstar_player_style.dart';
import 'player_prompt_placement.dart';

class NextEpisodeOverlay extends StatefulWidget {
  final String nextEpisodeTitle;
  final String? nextEpisodePosterUrl;
  final double? nextEpisodeRating;
  final int? nextEpisodeNumber;
  final int? nextEpisodeSeason;
  final int? nextEpisodeRuntime;
  final VoidCallback onPlayNext;
  final VoidCallback onDismiss;
  final bool isTv;
  final FocusNode? focusNode;
  final bool isPlaying;

  const NextEpisodeOverlay({
    super.key,
    required this.nextEpisodeTitle,
    this.nextEpisodePosterUrl,
    this.nextEpisodeRating,
    this.nextEpisodeNumber,
    this.nextEpisodeSeason,
    this.nextEpisodeRuntime,
    required this.onPlayNext,
    required this.onDismiss,
    this.isTv = false,
    this.focusNode,
    this.isPlaying = true,
  });

  @override
  State<NextEpisodeOverlay> createState() => _NextEpisodeOverlayState();
}

class _NextEpisodeOverlayState extends State<NextEpisodeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _countdownController;
  late final AnimationController _entranceController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final FocusNode _cancelFocusNode;
  Timer? _timer;
  bool _completed = false;
  bool _timerPaused = false;
  double _elapsedFraction = 0.0;

  static const _countdownSecs = 15;

  @override
  void initState() {
    super.initState();
    _cancelFocusNode = FocusNode(debugLabel: 'next_ep_cancel');

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.12, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Cubic(0.0, 0.0, 0.3, 1.0),
      ),
    );

    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _countdownSecs),
    );

    if (widget.isPlaying) {
      _startCountdown();
    } else {
      _timerPaused = true;
    }
  }

  void _startCountdown() {
    _timerPaused = false;
    _countdownController.forward(from: _elapsedFraction);
    final remaining = _countdownSecs * (1.0 - _elapsedFraction);
    _timer = Timer(
      Duration(milliseconds: (remaining * 1000).round()),
      _handleTimeout,
    );
  }

  void _pauseCountdown() {
    if (_timerPaused || _completed) return;
    _timerPaused = true;
    _elapsedFraction = _countdownController.value;
    _countdownController.stop();
    _timer?.cancel();
  }

  void _resumeCountdown() {
    if (!_timerPaused || _completed) return;
    _startCountdown();
  }

  @override
  void didUpdateWidget(NextEpisodeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _resumeCountdown();
      } else {
        _pauseCountdown();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownController.dispose();
    _entranceController.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _handlePressed() {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    _countdownController.stop();
    widget.onPlayNext();
  }

  void _handleTimeout() {
    if (_completed) return;
    _completed = true;
    widget.onPlayNext();
  }

  void _handleDismiss() {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    _countdownController.stop();
    widget.onDismiss();
  }

  String _formatRuntime(int? seconds) {
    if (seconds == null || seconds < 60) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.shortestSide < 600;
    final cardWidth = isCompact ? 280.0 : (widget.isTv ? 440.0 : 360.0);
    final thumbHeight = cardWidth * 9 / 16;
    final radius = isCompact ? 10.0 : 12.0;
    final borderRadius = BorderRadius.circular(radius);

    return PlayerPromptPlacement(
      isTv: widget.isTv,
      alignment: widget.isTv
          ? PromptVerticalAlignment.center
          : PromptVerticalAlignment.bottom,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SizedBox(
            width: cardWidth,
            child: AnimatedBuilder(
              animation: _countdownController,
              builder: (context, _) {
                final remaining =
                    _countdownSecs -
                    (_countdownController.value * _countdownSecs).round();
                return ClipRRect(
                  borderRadius: borderRadius,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(l10n, isCompact, remaining),
                      _buildThumbnail(thumbHeight, cardWidth),
                      _buildInfo(isCompact),
                      _buildButtons(isCompact, l10n),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isCompact, int remaining) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 12 : 16,
          isCompact ? 8 : 10,
          isCompact ? 12 : 16,
          isCompact ? 8 : 10,
        ),
        child: Row(
          children: [
            Text(
              l10n.upNext.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: isCompact ? 10 : 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: Color(0x80FFFFFF),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${remaining}s',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: isCompact ? 10 : 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            if (remaining <= 3 && remaining > 0) _buildPulseDot(),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseDot() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: HotstarPlayerStyle.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: HotstarPlayerStyle.accent.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(double height, double cardWidth) {
    final imageUrl = widget.nextEpisodePosterUrl?.isNotEmpty == true
        ? widget.nextEpisodePosterUrl!
        : null;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: (cardWidth * 2).round(),
              memCacheHeight: (height * 2).round(),
              errorWidget: (context, url, error) =>
                  const ThumbnailErrorPlaceholder(),
              placeholder: (context, url) => Container(
                color: Colors.white.withValues(alpha: 0.05),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            )
          else
            const ThumbnailErrorPlaceholder(),
          if (widget.nextEpisodeRuntime != null &&
              widget.nextEpisodeRuntime! >= 60)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatRuntime(widget.nextEpisodeRuntime),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height * 0.35,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(bool isCompact) {
    final hasRating =
        widget.nextEpisodeRating != null && widget.nextEpisodeRating! > 0;
    final seasonStr = widget.nextEpisodeSeason != null
        ? 'S${widget.nextEpisodeSeason}'
        : '';
    final epStr = widget.nextEpisodeNumber != null
        ? 'E${widget.nextEpisodeNumber}'
        : '';
    final badge = [seasonStr, epStr].where((s) => s.isNotEmpty).join(' ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 12 : 16,
          isCompact ? 10 : 12,
          isCompact ? 12 : 16,
          isCompact ? 8 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: HotstarPlayerStyle.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: HotstarPlayerStyle.accent,
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (hasRating) ...[const Spacer(), _buildRating(isCompact)],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.nextEpisodeTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRating(bool isCompact) {
    final rating = widget.nextEpisodeRating!;
    final fullStars = rating ~/ 2;
    final halfStar = rating % 2 >= 1;
    final numeric = rating.toStringAsFixed(1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          IconData icon;
          final color = i < fullStars
              ? const Color(0xFFFFC107)
              : i == fullStars && halfStar
              ? const Color(0xFFFFC107)
              : Colors.white.withValues(alpha: 0.25);
          if (i < fullStars) {
            icon = Icons.star_rounded;
          } else if (i == fullStars && halfStar) {
            icon = Icons.star_half_rounded;
          } else {
            icon = Icons.star_outline_rounded;
          }
          return Padding(
            padding: EdgeInsets.only(right: isCompact ? 1 : 1.5),
            child: Icon(icon, size: isCompact ? 13 : 14, color: color),
          );
        }),
        const SizedBox(width: 4),
        Text(
          numeric,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: isCompact ? 10 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '/10',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: isCompact ? 9 : 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(bool isCompact, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(isCompact ? 10 : 12),
          bottomRight: Radius.circular(isCompact ? 10 : 12),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 12 : 16,
          isCompact ? 8 : 10,
          isCompact ? 12 : 16,
          isCompact ? 8 : 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: _PlayNowButton(
                onPressed: _handlePressed,
                onDismiss: _handleDismiss,
                isTv: widget.isTv,
                isCompact: isCompact,
                label: l10n.playNow,
                isCompleted: _completed,
                focusNode: widget.focusNode,
              ),
            ),
            SizedBox(width: isCompact ? 8 : 10),
            Expanded(
              child: _CancelButton(
                onPressed: _handleDismiss,
                isTv: widget.isTv,
                isCompact: isCompact,
                label: MaterialLocalizations.of(context).closeButtonTooltip,
                isCompleted: _completed,
                focusNode: _cancelFocusNode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayNowButton extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback onDismiss;
  final bool isTv;
  final bool isCompact;
  final String label;
  final bool isCompleted;
  final FocusNode? focusNode;

  const _PlayNowButton({
    required this.onPressed,
    required this.onDismiss,
    required this.isTv,
    required this.isCompact,
    required this.label,
    required this.isCompleted,
    this.focusNode,
  });

  @override
  State<_PlayNowButton> createState() => _PlayNowButtonState();
}

class _PlayNowButtonState extends State<_PlayNowButton> {
  FocusNode? _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isTv) {
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode!.addListener(() {
        if (mounted) setState(() => _isFocused = _focusNode!.hasFocus);
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScale(
      scale: _isFocused ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: widget.isCompact ? 36 : 40,
        decoration: BoxDecoration(
          color: HotstarPlayerStyle.accent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
          border: Border.all(
            color: _isFocused
                ? HotstarPlayerStyle.accent
                : HotstarPlayerStyle.accent.withValues(alpha: 0.5),
            width: _isFocused ? 1.5 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: HotstarPlayerStyle.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isCompleted ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: widget.isCompact ? 18 : 20,
                ),
                SizedBox(width: widget.isCompact ? 4 : 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.isCompact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isTv) {
      return Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            widget.onDismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: button,
      );
    }
    return button;
  }
}

class _CancelButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isTv;
  final bool isCompact;
  final String label;
  final bool isCompleted;
  final FocusNode? focusNode;

  const _CancelButton({
    required this.onPressed,
    required this.isTv,
    required this.isCompact,
    required this.label,
    required this.isCompleted,
    this.focusNode,
  });

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  FocusNode? _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isTv) {
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode!.addListener(() {
        if (mounted) setState(() => _isFocused = _focusNode!.hasFocus);
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScale(
      scale: _isFocused ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: widget.isCompact ? 36 : 40,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
          border: Border.all(
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.15),
            width: _isFocused ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isCompleted ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
            splashColor: Colors.white.withValues(alpha: 0.1),
            highlightColor: Colors.white.withValues(alpha: 0.03),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: widget.isCompact ? 16 : 18,
                ),
                SizedBox(width: widget.isCompact ? 4 : 6),
                Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: widget.isCompact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isTv) {
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: button,
      );
    }
    return button;
  }
}
