import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/paged_rail.dart';
import 'home_section_header.dart';
import 'news_card.dart';

class NewsSection extends StatelessWidget {
  const NewsSection({
    super.key,
    required this.title,
    required this.items,
    this.onViewAll,
    this.onOpen,
    this.onAnimeTap,
  });

  final String title;
  final List<NewsItem> items;
  final VoidCallback? onViewAll;
  final void Function(NewsItem item)? onOpen;
  final void Function(NewsItem item)? onAnimeTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isDesktop = context.isDesktop;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSectionHeader(
              title: title,
              action: onViewAll == null
                  ? null
                  : HomeViewAllButton(onTap: onViewAll!),
            ),
            SizedBox(
              height: 172,
              child: PagedRail(
                // 200 (compact card intrinsic width from NewsCard) + 10
                // (inter-card gap) = 210 stride so snaps land on card edges.
                itemExtent: 210,
                itemCount: items.length,
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop
                      ? LayoutConstants.dashboardContentPadding
                      : LayoutConstants.spacingMd,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  // itemExtent hands children TIGHT width constraints, so the
                  // compact card (intrinsic 200) would stretch to the full
                  // 210 stride and neighbouring cards would touch. Padding
                  // deflates the constraints instead, keeping the card at 200
                  // with a 10px trailing gap as part of the stride.
                  return Padding(
                    key: ValueKey('news-rail-${item.id}'),
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: NewsCard(
                      item: item,
                      compact: true,
                      onOpen: onOpen == null ? null : () => onOpen!(item),
                      onAnimeTap: onAnimeTap == null
                          ? null
                          : () => onAnimeTap!(item),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
