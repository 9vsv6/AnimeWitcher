import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/localized_text.dart';
import '../../../../shared/widgets/fallback_poster_image.dart';
import '../../../../shared/widgets/multimedia_card.dart';
import '../../../../shared/widgets/paged_rail.dart';
import '../../../../shared/widgets/poster_plate.dart';

/// What the search tab shows before anything is typed: a random pick, the
/// searches made last, this week's top ten and the saved shows not yet
/// started. The rankings as rows are on the home page.
class SearchStartPage extends StatelessWidget {
  const SearchStartPage({
    super.key,
    required this.recents,
    required this.onRecent,
    required this.onRemoveRecent,
    required this.onClearRecents,
    required this.onOpen,
    this.onSurprise,
    this.surprising = false,
    this.topTen = const <MultimediaItem>[],
    this.notStarted = const <MultimediaItem>[],
    this.topPadding = 0,
  });

  final List<String> recents;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecents;
  final ValueChanged<MultimediaItem> onOpen;

  /// Opens a random well-rated anime; no button without it.
  final VoidCallback? onSurprise;

  /// A random pick is being fetched.
  final bool surprising;

  /// The ten most popular airing anime this week, shown numbered.
  final List<MultimediaItem> topTen;

  /// Saved to the library but not watched yet.
  final List<MultimediaItem> notStarted;

  /// Room left above for the floating search bar.
  final double topPadding;

  bool get hasAnything =>
      onSurprise != null ||
      topTen.isNotEmpty ||
      notStarted.isNotEmpty ||
      recents.isNotEmpty;

  Widget _heading(BuildContext context, double side, String text) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(side, 22, side, 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  /// "Surprise me": a random well-rated anime.
  Widget _surpriseButton(BuildContext context) {
    final onSurprise = this.onSurprise;
    if (onSurprise == null) return const SizedBox.shrink();
    return FilledButton.tonalIcon(
      key: const ValueKey<String>('search-surprise'),
      onPressed: surprising ? null : onSurprise,
      icon: surprising
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.casino_rounded),
      label: Text(
        appText(context, english: 'Surprise me', arabic: 'اقترح لي أنمي'),
      ),
    );
  }

  Widget _recentsHeading(BuildContext context, double side) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(side, 18, side - 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              appText(
                context,
                english: 'Recent',
                arabic: 'عمليات البحث الأخيرة',
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onClearRecents,
            child: Text(appText(context, english: 'Clear', arabic: 'مسح')),
          ),
        ],
      ),
    );
  }

  Widget _recentChips(BuildContext context, {WrapAlignment? alignment}) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: alignment ?? WrapAlignment.start,
      children: [
        for (final recent in recents)
          InputChip(
            key: ValueKey<String>('search-recent-$recent'),
            label: Text(recent),
            onPressed: () => onRecent(recent),
            onDeleted: () => onRemoveRecent(recent),
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            side: BorderSide.none,
            backgroundColor: colors.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = MultimediaCardLayout.catalogGridHorizontalPadding(context) + 4;
    return ListView(
      key: const ValueKey<String>('search-start-page'),
      padding: EdgeInsets.only(top: topPadding, bottom: 120),
      children: [
        if (onSurprise != null)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(side, 8, side - 8, 0),
            child: Row(children: [const Spacer(), _surpriseButton(context)]),
          ),
        // What was searched last, right under the search bar.
        if (recents.isNotEmpty) ...[
          _recentsHeading(context, side),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: _recentChips(context),
          ),
        ],
        if (topTen.isNotEmpty) ...[
          _heading(
            context,
            side,
            appText(
              context,
              english: 'Top 10 this week',
              arabic: 'الأكثر رواجًا هذا الأسبوع',
            ),
          ),
          // The app's rail: dragged with the mouse and carried by the
          // wheel, so the last of the ten can be reached on a desktop.
          SizedBox(
            height: 196,
            child: PagedRail(
              key: const ValueKey<String>('search-top-ten'),
              itemExtent: 216,
              padding: EdgeInsets.symmetric(horizontal: side - 4),
              itemCount: topTen.length.clamp(0, 10),
              itemBuilder: (context, index) => _RankedPoster(
                rank: index + 1,
                item: topTen[index],
                onOpen: onOpen,
              ),
            ),
          ),
        ],
        if (notStarted.isNotEmpty) ...[
          _heading(
            context,
            side,
            appText(
              context,
              english: 'In your list, not started',
              arabic: 'في قائمتك ولم تبدأه',
            ),
          ),
          SizedBox(
            height: MultimediaCardLayout.listHeight(130, isPortrait: true),
            child: PagedRail(
              key: const ValueKey<String>('search-not-started'),
              itemExtent: 140,
              padding: EdgeInsets.symmetric(horizontal: side - 4),
              itemCount: notStarted.length,
              itemBuilder: (context, index) {
                final item = notStarted[index];
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: MultimediaCard.fromItem(
                    key: ValueKey<String>('search-not-started-${item.url}'),
                    item: item,
                    heroTag: 'search_not_started_${item.url}',
                    onTap: () => onOpen(item),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// A poster with its rank beside it in large outlined numerals, as the
/// numbered rows of streaming apps show them.
class _RankedPoster extends StatelessWidget {
  const _RankedPoster({
    required this.rank,
    required this.item,
    required this.onOpen,
  });

  final int rank;
  final MultimediaItem item;
  final ValueChanged<MultimediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const posterWidth = 124.0;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: InkWell(
        key: ValueKey<String>('search-top-ten-$rank'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpen(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 76,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.bottomEnd,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 110,
                    height: 0.9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -6,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 3
                      ..color = colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: posterWidth,
                height: posterWidth * 1.45,
                child: FallbackPosterImage(
                  imageUrl: item.posterUrl,
                  malId: item.artworkLookupMalId,
                  title: item.artworkLookupTitle,
                  memCacheWidth: 320,
                  placeholder: (_) => PosterPlate(seed: item.title),
                  errorWidget: (_) => PosterPlate(seed: item.title),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
