import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:animewitcher/core/utils/artwork_quality.dart';
import 'package:animewitcher/core/utils/episode_label.dart';
import 'package:animewitcher/core/utils/image_fallbacks.dart';
import 'package:animewitcher/core/utils/layout_constants.dart';
import 'package:animewitcher/features/details/presentation/widgets/episode_action_chip.dart';
import 'package:animewitcher/shared/widgets/thumbnail_error_placeholder.dart';

import '../download_episode_artwork.dart';
import '../downloads_provider.dart';

/// Episode-row presentation for the Completed downloads tab.
///
/// It intentionally mirrors the details-page EpisodeCard: 16:9 still, episode
/// number/title, summary, the same surface/border/radii and the same compact
/// action chip. Download/comment actions are replaced by one centered delete
/// action because this row represents an already-downloaded local file.
class CompletedDownloadEpisodeCard extends StatefulWidget {
  const CompletedDownloadEpisodeCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadItem item;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  State<CompletedDownloadEpisodeCard> createState() =>
      _CompletedDownloadEpisodeCardState();
}

class _CompletedDownloadEpisodeCardState
    extends State<CompletedDownloadEpisodeCard> {
  late Future<File?> _artwork;

  @override
  void initState() {
    super.initState();
    _artwork = _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant CompletedDownloadEpisodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.episode?.posterUrl != widget.item.episode?.posterUrl) {
      _artwork = _loadArtwork();
    }
  }

  Future<File?> _loadArtwork() => ensureDownloadedEpisodeArtwork(
    taskId: widget.item.id,
    episode: widget.item.episode,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episode = widget.item.episode;
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final episodeTitle = episode == null ? '' : realEpisodeTitle(episode.name);
    final episodeNumberLabel = episode == null
        ? widget.item.item.title
        : formatEpisodePrimaryLabel(
            episode: episode.episode,
            isArabic: isArabic,
            isFinal: episode.isFinal,
            serverName: episode.serverName,
          );
    final description = episode?.description?.trim() ?? '';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: InkWell(
        onTap: widget.onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.1 : 0.5,
              ),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(LayoutConstants.spacingSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildThumbnail(context),
              const SizedBox(width: LayoutConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (episodeNumberLabel.isNotEmpty)
                      Text(
                        episodeNumberLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (episodeTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        episodeTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.72,
                          ),
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: LayoutConstants.spacingSm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: LayoutConstants.spacingXs),
              Align(
                alignment: Alignment.center,
                child: EpisodeActionChip(
                  tooltip: isArabic ? 'حذف الحلقة' : 'Delete episode',
                  icon: Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final episode = widget.item.episode;
    final episodePosterUrl = AppImageFallbacks.optional(episode?.posterUrl);
    final fallbackUrl =
        episodePosterUrl ??
        AppImageFallbacks.episode(
          bannerUrl: widget.item.item.bannerUrl,
          posterUrl: widget.item.item.posterUrl,
          label: widget.item.item.title,
        );
    final placeholderColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 140,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: FutureBuilder<File?>(
            future: _artwork,
            builder: (context, snapshot) {
              final local = snapshot.data;
              if (local != null) {
                return ArtworkDecode(
                  paintedWidth: 140,
                  builder: (context, decodeWidth) => Image.file(
                    local,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: decodeWidth,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => _networkThumbnail(
                      fallbackUrl,
                      episodePosterUrl,
                      placeholderColor,
                    ),
                  ),
                );
              }
              return _networkThumbnail(
                fallbackUrl,
                episodePosterUrl,
                placeholderColor,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _networkThumbnail(
    String? imageUrl,
    String? episodePosterUrl,
    Color placeholderColor,
  ) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const ThumbnailErrorPlaceholder();
    }
    return ArtworkDecode(
      paintedWidth: 140,
      builder: (context, decodeWidth) => CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        placeholder: (_, _) => ColoredBox(color: placeholderColor),
        errorWidget: (_, _, _) => episodePosterUrl != null
            ? ColoredBox(color: placeholderColor)
            : const ThumbnailErrorPlaceholder(),
      ),
    );
  }
}
