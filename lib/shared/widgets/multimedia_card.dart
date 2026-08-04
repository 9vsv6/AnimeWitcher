import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/responsive_breakpoints.dart';
import '../../features/settings/presentation/general_settings_provider.dart';
import 'cards_wrapper.dart';
import 'shimmer_placeholder.dart';
import 'thumbnail_error_placeholder.dart';

class MultimediaCard extends ConsumerWidget {
  final String? imageUrl;
  final String title;
  final VoidCallback onTap;
  final String heroTag;
  final bool isPortrait;
  final FocusNode? focusNode;

  /// Fully formatted text supplied by the provider.
  ///
  /// This widget displays the string unchanged.
  final String? episodeBadge;

  const MultimediaCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    required this.heroTag,
    this.isPortrait = true,
    this.focusNode,
    this.episodeBadge,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = context.isDesktop;
    final cardWidth = isDesktop
        ? (isPortrait ? 200.0 : 300.0)
        : (isPortrait ? 130.0 : 200.0);

    final titlePosition = ref.watch(
      generalSettingsProvider.select((s) => s.titlePosition),
    );
    final isInside = titlePosition == 'inside';
    final normalizedEpisodeBadge = episodeBadge?.trim();
    final badgeText =
        normalizedEpisodeBadge == null || normalizedEpisodeBadge.isEmpty
        ? null
        : normalizedEpisodeBadge;

    final imageWidget = Hero(
      tag: heroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageUrl ?? '',
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (context, url) => ShimmerPlaceholder(borderRadius: 12),
          errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(label: title),
        ),
      ),
    );

    final titleTextStyle = TextStyle(
      color: isInside
          ? Colors.white
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      fontSize: isDesktop ? 22 : 14,
      fontWeight: FontWeight.w500,
      shadows: isInside
          ? [
              const Shadow(
                color: Colors.black87,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );

    return RepaintBoundary(
      child: CardsWrapper(
        onTap: onTap,
        focusNode: focusNode,
        scaleFactor: 1.05,
        child: SizedBox(
          width: cardWidth,
          child: isInside
              ? _buildInsideMode(
                  context,
                  imageWidget,
                  titleTextStyle,
                  badgeText,
                )
              : _buildBelowMode(
                  context,
                  imageWidget,
                  titleTextStyle,
                  badgeText,
                ),
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

  Widget _buildBelowMode(
    BuildContext context,
    Widget imageWidget,
    TextStyle titleTextStyle,
    String? badgeText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              if (badgeText != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _buildEpisodeBadge(context, badgeText),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleTextStyle,
        ),
      ],
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
