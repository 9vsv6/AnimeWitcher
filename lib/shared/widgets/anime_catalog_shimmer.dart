import 'package:flutter/material.dart';

import '../../core/utils/responsive_breakpoints.dart';
import 'catalog_ltr.dart';
import 'multimedia_card.dart';
import 'shimmer_placeholder.dart';

/// Skeleton poster matching home-page card loading.
class AnimePosterShimmer extends StatelessWidget {
  const AnimePosterShimmer({
    super.key,
    this.isPortrait = true,
    this.characterCaptionSpace = false,
  });

  final bool isPortrait;
  final bool characterCaptionSpace;

  @override
  Widget build(BuildContext context) {
    // A real catalog card receives a bounded grid-cell height and lets its
    // poster expand into all space left above the caption. Mirror that exact
    // structure here so replacing the skeleton never changes poster/card size.
    final captionExtent = characterCaptionSpace
        ? MultimediaCardLayout.characterCaptionExtent(context)
        : MultimediaCardLayout.animeCaptionExtent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ShimmerPlaceholder.rectangular(
            borderRadius: MultimediaCardLayout.posterRadius,
          ),
        ),
        SizedBox(height: captionExtent),
      ],
    );
  }
}

/// Full-page anime grid skeleton — same style as the home catalog shimmer.
class AnimeCatalogShimmer extends StatelessWidget {
  const AnimeCatalogShimmer({
    super.key,
    this.itemCount,
    this.padding,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.characterCaptionSpace = false,
  });

  final int? itemCount;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  /// Character tiles only reserve one name line, so their empty caption area
  /// is intentionally smaller than the anime title + type area.
  final bool characterCaptionSpace;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final count = itemCount ?? (isDesktop ? 18 : 12);
    final horizontalPadding = MultimediaCardLayout.catalogGridHorizontalPadding(
      context,
    );
    final crossAxisSpacing = MultimediaCardLayout.catalogGridCrossAxisSpacing(
      context,
    );
    final mainAxisSpacing = MultimediaCardLayout.catalogGridMainAxisSpacing(
      context,
    );
    final childAspectRatio = characterCaptionSpace
        ? MultimediaCardLayout.characterGridAspectRatio
        : MultimediaCardLayout.gridAspectRatio(
            isPortrait: true,
            isDesktop: isDesktop,
          );
    return CatalogLtr(
      child: GridView.builder(
        physics: physics,
        padding:
            padding ??
            EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              110,
            ),
        gridDelegate: ResponsiveBreakpoints.animeGridDelegate(
          context,
          maxCrossAxisExtent: isDesktop ? 240 : 150,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          handsetPortraitCrossAxisCount:
              MultimediaCardLayout.handsetPortraitGridColumns,
          horizontalPadding: horizontalPadding,
        ),
        itemCount: count,
        itemBuilder: (context, index) => AnimePosterShimmer(
          key: ValueKey('anime-catalog-shimmer-$index'),
          characterCaptionSpace: characterCaptionSpace,
        ),
      ),
    );
  }
}
