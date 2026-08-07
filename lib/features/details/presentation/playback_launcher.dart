import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/external_player_service.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/base_provider.dart';
import '../../settings/presentation/player_settings_provider.dart';
import 'package:collection/collection.dart';
import 'details_controller.dart';
import 'source_picker.dart';
import '../../../core/services/download_service.dart';
import '../../../shared/widgets/loading_dialog.dart';
import '../../../core/utils/app_utils.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../core/services/notification_service.dart';

part 'playback_launcher.g.dart';

@Riverpod(keepAlive: true)
PlaybackLauncher playbackLauncher(Ref ref) {
  return PlaybackLauncher(ref);
}

class PlaybackLauncher {
  final Ref _ref;

  PlaybackLauncher(this._ref);

  SkyStreamProvider? _resolveProvider(MultimediaItem item) {
    final manager = _ref.read(extensionManagerProvider.notifier);
    SkyStreamProvider? provider;
    if (item.provider != null) {
      try {
        final val = item.provider!;
        provider = manager.getAllProviders().firstWhere(
          (p) => p.packageName == val || p.name == val,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('PlaybackLauncher._resolveProvider: $e');
      }
    }
    return provider ?? _ref.read(activeProviderProvider);
  }

  Future<StreamResult?> _chooseSource(
    BuildContext context,
    SkyStreamProvider provider,
    String episodeDataUrl,
  ) async {
    bool isCanceled = false;
    bool dialogDismissed = false;
    unawaited(
      LoadingDialog.show(
        context,
        message: AppLocalizations.of(context)!.resolving,
        onCancel: () {
          isCanceled = true;
          dialogDismissed = true;
        },
      ),
    );

    try {
      final sources = await provider.loadStreamSources(episodeDataUrl);
      if (isCanceled || !context.mounted) return null;
      if (!dialogDismissed) {
        Navigator.of(context).pop();
        dialogDismissed = true;
      }
      if (sources.isEmpty) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'لم يتم العثور على مصادر تشغيل.'
                  : 'No playback sources found.',
            );
        return null;
      }
      return showStreamSourcePicker(context, sources, forDownload: false);
    } catch (e) {
      if (context.mounted && !isCanceled && !dialogDismissed) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              AppLocalizations.of(context)!.usingInternalPlayerError(e.toString()),
            );
      }
      return null;
    }
  }

  Future<StreamResult?> _resolveSelectedSource(
    BuildContext context,
    SkyStreamProvider provider,
    StreamResult source,
  ) async {
    if (!source.requiresResolution) return source;

    bool isCanceled = false;
    bool dialogDismissed = false;
    unawaited(
      LoadingDialog.show(
        context,
        message: AppLocalizations.of(context)!.resolving,
        onCancel: () {
          isCanceled = true;
          dialogDismissed = true;
        },
      ),
    );
    try {
      final streams = await provider.loadStreams(source.url);
      if (isCanceled || !context.mounted) return null;
      if (!dialogDismissed) {
        Navigator.of(context).pop();
        dialogDismissed = true;
      }
      if (streams.isEmpty) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'تعذر استخراج رابط صالح من هذا المصدر.'
                  : 'Could not extract a playable URL from this source.',
            );
        return null;
      }
      return streams.first;
    } catch (e) {
      if (context.mounted && !isCanceled && !dialogDismissed) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              AppLocalizations.of(context)!.usingInternalPlayerError(e.toString()),
            );
      }
      return null;
    }
  }

  Future<void> play(
    BuildContext context,
    String url, {
    required MultimediaItem baseItem,
    MultimediaItem? detailedItem,
    Episode? episode,
  }) async {
    final settings = await _ref.read(playerSettingsProvider.future);
    if (!context.mounted) return;

    final item = detailedItem ?? baseItem;
    final resolvedEpisode =
        episode ?? item.episodes?.firstWhereOrNull((e) => e.url == url);
    final downloadService = _ref.read(downloadServiceProvider);
    final localFile = await downloadService.getDownloadedFile(
      item,
      episode: resolvedEpisode,
    );
    if (!context.mounted) return;

    final localOrEpisodeUrl = AppUtils.normalizeUrl(localFile?.path ?? url);

    // Downloaded files are already playable and do not need a source list.
    if (AppUtils.isLocalFile(localOrEpisodeUrl)) {
      if (settings.preferredPlayer != null) {
        final stream = StreamResult(url: localOrEpisodeUrl, source: 'Local');
        await _launchStream(
          context,
          stream,
          item,
          localOrEpisodeUrl,
          settings.preferredPlayer!,
        );
      } else {
        await PlayerRoute(
          $extra: PlayerRouteExtra(
            item: item,
            videoUrl: localOrEpisodeUrl,
            episode: resolvedEpisode,
          ),
        ).push<void>(context);
      }
      return;
    }

    final provider = _resolveProvider(item);
    if (provider == null) {
      _ref
          .read(notificationServiceProvider)
          .showError(
            Localizations.localeOf(context).languageCode == 'ar'
                ? 'لم يتم العثور على مزود التشغيل.'
                : 'No playback provider found.',
          );
      return;
    }

    // AnimeWitcher source discovery is intentionally separate from extraction:
    // show PD/MF2/ST/etc. first, then resolve only the server the user chose.
    final selected = await _chooseSource(context, provider, localOrEpisodeUrl);
    if (selected == null || !context.mounted) return;

    if (settings.preferredPlayer != null) {
      if (baseItem.url.isNotEmpty) {
        _ref
            .read(detailsControllerProvider(baseItem.url).notifier)
            .setLaunching(true);
      }
      try {
        final resolved = await _resolveSelectedSource(context, provider, selected);
        if (resolved == null || !context.mounted) return;
        await _launchStream(
          context,
          resolved,
          item,
          selected.url,
          settings.preferredPlayer!,
        );
      } finally {
        if (baseItem.url.isNotEmpty) {
          _ref
              .read(detailsControllerProvider(baseItem.url).notifier)
              .setLaunching(false);
        }
      }
      return;
    }

    // For deferred sources, the opaque selected URL tells the provider to
    // extract exactly that one server inside the player loading screen.
    final selectedUrl = selected.requiresResolution
        ? selected.url
        : localOrEpisodeUrl;
    await PlayerRoute(
      $extra: PlayerRouteExtra(
        item: item,
        videoUrl: selectedUrl,
        episode: resolvedEpisode,
      ),
    ).push<void>(context);
  }

  Future<void> _launchStream(
    BuildContext context,
    StreamResult stream,
    MultimediaItem item,
    String fallbackVideoUrl,
    String playerId,
  ) async {
    final success = await ExternalPlayerService.instance.launch(
      stream.url,
      headers: stream.headers,
      playerId: playerId,
      title: item.title,
    );

    if (!success && context.mounted) {
      final playerName =
          ExternalPlayerService.instance.getPlayerById(playerId)?.displayName ??
          playerId;
      _ref
          .read(notificationServiceProvider)
          .showError(
            AppLocalizations.of(context)!.playerNotDetected(playerName),
          );
      unawaited(
        PlayerRoute(
          $extra: PlayerRouteExtra(item: item, videoUrl: fallbackVideoUrl),
        ).push<void>(context),
      );
    }
  }
}
