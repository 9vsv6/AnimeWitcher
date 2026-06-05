import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

import 'package:skystream/shared/widgets/cards_wrapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../shared/widgets/loading_dialog.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/core/services/notification_service.dart';

class ContinueWatchingCard extends ConsumerStatefulWidget {
  final HistoryItem historyItem;
  final double width;
  final bool isLarge;

  const ContinueWatchingCard({
    super.key,
    required this.historyItem,
    this.width = 280,
    this.isLarge = false,
  });

  static String _normalizeMatchKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static MultimediaItem? _pickBestLiveMatch(
    Iterable<MultimediaItem> candidates,
    MultimediaItem target,
  ) {
    final normalizedTarget = _normalizeMatchKey(target.title);
    if (normalizedTarget.isEmpty) return null;

    final exactTitleMatches = candidates.where(
      (candidate) =>
          candidate.contentType == MultimediaContentType.livestream &&
          _normalizeMatchKey(candidate.title) == normalizedTarget,
    );

    if (target.posterUrl.isNotEmpty) {
      final posterMatch = exactTitleMatches.firstWhereOrNull(
        (candidate) => candidate.posterUrl == target.posterUrl,
      );
      if (posterMatch != null) return posterMatch;
    }

    return exactTitleMatches.firstOrNull;
  }

  @override
  ConsumerState<ContinueWatchingCard> createState() =>
      _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends ConsumerState<ContinueWatchingCard> {
  bool _isHovered = false;

  Future<MultimediaItem?> _resolveFreshLiveItem(
    WidgetRef ref,
    MultimediaItem item,
  ) async {
    final providerId = item.provider;
    if (providerId == null || providerId.isEmpty) return null;

    final manager = ref.read(extensionManagerProvider.notifier);
    final provider = manager.getAllProviders().firstWhereOrNull(
      (p) => p.packageName == providerId || p.name == providerId,
    );
    if (provider == null) return null;

    try {
      final results = await provider.search(item.title);
      final match = ContinueWatchingCard._pickBestLiveMatch(results, item);
      if (match != null) {
        return match.copyWith(provider: provider.packageName);
      }
    } catch (_) {}

    try {
      final homeSections = await provider.getHome();
      final flattened = homeSections.values.expand((items) => items);
      final match = ContinueWatchingCard._pickBestLiveMatch(flattened, item);
      if (match != null) {
        return match.copyWith(provider: provider.packageName);
      }
    } catch (_) {}

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.historyItem.item;
    final double progress = (widget.historyItem.duration > 0)
        ? (widget.historyItem.position / widget.historyItem.duration).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final int percentage = (progress * 100).toInt();

    final providers = ref.watch(extensionManagerProvider);
    final providerObj = (item.provider != null)
        ? providers.where((p) => p.packageName == item.provider).firstOrNull
        : null;
    final providerName = providerObj?.name ?? item.provider;

    final bannerUrl = AppImageFallbacks.poster(
      item.backdropImageUrl,
      label: item.title,
    );
    final isLivestream = item.contentType == MultimediaContentType.livestream;
    final isSeries = item.contentType == MultimediaContentType.series;

    final scrimColors = [
      Colors.transparent,
      Colors.black.withValues(alpha: 0.05),
      Colors.black.withValues(alpha: 0.55),
      Colors.black.withValues(alpha: _isHovered ? 0.90 : 0.82),
    ];

    return CardsWrapper(
      onTap: () async {
        if (isLivestream) {
          bool dialogDismissed = false;
          bool canceled = false;
          unawaited(
            LoadingDialog.show(
              context,
              message: AppLocalizations.of(context)!.refreshingLiveStream,
              onCancel: () {
                canceled = true;
                dialogDismissed = true;
              },
            ),
          );
          final refreshedItem = await _resolveFreshLiveItem(ref, item);
          if (!context.mounted || canceled) return;

          if (!dialogDismissed) {
            Navigator.of(context, rootNavigator: true).pop();
            dialogDismissed = true;
          }

          final liveItem = refreshedItem ?? item;
          if (!context.mounted || canceled) return;

          unawaited(
            PlayerRoute(
              $extra: PlayerRouteExtra(item: liveItem, videoUrl: liveItem.url),
            ).push<void>(context),
          );
          unawaited(
            ref.read(watchHistoryProvider.notifier).removeFromHistory(item.url),
          );
          return;
        }

        unawaited(
          DetailsRoute(
            $extra: DetailsRouteExtra(item: item, autoPlay: true),
          ).push<void>(context),
        );
      },
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(AppLocalizations.of(context)!.viewDetails),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(
                      DetailsRoute(
                        $extra: DetailsRouteExtra(item: item),
                      ).push<void>(context),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    AppLocalizations.of(context)!.removeFromHistory,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    ref
                        .read(watchHistoryProvider.notifier)
                        .removeFromHistory(item.url);
                    Navigator.pop(context);
                    ref
                        .read(notificationServiceProvider)
                        .showSuccess(
                          AppLocalizations.of(
                            context,
                          )!.removedFromHistory(item.title),
                        );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(AppLocalizations.of(context)!.cancel),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: SizedBox(
          width: widget.width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Banner background
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: bannerUrl != null
                        ? CachedNetworkImage(
                            imageUrl: bannerUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          )
                        : null,
                  ),
                ),

                // Gradient scrim
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: scrimColors,
                          stops: const [0.0, 0.3, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Play button overlay (centre)
                if (!isLivestream)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: AnimatedScale(
                          scale: _isHovered ? 1.0 : 0.85,
                          duration: const Duration(milliseconds: 200),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Bottom info + progress section
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: widget.isLarge ? 14 : 13,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(
                                      alpha: _isHovered ? 0.6 : 0.4,
                                    ),
                                    blurRadius: _isHovered ? 6 : 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Badges
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (item.provider != null &&
                                    item.provider!.isNotEmpty)
                                  _buildBadge(
                                    providerName!,
                                    Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                if (!isLivestream)
                                  _buildBadge(
                                    item.contentType.name.toUpperCase(),
                                    Colors.white.withValues(alpha: 0.1),
                                    Colors.white60,
                                  ),
                              ],
                            ),
                            // Series episode info
                            if (isSeries &&
                                widget.historyItem.season != null &&
                                widget.historyItem.episode != null &&
                                (widget.historyItem.season! > 0 ||
                                    widget.historyItem.episode! > 0)) ...[
                              const SizedBox(height: 4),
                              Text(
                                "S${widget.historyItem.season} E${widget.historyItem.episode}${widget.historyItem.episodeTitle != null && widget.historyItem.episodeTitle!.isNotEmpty && !widget.historyItem.episodeTitle!.startsWith("Episode") ? " - ${widget.historyItem.episodeTitle}" : ""}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            // Livestream indicator
                            if (isLivestream) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    AppLocalizations.of(context)!.live,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Spacer(),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: Colors.white.withValues(
                                      alpha: _isHovered ? 0.7 : 0.5,
                                    ),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  child: Text('$percentage%'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Progress bar
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        height: _isHovered ? 4 : 3,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Close button
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      focusNode: FocusNode(
                        canRequestFocus: false,
                        skipTraversal: true,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        ref
                            .read(watchHistoryProvider.notifier)
                            .removeFromHistory(item.url);
                        ref
                            .read(notificationServiceProvider)
                            .showSuccess(
                              AppLocalizations.of(
                                context,
                              )!.removedFromHistory(item.title),
                            );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: textColor,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
