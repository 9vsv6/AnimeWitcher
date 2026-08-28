import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop
                      ? LayoutConstants.dashboardContentPadding
                      : LayoutConstants.spacingMd,
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0) const SizedBox(width: 10),
                      NewsCard(
                        key: ValueKey('news-rail-${items[index].id}'),
                        item: items[index],
                        compact: true,
                        onOpen: onOpen == null
                            ? null
                            : () => onOpen!(items[index]),
                        onAnimeTap: onAnimeTap == null
                            ? null
                            : () => onAnimeTap!(items[index]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
