import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/account/animewitcher_character_models.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/network/dio_client_provider.dart';
import '../../../../core/utils/catalog_metadata_enricher.dart';
import '../../../../core/utils/catalog_rating.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/multimedia_card.dart';

const int detailsExtraTabGridColumns = 3;
const double detailsExtraTabCrossAxisSpacing = 12;
const double detailsExtraTabMainAxisSpacing = 14;

int detailsExtraTabCrossAxisCount(BuildContext context) {
  return context.isHandsetLandscape
      ? ResponsiveBreakpoints.handsetLandscapeAnimeColumns
      : detailsExtraTabGridColumns;
}

/// Height of two poster-card rows in the extra-tabs body.
double detailsExtraTabBodyHeight(BuildContext context, double width) {
  final isDesktop = context.isDesktop;
  final columns = detailsExtraTabCrossAxisCount(context);
  final crossSpacing = MultimediaCardLayout.catalogGridCrossAxisSpacing(
    context,
    fallback: detailsExtraTabCrossAxisSpacing,
  );
  final mainSpacing = MultimediaCardLayout.catalogGridMainAxisSpacing(
    context,
    fallback: detailsExtraTabMainAxisSpacing,
  );
  final childWidth = (width - crossSpacing * (columns - 1)) / columns;
  final childHeight =
      childWidth /
      MultimediaCardLayout.gridAspectRatio(
        isPortrait: true,
        isDesktop: isDesktop,
      );
  return childHeight * 2 + mainSpacing;
}

class ExtraTabGridPreview {
  const ExtraTabGridPreview({required this.items, required this.showMore});

  final List<MultimediaItem> items;
  final bool showMore;
}

/// Caps similar/related extra-tab grids at 6 slots: 5 posters + المزيد
/// when there are more than 6 works.
ExtraTabGridPreview extraTabGridPreview(
  List<MultimediaItem> items, {
  required bool hasMore,
}) {
  final showMore = hasMore || items.length > animeWitcherExtraTabPreviewSlots;
  if (!showMore) {
    return ExtraTabGridPreview(items: items, showMore: false);
  }
  return ExtraTabGridPreview(
    items: items
        .take(animeWitcherExtraTabPreviewItemsWhenMore)
        .toList(growable: false),
    showMore: true,
  );
}

class DetailsPosterGrid extends ConsumerStatefulWidget {
  const DetailsPosterGrid({
    super.key,
    required this.items,
    required this.onItemTap,
    this.showRelationBadge = false,
    this.hasMore = false,
    this.onShowMore,
    this.keyPrefix = 'details-poster-grid',
  });

  final List<MultimediaItem> items;
  final void Function(MultimediaItem) onItemTap;
  final bool showRelationBadge;
  final bool hasMore;
  final VoidCallback? onShowMore;
  final String keyPrefix;

  @override
  ConsumerState<DetailsPosterGrid> createState() => _DetailsPosterGridState();
}

class _DetailsPosterGridState extends ConsumerState<DetailsPosterGrid> {
  late List<MultimediaItem> _displayItems;
  late String _inputSignature;
  var _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _displayItems = widget.items;
    _inputSignature = _signature(widget.items);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enrichMetadata());
  }

  @override
  void didUpdateWidget(covariant DetailsPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.items);
    if (signature == _inputSignature) return;
    _inputSignature = signature;
    _displayItems = widget.items;
    WidgetsBinding.instance.addPostFrameCallback((_) => _enrichMetadata());
  }

  String _signature(List<MultimediaItem> items) {
    return items.map((item) {
      final rating = preferredCatalogRating(item);
      return '${item.url}|${item.year ?? ''}|${rating?.score ?? ''}|${rating?.source.name ?? ''}';
    }).join('\n');
  }

  Future<void> _enrichMetadata() async {
    if (!mounted) return;
    final source = List<MultimediaItem>.from(widget.items);
    final needsMetadata = source.any(
      (item) => item.year == null || preferredCatalogRating(item) == null,
    );
    if (!needsMetadata) return;

    final generation = ++_requestGeneration;
    final enriched = await CatalogMetadataEnricher.enrich(
      ref.read(dioClientProvider),
      source,
    );
    if (!mounted || generation != _requestGeneration) return;
    final enrichedSignature = _signature(enriched);
    if (enrichedSignature == _signature(_displayItems)) return;
    setState(() {
      _displayItems = enriched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final extra = widget.hasMore && widget.onShowMore != null ? 1 : 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GridView.builder(
        key: ValueKey('${widget.keyPrefix}-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: ResponsiveBreakpoints.animeGridDelegate(
          context,
          maxCrossAxisExtent: isDesktop ? 240 : 150,
          childAspectRatio: MultimediaCardLayout.gridAspectRatio(
            isPortrait: true,
            isDesktop: isDesktop,
          ),
          crossAxisSpacing: MultimediaCardLayout.catalogGridCrossAxisSpacing(
            context,
            fallback: detailsExtraTabCrossAxisSpacing,
          ),
          mainAxisSpacing: MultimediaCardLayout.catalogGridMainAxisSpacing(
            context,
            fallback: detailsExtraTabMainAxisSpacing,
          ),
          handsetPortraitCrossAxisCount:
              MultimediaCardLayout.handsetPortraitGridColumns,
        ),
        itemCount: _displayItems.length + extra,
        itemBuilder: (context, index) {
          if (index >= _displayItems.length) {
            return DetailsShowMoreTile(
              key: ValueKey('${widget.keyPrefix}-more'),
              onTap: widget.onShowMore!,
            );
          }
          final item = _displayItems[index];
          return MultimediaCard.fromItem(
            key: ValueKey('${widget.keyPrefix}-$index'),
            item: item,
            heroTag: '${widget.keyPrefix}_${item.url}_$index',
            showRelationBadge: widget.showRelationBadge,
            onTap: () => widget.onItemTap(item),
          );
        },
      ),
    );
  }
}

class DetailsShowMoreTile extends StatelessWidget {
  const DetailsShowMoreTile({
    super.key,
    required this.onTap,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return CardsWrapper(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MultimediaCardLayout.posterRadius),
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(
              MultimediaCardLayout.posterRadius,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz_rounded,
                size: compact ? 28 : 36,
                color: colors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                animeWitcherShowMoreLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
