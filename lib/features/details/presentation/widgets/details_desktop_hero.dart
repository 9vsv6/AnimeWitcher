import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:animewitcher/shared/widgets/secondary_mouse_refresh_indicator.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/artwork_quality.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import 'premium_details_widgets.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import 'package:animewitcher/core/services/notification_service.dart';

/// Immersive desktop/TV hero for non-TMDB details.
///
/// Layout: full-page banner-as-background for the Details tab, with the
/// title and metadata sitting beside the poster like the handset header.
/// Play /
/// Resume action is intentionally omitted on desktop; on wide screens
/// playback is driven from the Episodes tab, matching the mobile app
/// pattern. [child] renders the rest of the Details tab below the hero row.
class DetailsDesktopHero extends ConsumerWidget {
  const DetailsDesktopHero({
    super.key,
    required this.displayItem,
    required this.details,
    required this.detailsState,
    required this.isMovie,
    required this.itemUrl,
    required this.child,
    required this.onRefresh,
    this.onPosterTap,
    // Kept for backwards compatibility with callers that still pass it,
    // but it's no longer used now that [DetailsActionButtons] is removed
    // from the desktop layout.
    this.baseItem,
  });

  /// The resolved item for display (details ?? widget.item).
  final MultimediaItem displayItem;

  /// Original item, retained as an optional hook. No longer used by the
  /// desktop hero now that the Play/Resume button is intentionally
  /// excluded from wide screens.
  final MultimediaItem? baseItem;

  /// Loaded details (nullable while loading).
  final MultimediaItem? details;

  /// Async state for loading/error indicators.
  final AsyncValue<MultimediaItem?> detailsState;

  final bool isMovie;
  final String itemUrl;

  /// Content rendered below the hero section (episodes, cast, etc.).
  final Widget child;

  /// Pull-to-refresh, matching Home and the other catalog lists.
  final Future<void> Function() onRefresh;

  /// Opens the fullscreen poster viewer at the largest available artwork.
  final VoidCallback? onPosterTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;

    final providedBannerUrl = AppImageFallbacks.optional(displayItem.bannerUrl);
    final posterUrl = AppImageFallbacks.poster(
      displayItem.posterUrl,
      label: displayItem.title,
    );
    final backdropUrl =
        AppImageFallbacks.banner(
          bannerUrl: displayItem.bannerUrl,
          posterUrl: displayItem.posterUrl,
          label: displayItem.title,
        ) ??
        '';

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Layer 1: Backdrop image with left-fade ShaderMask ──
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scaffoldColor,
                  scaffoldColor.withValues(alpha: 0.85),
                  scaffoldColor.withValues(alpha: 0.55),
                  scaffoldColor.withValues(alpha: 0.25),
                  scaffoldColor.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstOut,
            child: ArtworkDecode(
              paintedWidth: MediaQuery.sizeOf(context).width,
              builder: (BuildContext context, int? decodeWidth) =>
                  CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    memCacheWidth: decodeWidth,
                    filterQuality: FilterQuality.medium,
                    errorWidget: (_, _, _) {
                      if (providedBannerUrl != null &&
                          posterUrl != null &&
                          providedBannerUrl != posterUrl) {
                        return CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                          memCacheWidth: decodeWidth,
                          filterQuality: FilterQuality.medium,
                          errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                            label: displayItem.title,
                            isBackdrop: true,
                          ),
                        );
                      }
                      return ThumbnailErrorPlaceholder(
                        label: displayItem.title,
                        isBackdrop: true,
                      );
                    },
                  ),
            ),
          ),
        ),

        // ── Layer 2: Left-to-right gradient overlay ──
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scaffoldColor,
                  scaffoldColor.withValues(alpha: 0.85),
                  scaffoldColor.withValues(alpha: 0.55),
                  scaffoldColor.withValues(alpha: 0.25),
                  scaffoldColor.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
              ),
            ),
          ),
        ),

        // ── Layer 3: Bottom-to-top gradient (subtle — keeps banner visible
        //    across the entire page, with a faint darken near the top for
        //    text legibility). The banner is meant to read as the page's
        //    full-bleed background, not a fixed hero zone, so this layer
        //    fades over a much longer stretch than the previous variant.
        //    Cards & panels painted on top of the scroll content still read
        //    correctly thanks to their own opaque surfaces.
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  scaffoldColor.withValues(alpha: 0.35),
                  scaffoldColor.withValues(alpha: 0.30),
                  scaffoldColor.withValues(alpha: 0.25),
                  scaffoldColor.withValues(alpha: 0.20),
                  scaffoldColor.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.20, 0.40, 0.60, 0.80, 1.0],
              ),
            ),
          ),
        ),

        // ── Layer 4: Scrollable content ──
        Positioned.fill(
          child: SecondaryMouseRefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Poster on LEFT (mobile-style fixed-left anchor) +
                  //    compact title and metadata to the right of it.
                  //    Play/Resume ("آخر حلقة") action is intentionally
                  //    omitted on desktop per the desktop layout pass — the
                  //    user's media flow on wide screens is driven from
                  //    the episode grid below, mirroring the mobile app.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (posterUrl != null && posterUrl.isNotEmpty) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onPosterTap,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 200,
                                height: 300,
                                child: ArtworkDecode(
                                  paintedWidth: 200,
                                  builder:
                                      (
                                        BuildContext context,
                                        int? decodeWidth,
                                      ) => CachedNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: decodeWidth,
                                        filterQuality: FilterQuality.medium,
                                        placeholder: (_, _) => ColoredBox(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                        ),
                                        errorWidget: (_, _, _) =>
                                            ThumbnailErrorPlaceholder(
                                              label: displayItem.title,
                                            ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                        ],
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () => _copyAnimeTitle(context),
                                  child: displayItem.logoUrl != null
                                      ? ArtworkDecode(
                                          paintedWidth: 320,
                                          builder:
                                              (
                                                BuildContext context,
                                                int? decodeWidth,
                                              ) => CachedNetworkImage(
                                                imageUrl: displayItem.logoUrl!,
                                                height: 88,
                                                alignment: Alignment.centerLeft,
                                                fit: BoxFit.contain,
                                                memCacheWidth: decodeWidth,
                                                placeholder: (_, _) =>
                                                    _buildTitle(textColor),
                                                errorWidget: (_, _, _) =>
                                                    _buildTitle(textColor),
                                              ),
                                        )
                                      : _buildTitle(textColor),
                                ),
                                const SizedBox(height: 18),
                                MetadataBar(
                                  item: displayItem,
                                  isLoading: detailsState is AsyncLoading,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  // ── Content below hero (full width) ──
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyAnimeTitle(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: displayItem.title));
    await HapticFeedback.selectionClick();

    if (!context.mounted) {
      return;
    }

    notificationServiceOf(context).showSuccess(
      appText(context, english: 'Title copied', arabic: 'تم نسخ العنوان'),
    );
  }

  Widget _buildTitle(Color textColor) {
    return Text(
      displayItem.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontSize: 36,
        fontWeight: FontWeight.bold,
        height: 1.12,
      ),
    );
  }
}

