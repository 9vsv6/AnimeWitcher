import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/image_quality.dart';
import '../../core/utils/responsive_breakpoints.dart';
import 'cards_wrapper.dart';
import 'shimmer_placeholder.dart';
import 'thumbnail_error_placeholder.dart';

class MultimediaCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String heroTag;
  final bool isPortrait;
  final FocusNode? focusNode;
  final bool compact;

  /// Shows a stable card surface while the poster is still loading.
  /// Search results disable the shimmer so the card is visible immediately.
  final bool showImageLoadingShimmer;

  /// Fully formatted text supplied by the provider.
  ///
  /// This widget displays the string unchanged.
  final String? episodeBadge;

  const MultimediaCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.onLongPress,
    required this.heroTag,
    this.isPortrait = true,
    this.focusNode,
    this.compact = false,
    this.episodeBadge,
    this.showImageLoadingShimmer = true,
  });

  @override
  Widget build(BuildContext context) {
    final isHandsetLandscape = context.isHandsetLandscape;
    final isDesktopLandscape = context.isDesktopLandscape;
    final isDesktop = context.isDesktop;
    final effectiveCompact = compact || isDesktopLandscape;
    final cardWidth = isHandsetLandscape
        ? ResponsiveBreakpoints.handsetLandscapeAnimeCardWidth(context)
        : isDesktopLandscape
        ? ResponsiveBreakpoints.desktopLandscapeAnimeCardWidth(context)
        : isDesktop
        ? (isPortrait ? 200.0 : 300.0)
        : (isPortrait ? 130.0 : 200.0);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    final normalizedEpisodeBadge = episodeBadge?.trim();
    final badgeText =
        normalizedEpisodeBadge == null || normalizedEpisodeBadge.isEmpty
        ? null
        : normalizedEpisodeBadge;

    final normalizedImageUrl = imageUrl?.trim();
    final hasImageUrl =
        normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;
    final imageWidget = Hero(
      tag: heroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: hasImageUrl
            // Decode for the box the poster really fills. Grid cells and
            // horizontal lists override [cardWidth], so sizing from that
            // nominal value decoded posters smaller than they are painted,
            // which is what made cards look soft next to the details page.
            ? LayoutBuilder(
                builder: (context, constraints) => _buildPoster(
                  context,
                  normalizedImageUrl,
                  posterDecodeWidth(
                    paintedWidth: constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : cardWidth,
                    devicePixelRatio: devicePixelRatio,
                  ),
                ),
              )
            : ThumbnailErrorPlaceholder(label: title),
      ),
    );

    final titleTextStyle = TextStyle(
      color: Colors.white,
      fontSize: effectiveCompact ? 14 : (isDesktop ? 22 : 14),
      fontWeight: FontWeight.w500,
      shadows: const [
        Shadow(
          color: Colors.black87,
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    );

    return RepaintBoundary(
      child: CardsWrapper(
        onTap: onTap,
        onLongPress: onLongPress,
        focusNode: focusNode,
        scaleFactor: 1.05,
        child: SizedBox(
          width: cardWidth,
          child: _buildInsideMode(
            context,
            imageWidget,
            titleTextStyle,
            badgeText,
          ),
        ),
      ),
    );
  }

  /// Poster loader that asks for the largest artwork and, if that variant is
  /// missing on the CDN, retries the smaller one before giving up.
  Widget _buildPoster(
    BuildContext context,
    String imageUrl,
    int memoryCacheWidth, {
    bool allowFallback = true,
  }) {
    final fallbackUrl = allowFallback
        ? fallbackQualityImageUrl(imageUrl)
        : null;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      memCacheWidth: memoryCacheWidth,
      placeholder: (context, url) => showImageLoadingShimmer
          ? ShimmerPlaceholder(borderRadius: 12)
          : _buildImageLoadingCard(context),
      errorWidget: (context, url, error) => fallbackUrl == null
          ? ThumbnailErrorPlaceholder(label: title)
          : _buildPoster(
              context,
              fallbackUrl,
              memoryCacheWidth,
              allowFallback: false,
            ),
      fadeOutDuration: Duration.zero,
      fadeInDuration: const Duration(milliseconds: 120),
      useOldImageOnUrlChange: true,
    );
  }

  Widget _buildImageLoadingCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surfaceContainerHighest,
            colors.surface,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 32,
          color: colors.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildEpisodeBadge(BuildContext context, String text) {
    // Episode badge UI v2: use the active theme and pin to the right.
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: colors.primaryContainer.withValues(alpha: 0.85),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.28),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInsideMode(
    BuildContext context,
    Widget imageWidget,
    TextStyle titleTextStyle,
    String? badgeText,
  ) {
    return Stack(
      children: [
        Positioned.fill(child: imageWidget),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.0, 1.0],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: titleTextStyle,
            ),
          ),
        ),
        if (badgeText != null)
          Positioned(
            right: 8,
            bottom: (titleTextStyle.fontSize ?? 14) + 30,
            child: _buildEpisodeBadge(context, badgeText),
          ),
      ],
    );
  }
}
