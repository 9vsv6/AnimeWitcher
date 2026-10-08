import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/artwork_quality.dart';
import '../../../../core/account/animewitcher_comment_models.dart';
import '../../../comments/presentation/animewitcher_comments_screen.dart';
import '../../../../shared/widgets/taskbar_visibility.dart';

class NewsCard extends StatelessWidget {
  const NewsCard({
    super.key,
    required this.item,
    this.compact = true,
    this.expandToFill = false,
    this.onOpen,
    this.onAnimeTap,
  });

  final NewsItem item;
  final bool compact;
  final bool expandToFill;
  final VoidCallback? onOpen;
  final VoidCallback? onAnimeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = this.compact;
    final expandToFill = this.expandToFill;
    final width = compact ? 200.0 : double.infinity;
    final imageHeight = compact ? 100.0 : 210.0;

    final image = Stack(
      fit: StackFit.expand,
      children: [
        _buildImage(context),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                  stops: const [0.42, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: compact ? 7 : 10,
          bottom: compact ? 6 : 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.hasAnimeLink) ...[
                _NewsActionIcon(
                  icon: Icons.link_rounded,
                  onTap: onAnimeTap,
                  size: compact ? 20 : 28,
                ),
                SizedBox(width: compact ? 7 : 10),
              ],
              _NewsActionIcon(
                icon: Icons.chat_bubble_outline_rounded,
                onTap: () {
                  final target = animeWitcherNewsCommentTarget(item);
                  pushOverTaskbar<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AnimeWitcherCommentsScreen(target: target),
                    ),
                  );
                },
                size: compact ? 20 : 28,
              ),
            ],
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 3,
        color: colors.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 8 : 5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            mainAxisSize: expandToFill ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expandToFill)
                Expanded(child: image)
              else
                SizedBox(height: imageHeight, child: image),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 12,
                  compact ? 7 : 9,
                  compact ? 10 : 12,
                  compact ? 3 : 5,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    item.title,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: compact ? 12 : 15,
                      height: 1.25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 14,
                  0,
                  compact ? 12 : 14,
                  compact ? 8 : 10,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    _newsTimeAgo(context, item.publishedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: compact ? 10 : 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = item.imageUrl.trim();
    if (url.isEmpty) return _imageFallback(colors);

    return ArtworkDecode(
      paintedWidth: compact ? 200 : MediaQuery.sizeOf(context).width,
      builder: (BuildContext context, int? decodeWidth) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _imageFallback(colors),
        errorWidget: (context, url, error) => _imageFallback(colors),
      ),
    );
  }

  Widget _imageFallback(ColorScheme colors) {
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.article_outlined,
          color: colors.onSurfaceVariant.withValues(alpha: 0.55),
          size: compact ? 30 : 42,
        ),
      ),
    );
  }
}

/// Opens the comments on [item].
void openNewsComments(BuildContext context, NewsItem item) {
  final target = animeWitcherNewsCommentTarget(item);
  pushOverTaskbar<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AnimeWitcherCommentsScreen(target: target),
    ),
  );
}

/// The news picture, or an article icon while it loads or when it fails.
class NewsImage extends StatelessWidget {
  const NewsImage({super.key, required this.item, required this.paintedWidth});

  final NewsItem item;
  final double paintedWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.article_outlined,
          color: colors.onSurfaceVariant.withValues(alpha: 0.55),
          size: 36,
        ),
      ),
    );
    final url = item.imageUrl.trim();
    if (url.isEmpty) return fallback;
    return ArtworkDecode(
      paintedWidth: paintedWidth,
      builder: (BuildContext context, int? decodeWidth) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}

/// The comments and, when the story is about one, the anime: small icons
/// on a dark disc so they read over any picture.
class _NewsActions extends StatelessWidget {
  const _NewsActions({required this.item, this.onAnimeTap});

  final NewsItem item;
  final VoidCallback? onAnimeTap;

  @override
  Widget build(BuildContext context) {
    Widget disc(IconData icon, String tooltip, VoidCallback? onTap) => Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.hasAnimeLink && onAnimeTap != null) ...[
          disc(
            Icons.link_rounded,
            arabic ? 'فتح الأنمي' : 'Open anime',
            onAnimeTap,
          ),
          const SizedBox(width: 6),
        ],
        disc(
          Icons.chat_bubble_outline_rounded,
          arabic ? 'التعليقات' : 'Comments',
          () => openNewsComments(context, item),
        ),
      ],
    );
  }
}

/// A lead story in the magazine layout: the picture fills the tile and the
/// title sits over its darkened lower part.
class NewsFeatureTile extends StatelessWidget {
  const NewsFeatureTile({
    super.key,
    required this.item,
    this.large = false,
    this.onOpen,
    this.onAnimeTap,
  });

  final NewsItem item;

  /// The top story: a bigger title, three lines of it.
  final bool large;
  final VoidCallback? onOpen;
  final VoidCallback? onAnimeTap;

  @override
  Widget build(BuildContext context) {
    final time = newsTimeAgo(context, item.publishedAt);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.black,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) =>
                    NewsImage(item: item, paintedWidth: constraints.maxWidth),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6000000)],
                      stops: [0.35, 1],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 10,
                end: 10,
                child: _NewsActions(item: item, onAnimeTap: onAnimeTap),
              ),
              PositionedDirectional(
                start: large ? 18 : 12,
                end: large ? 18 : 12,
                bottom: large ? 16 : 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: large ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: large ? 20 : 14,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: large ? 12.5 : 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A story in the magazine grid: the picture, then the title and time.
class NewsGridTile extends StatelessWidget {
  const NewsGridTile({
    super.key,
    required this.item,
    this.onOpen,
    this.onAnimeTap,
  });

  final NewsItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onAnimeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = newsTimeAgo(context, item.publishedAt);
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => NewsImage(
                      item: item,
                      paintedWidth: constraints.maxWidth,
                    ),
                  ),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: _NewsActions(item: item, onAnimeTap: onAnimeTap),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
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

class _NewsActionIcon extends StatelessWidget {
  const _NewsActionIcon({
    required this.icon,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: size,
        color: colors.onSurface.withValues(alpha: 0.9),
      ),
    );
  }
}

String _newsTimeAgo(BuildContext context, DateTime? date) =>
    newsTimeAgo(context, date);

/// How long ago [date] was ("منذ 4 ساعة"), in the app's language.
String newsTimeAgo(BuildContext context, DateTime? date) {
  if (date == null) return '';
  final difference = DateTime.now().difference(date);
  final elapsed = difference.isNegative ? Duration.zero : difference;
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';

  if (elapsed.inMinutes < 1) return isArabic ? 'الآن' : 'just now';
  if (elapsed.inHours < 1) {
    final value = elapsed.inMinutes;
    return isArabic
        ? 'منذ ' + (value == 1 ? 'دقيقة' : value.toString() + ' دقيقة')
        : value.toString() + (value == 1 ? ' minute ago' : ' minutes ago');
  }
  if (elapsed.inDays < 1) {
    final value = elapsed.inHours;
    return isArabic
        ? 'منذ ' + (value == 1 ? 'ساعة' : value.toString() + ' ساعة')
        : value.toString() + (value == 1 ? ' hour ago' : ' hours ago');
  }

  final value = elapsed.inDays;
  return isArabic
      ? 'منذ ' + (value == 1 ? 'يوم' : value.toString() + ' يوم')
      : value.toString() + (value == 1 ? ' day ago' : ' days ago');
}
