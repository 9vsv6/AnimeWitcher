import 'package:flutter/material.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/catalog_ltr.dart';
import '../../../shared/widgets/multimedia_card.dart';

/// Character-details anime list: 3 posters per row, wrapping downward.
class CharacterAnimesGrid extends StatelessWidget {
  const CharacterAnimesGrid({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
  });

  final String title;
  final List<MultimediaItem> items;
  final void Function(MultimediaItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        CatalogLtr(
          child: GridView.builder(
            key: const ValueKey('character-animes-grid'),
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
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              handsetPortraitCrossAxisCount: 3,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return MultimediaCard.fromItem(
                key: ValueKey('character-animes-grid-$index'),
                item: item,
                heroTag: 'character_anime_${item.url}_$index',
                showRelationBadge: true,
                onTap: () => onItemTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
