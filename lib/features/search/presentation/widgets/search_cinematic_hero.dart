import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

/// Full-screen cinematic hero shown when the search screen has no active query.
///
/// Layers:
///   1. Deep dark gradient with radial glows (cinema/theater atmosphere)
///   2. Decorative floating rings (subtle depth)
///   3. Centered column with icon, heading, subtitle, and a glassmorphic
///      search bar connected to the screen's own controller and focus node.
class SearchCinematicHero extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const SearchCinematicHero({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        return Stack(
          children: [
            // ── Layer 1: Cinematic background ──
            Positioned.fill(child: _buildBackground(size, theme)),

            // ── Layer 2: Decorative ornaments ──
            ..._buildOrnaments(size, theme),

            // ── Layer 3: Centered hero content ──
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 28 : 64,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glowing icon badge
                      _buildIconBadge(theme),
                      const SizedBox(height: 28),

                      // Headline
                      Text(
                        'What are you looking for?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      // Subtitle
                      Text(
                        'Search across all your movies, series & live streams',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.45),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // Glassmorphic search bar
                      _GlassSearchField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                        l10n: l10n,
                        theme: theme,
                      ),

                      const SizedBox(height: 20),

                      // Secondary hint
                      Text(
                        'Try "Dune", "Inception" or browse by provider',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Background
  // ────────────────────────────────────────────────────────────────

  Widget _buildBackground(Size size, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF07070F),
            Color(0xFF0D0D1E),
            Color(0xFF12122A),
            Color(0xFF090918),
          ],
          stops: const [0.0, 0.3, 0.65, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Primary radiance — broad wash behind the hero content
          Positioned(
            top: -size.height * 0.08,
            left: 0,
            right: 0,
            height: size.height * 0.45,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 0.85,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.14),
                      theme.colorScheme.primary.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Secondary glow — warm accent bleeding up from the bottom
          Positioned(
            bottom: -size.height * 0.12,
            left: size.width * 0.15,
            width: size.width * 0.7,
            height: size.height * 0.3,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.colorScheme.tertiary.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Subtle top-right highlight
          Positioned(
            top: size.height * 0.05,
            right: -size.width * 0.1,
            width: size.width * 0.5,
            height: size.height * 0.25,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Ornaments
  // ────────────────────────────────────────────────────────────────

  List<Widget> _buildOrnaments(Size size, ThemeData theme) {
    return [
      // Large outer ring — top right
      Positioned(
        top: size.height * 0.06,
        right: -size.width * 0.08,
        child: _OrnamentRing(
          diameter: size.width * 0.45,
          color: theme.colorScheme.primary.withValues(alpha: 0.05),
        ),
      ),
      // Medium ring — bottom left
      Positioned(
        bottom: size.height * 0.08,
        left: -size.width * 0.1,
        child: _OrnamentRing(
          diameter: size.width * 0.35,
          color: theme.colorScheme.tertiary.withValues(alpha: 0.04),
        ),
      ),
      // Small dot cluster — middle right edge
      Positioned(
        top: size.height * 0.55,
        right: size.width * 0.04,
        child: _DotCluster(theme),
      ),
    ];
  }

  // ────────────────────────────────────────────────────────────────
  // Icon badge
  // ────────────────────────────────────────────────────────────────

  Widget _buildIconBadge(ThemeData theme) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.25),
            theme.colorScheme.primary.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.movie_creation_outlined,
        size: 32,
        color: theme.colorScheme.primary.withValues(alpha: 0.8),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Glassmorphic search field
// ──────────────────────────────────────────────────────────────────

class _GlassSearchField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final AppLocalizations l10n;
  final ThemeData theme;

  const _GlassSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.l10n,
    required this.theme,
  });

  @override
  State<_GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<_GlassSearchField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isFocused
        ? widget.theme.colorScheme.primary.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.10);
    final bgColor = _isFocused
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.white.withValues(alpha: 0.05);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: false,
            style: const TextStyle(fontSize: 16, color: Colors.white),
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.search,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            decoration: InputDecoration(
              hintText: widget.l10n.searchHint,
              hintStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Decorative ornament widgets
// ──────────────────────────────────────────────────────────────────

class _OrnamentRing extends StatelessWidget {
  final double diameter;
  final Color color;

  const _OrnamentRing({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(painter: _RingPainter(color)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;

  _RingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer ring
    canvas.drawCircle(center, radius * 0.95, paint);

    // Inner ring
    paint.color = color.withValues(alpha: color.opacity * 0.5);
    canvas.drawCircle(center, radius * 0.75, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.color != color;
}

class _DotCluster extends StatelessWidget {
  final ThemeData theme;

  const _DotCluster(this.theme);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 60,
        height: 60,
        child: CustomPaint(
          painter: _DotClusterPainter(
            theme.colorScheme.primary.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}

class _DotClusterPainter extends CustomPainter {
  final Color color;

  _DotClusterPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final positions = [
      const Offset(30, 10),
      const Offset(50, 20),
      const Offset(10, 30),
      const Offset(40, 40),
      const Offset(20, 50),
    ];
    for (final pos in positions) {
      canvas.drawCircle(pos, 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(_DotClusterPainter oldDelegate) =>
      oldDelegate.color != color;
}
