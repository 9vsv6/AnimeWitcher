import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final ShapeBorder shapeBorder;

  ShimmerPlaceholder({
    super.key,
    this.width,
    this.height,
    double borderRadius = 0,
    ShapeBorder shapeBorder = const RoundedRectangleBorder(),
  }) : shapeBorder = borderRadius > 0
           ? RoundedRectangleBorder(
               borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
             )
           : shapeBorder;

  ShimmerPlaceholder.rectangular({
    super.key,
    this.width,
    this.height,
    double borderRadius = 0,
  }) : shapeBorder = RoundedRectangleBorder(
         borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
       );

  const ShimmerPlaceholder.circular({super.key, this.width, this.height})
    : shapeBorder = const CircleBorder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseColor = colors.surfaceContainerHighest;
    final highlightColor = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.16),
      baseColor,
    );

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(color: baseColor, shape: shapeBorder),
      ),
    );
  }
}
