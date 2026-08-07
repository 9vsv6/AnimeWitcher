import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/services/download_service.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/loading_dialog.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/loading_indicator.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import 'package:skystream/core/utils/localized_text.dart';
import 'source_picker.dart';
part 'download_launcher.g.dart';

@Riverpod(keepAlive: true)
DownloadLauncher downloadLauncher(Ref ref) {
  return DownloadLauncher(ref);
}

class DownloadLauncher {
  final Ref _ref;

  DownloadLauncher(this._ref);

  Future<void> launch(
    BuildContext context,
    MultimediaItem item, {
    String? episodeUrl,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final resolveUrl = episodeUrl ?? item.url;
    if (resolveUrl.isEmpty) return;

    final manager = _ref.read(extensionManagerProvider.notifier);
    SkyStreamProvider? provider;
    if (item.provider != null) {
      try {
        final val = item.provider!;
        provider = manager.getAllProviders().firstWhere(
          (p) => p.packageName == val || p.name == val,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('DownloadLauncher.launch: $e');
      }
    }
    provider ??= _ref.read(activeProviderProvider);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix('No active provider'))),
      );
      return;
    }

    bool isCanceled = false;
    bool dialogDismissed = false;
    unawaited(
      LoadingDialog.show(
        context,
        message: l10n.resolving,
        onCancel: () {
          isCanceled = true;
          dialogDismissed = true;
        },
      ),
    );

    try {
      // Fetch only AnimeWitcher's source records here. Extraction happens
      // after the user chooses PD/MF2/ST/etc.
      final sources = await provider.loadStreamSources(resolveUrl);
      if (isCanceled || !context.mounted) return;
      if (!dialogDismissed) {
        Navigator.of(context).pop();
        dialogDismissed = true;
      }
      if (sources.isEmpty) {
        throw Exception('No download sources found for this item.');
      }

      final selected = await showStreamSourcePicker(
        context,
        sources,
        forDownload: true,
      );
      if (selected == null || !context.mounted) return;

      StreamResult stream = selected;
      if (selected.requiresResolution) {
        isCanceled = false;
        dialogDismissed = false;
        unawaited(
          LoadingDialog.show(
            context,
            message: l10n.resolving,
            onCancel: () {
              isCanceled = true;
              dialogDismissed = true;
            },
          ),
        );
        final resolved = await provider.loadStreams(selected.url);
        if (isCanceled || !context.mounted) return;
        if (!dialogDismissed) {
          Navigator.of(context).pop();
          dialogDismissed = true;
        }
        if (resolved.isEmpty) {
          throw Exception(
            Localizations.localeOf(context).languageCode == 'ar'
                ? 'تعذر استخراج رابط صالح من هذا المصدر.'
                : 'Could not extract a downloadable URL from this source.',
          );
        }
        stream = resolved.first;
      }

      await _verifyAndDownload(context, stream, item, resolveUrl);
    } catch (e) {
      if (!context.mounted) return;
      if (!isCanceled && !dialogDismissed) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
      );
    }
  }

  Future<void> _verifyAndDownload(
    BuildContext context,
    StreamResult stream,
    MultimediaItem item,
    String resolveUrl,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final downloadService = _ref.read(downloadServiceProvider);

    // 1. Show verification dialog
    // Use root navigator context if current context is unmounted
    final navContext = rootNavigatorKey.currentContext ?? context;

    bool isCanceled = false;
    unawaited(
      showDialog<void>(
        context: navContext,
        barrierDismissible: false, // Block UI interaction
        builder: (ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLoadingIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.verifyingSourceSize),
                ],
              ),
              actions: [
                CustomButton(
                  isPrimary: false,
                  onPressed: () {
                    isCanceled = true;
                    Navigator.of(ctx).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(l10n.cancel),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final metadata = await downloadService
        .getMetadata(stream.url, headers: stream.headers)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);

    if (!navContext.mounted) return;
    if (!isCanceled) {
      Navigator.of(navContext, rootNavigator: true).pop();
    } else {
      return; // Canceled, don't proceed
    }

    final finalContext = rootNavigatorKey.currentContext ?? navContext;

    if (metadata == null || metadata.size == null) {
      if (finalContext.mounted) {
        _showErrorDialog(
          finalContext,
          'This source doesn\'t support direct downloading or is currently unavailable. Please try another source.',
          stream,
          item,
          resolveUrl,
        );
      }
      return;
    }

    // 2. Show Confirmation Dialog
    if (finalContext.mounted) {
      unawaited(
        showDialog<void>(
          context: finalContext,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.confirmDownload),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.titleWithParam(item.title)),
                const SizedBox(height: 8),
                Text(l10n.sourceWithParam(stream.source)),
                const SizedBox(height: 8),
                Text(l10n.sizeWithParam(metadata.sizeString)),
                const SizedBox(height: 16),
                Text(l10n.fileSaveLocationNotification),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);

                  // Finalize path and filename
                  final episodeData = item.episodes?.firstWhereOrNull(
                    (e) => e.url == resolveUrl,
                  );
                  final saveDir = await downloadService.getDownloadPath(
                    item,
                    episode: episodeData,
                  );

                  final extension = _getFileExtension(
                    stream.url,
                    metadata.mimeType,
                  );
                  String filename;
                  if (episodeData != null &&
                      item.contentType != MultimediaContentType.movie) {
                    final sanitizedEpName = episodeData.name
                        .replaceAll(RegExp(r'[^\w\s-]'), '')
                        .trim();
                    filename =
                        "S${episodeData.season}-E${episodeData.episode} $sanitizedEpName$extension";
                  } else {
                    final sanitizedTitle = item.title
                        .replaceAll(RegExp(r'[^\w\s-]'), '')
                        .trim();
                    filename = "$sanitizedTitle$extension";
                  }

                  if (kDebugMode) {
                    debugPrint(
                      '[DownloadLauncher] Final Path: $saveDir/$filename',
                    );
                  }

                  final started = await downloadService.startDownload(
                    url: stream.url,
                    filename: filename,
                    directory: saveDir,
                    item: item,
                    episode: episodeData,
                    trackingUrl: resolveUrl,
                    headers: stream.headers,
                    totalBytes: metadata.size ?? -1,
                  );

                  if (!started && finalContext.mounted) {
                    ScaffoldMessenger.of(finalContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          appText(
                            finalContext,
                            english:
                                'Failed to start download. Check storage permissions.',
                            arabic:
                                'فشل بدء التنزيل. تحقق من أذونات التخزين.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: Text(l10n.downloadNow),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showErrorDialog(
    BuildContext context,
    String message,
    StreamResult stream,
    MultimediaItem item,
    String resolveUrl,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.downloadUnavailable),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              launch(
                context,
                item,
                episodeUrl: resolveUrl,
              ); // Go back to source picker
            },
            child: Text(l10n.selectAnotherSource),
          ),
        ],
      ),
    );
  }

  String _getFileExtension(String url, String? mimeType) {
    if (mimeType != null) {
      if (mimeType.contains('video/mp4')) return '.mp4';
      if (mimeType.contains('video/x-matroska')) return '.mkv';
      if (mimeType.contains('video/webm')) return '.webm';
    }

    final uri = Uri.tryParse(url);
    if (uri != null) {
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp4')) return '.mp4';
      if (path.endsWith('.mkv')) return '.mkv';
      if (path.endsWith('.webm')) return '.webm';
      if (path.endsWith('.avi')) return '.avi';
    }

    return '.mp4'; // Default
  }
}
