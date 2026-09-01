import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 1–10 star bar matching APK `ScaleRatingBar`: filled/empty gold stars
/// with a short scale bounce when the selected value changes.
class ScaleRatingBar extends StatefulWidget {
  const ScaleRatingBar({
    super.key,
    required this.rating,
    this.onChanged,
    this.enabled = true,
    this.starSize = 28,
    this.itemCount = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 2),
  });

  final int rating;
  final ValueChanged<int>? onChanged;
  final bool enabled;
  final double starSize;
  final int itemCount;
  final EdgeInsets padding;

  @override
  State<ScaleRatingBar> createState() => _ScaleRatingBarState();
}

class _ScaleRatingBarState extends State<ScaleRatingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  late final Animation<double> _scale;
  int _pulseUntil = 0;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = Tween<double>(begin: 1, end: 1.28).animate(
      CurvedAnimation(parent: _bounce, curve: Curves.elasticOut),
    );
    if (widget.rating > 0) {
      _pulseUntil = widget.rating;
    }
  }

  @override
  void didUpdateWidget(covariant ScaleRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rating != widget.rating) {
      _pulseUntil = widget.rating;
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _select(int value) {
    if (!widget.enabled || widget.onChanged == null) return;
    widget.onChanged!(value);
  }

  @override
  Widget build(BuildContext context) {
    const gold = AppTheme.animeWitcherAccent;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 1; index <= widget.itemCount; index++)
              _StarButton(
                index: index,
                filled: index <= widget.rating,
                pulsing: index <= _pulseUntil && _bounce.isAnimating,
                scale: _scale.value,
                size: widget.starSize,
                color: gold,
                enabled: widget.enabled && widget.onChanged != null,
                padding: widget.padding,
                onPressed: () => _select(index),
              ),
          ],
        );
      },
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.index,
    required this.filled,
    required this.pulsing,
    required this.scale,
    required this.size,
    required this.color,
    required this.enabled,
    required this.padding,
    required this.onPressed,
  });

  final int index;
  final bool filled;
  final bool pulsing;
  final double scale;
  final double size;
  final Color color;
  final bool enabled;
  final EdgeInsets padding;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = filled ? Icons.star_rounded : Icons.star_border_rounded;
    final child = Transform.scale(
      scale: pulsing ? scale : 1,
      child: Icon(
        icon,
        size: size,
        color: filled ? color : color.withValues(alpha: 0.38),
      ),
    );
    return Semantics(
      button: enabled,
      selected: filled,
      label: '$index',
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
