import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/shared/widgets/desktop_scroll_wrapper.dart';
import 'package:skystream/shared/widgets/multimedia_card.dart';
import 'package:skystream/shared/widgets/shimmer_placeholder.dart';

class SearchResultSection extends ConsumerStatefulWidget {
  final String providerName;
  final String providerId;
  final List<MultimediaItem> results;
  final bool isLoadingMore;
  final FocusNode? firstCardFocusNode;

  const SearchResultSection({
    super.key,
    required this.providerName,
    required this.providerId,
    required this.results,
    required this.isLoadingMore,
    this.firstCardFocusNode,
  });

  @override
  ConsumerState<SearchResultSection> createState() =>
      _SearchResultSectionState();
}

class _SearchResultSectionState extends ConsumerState<SearchResultSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) return const SizedBox.shrink();

    final isDesktopPlatform =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final isLarge = isDesktopPlatform || context.isTabletOrLarger;
    if (!isLarge) {
      final mobileColumns = context.isHandsetLandscape
          ? ResponsiveBreakpoints.handsetLandscapeAnimeColumns
          : 3;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: mobileColumns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.56,
        ),
        itemCount:
            widget.results.length + (widget.isLoadingMore ? mobileColumns : 0),
        itemBuilder: (context, rIndex) {
          if (rIndex >= widget.results.length) {
            return ShimmerPlaceholder(borderRadius: 12);
          }

          final item = widget.results[rIndex];
          final uniqueTag =
              'search_${widget.providerId}_${item.url}_$rIndex';
          return MultimediaCard(
              key: ValueKey(item.url),
              imageUrl: AppImageFallbacks.poster(
                item.posterUrl,
                label: item.title,
              ),
              title: item.title,
              heroTag: uniqueTag,
              focusNode: rIndex == 0 ? widget.firstCardFocusNode : null,
              onTap: () => DetailsRoute(
                $extra: DetailsRouteExtra(item: item),
              ).push<void>(context),
            );
        },
      );
    }

    final isLandscape = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    if (isLandscape) {
      const desktopColumns = 8;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: desktopColumns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.56,
        ),
        itemCount:
            widget.results.length + (widget.isLoadingMore ? desktopColumns : 0),
        itemBuilder: (context, rIndex) {
          if (rIndex >= widget.results.length) {
            return ShimmerPlaceholder(borderRadius: 12);
          }

          final item = widget.results[rIndex];
          final uniqueTag =
              'search_${widget.providerId}_${item.url}_$rIndex';
          return MultimediaCard(
            key: ValueKey(item.url),
            imageUrl: AppImageFallbacks.poster(
              item.posterUrl,
              label: item.title,
            ),
            title: item.title,
            heroTag: uniqueTag,
            compact: true,
            focusNode: rIndex == 0 ? widget.firstCardFocusNode : null,
            onTap: () => DetailsRoute(
              $extra: DetailsRouteExtra(item: item),
            ).push<void>(context),
          );
        },
      );
    }

    const listHeight = 350.0;
    const cardWidth = 200.0;
    const spacing = 24.0;
    return SizedBox(
      height: listHeight,
      child: DesktopScrollWrapper(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          scrollDirection: Axis.horizontal,
          itemCount: widget.results.length + (widget.isLoadingMore ? 3 : 0),
          itemExtent: cardWidth + spacing,
          clipBehavior: Clip.none,
          itemBuilder: (context, rIndex) {
            if (rIndex >= widget.results.length) {
              return Padding(
                padding: const EdgeInsets.only(right: spacing),
                child: ShimmerPlaceholder(borderRadius: 12),
              );
            }

            final item = widget.results[rIndex];
            final uniqueTag =
                'search_${widget.providerId}_${item.url}_$rIndex';
            return Padding(
              padding: const EdgeInsets.only(right: spacing),
              child: MultimediaCard(
                key: ValueKey(item.url),
                imageUrl: AppImageFallbacks.poster(
                  item.posterUrl,
                  label: item.title,
                ),
                title: item.title,
                heroTag: uniqueTag,
                focusNode: rIndex == 0 ? widget.firstCardFocusNode : null,
                onTap: () => DetailsRoute(
                  $extra: DetailsRouteExtra(item: item),
                ).push<void>(context),
              ),
            );
          },
        ),
      ),
    );  }

}
