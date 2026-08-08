import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
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

    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (onViewAll != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: onViewAll,
                      child: Text(isArabic ? 'عرض المزيد' : 'View all'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            height: 198,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return NewsCard(
                    item: item,
                    compact: true,
                    onOpen: onOpen == null ? null : () => onOpen!(item),
                    onCommentsTap: onOpen == null ? null : () => onOpen!(item),
                    onAnimeTap: onAnimeTap == null
                        ? null
                        : () => onAnimeTap!(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
