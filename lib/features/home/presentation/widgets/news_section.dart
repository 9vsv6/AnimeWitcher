import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
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

    final l10n = AppLocalizations.of(context)!;
    final localeDirection = Directionality.of(context);
    final isDesktop = context.isDesktop;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop
                    ? LayoutConstants.dashboardContentPadding
                    : LayoutConstants.spacingMd,
                LayoutConstants.spacingLg,
                isDesktop
                    ? LayoutConstants.dashboardContentPadding
                    : LayoutConstants.spacingMd,
                LayoutConstants.spacingSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textDirection: localeDirection,
                          textAlign: TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isDesktop ? 24 : 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: isDesktop ? 30 : 20,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onViewAll != null)
                    const SizedBox(width: LayoutConstants.spacingXs),
                  if (onViewAll != null)
                    CardsWrapper(
                      onTap: onViewAll!,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: LayoutConstants.spacingSm,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Text(
                              l10n.viewAll,
                              textDirection: localeDirection,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 172,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop
                      ? LayoutConstants.dashboardContentPadding
                      : LayoutConstants.spacingMd,
                ),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Directionality(
                    textDirection: localeDirection,
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
