import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'dart:async';

import '../../../shared/widgets/custom_widgets.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../core/router/app_router.dart';
import 'widgets/settings_widgets.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import 'package:flutter/foundation.dart';

class DeveloperOptionsScreen extends ConsumerStatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  ConsumerState<DeveloperOptionsScreen> createState() =>
      _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState
    extends ConsumerState<DeveloperOptionsScreen> {
  @override

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceProfileProvider);

    final l10n = AppLocalizations.of(context)!;
    final scaffold = Scaffold(
      appBar: AppBar(title: Text(l10n.developerOptions)),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          SettingsGroup(
            title: l10n.debugTools,
            children: [
              SettingsTile(
                icon: Icons.video_file_rounded,
                title: l10n.playLocalVideo,
                subtitle: l10n.playLocalVideoSubtitle,
                onTap: () => _pickLocalVideo(context),
              ),
              SettingsTile(
                icon: Icons.link_rounded,
                title: l10n.streamUrl,
                subtitle: l10n.streamUrlSubtitle,
                onTap: () => _showStreamUrlDialog(
                  context,
                  deviceAsync.asData?.value.isTv ?? false,
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.diagnostics,
            children: [
              SettingsTile(
                icon: Icons.bug_report_rounded,
                title: l10n.viewLogs,
                subtitle: l10n.viewLogsSubtitle,
                isLast: true,
                onTap: () {
                  unawaited(const AppLogsRoute().push<void>(context));
                },
              ),
            ],
          ),
        ],
      ),
    );

    return scaffold;
  }


  Future<void> _pickLocalVideo(BuildContext context) async {
    final result = await FilePicker.pickFiles(type: FileType.video);

    if (result != null && result.files.single.path != null && context.mounted) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      unawaited(
        PlayerRoute(
          $extra: PlayerRouteExtra(
            item: MultimediaItem(
              title: name,
              url: path,
              posterUrl: '',
              provider: AppLocalizations.of(context)!.local,
              episodes: [Episode(name: name, url: path, posterUrl: '')],
            ),
            videoUrl: path,
          ),
        ).push<void>(context),
      );
    }
  }

  void _showStreamUrlDialog(BuildContext context, bool isTv) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.streamUrl),
        content: CustomTextField(
          controller: controller,
          hintText: l10n.enterVideoUrlHint,
          autofocus: false, // Start focus on Play button
          textInputAction: TextInputAction.done,
        ),
        actions: [
          CustomButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CustomButton(
            autofocus: true,
            isPrimary: true,

            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                String title = l10n.networkStream;
                try {
                  final uri = Uri.parse(url);
                  if (uri.pathSegments.isNotEmpty) {
                    title = uri.pathSegments.last;
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('DeveloperOptionsScreen: URI parse error: $e');
                  }
                }

                Navigator.pop(context);
                PlayerRoute(
                  $extra: PlayerRouteExtra(
                    item: MultimediaItem(
                      title: title,
                      url: url, // Unique URL for history
                      posterUrl: '',
                      provider: l10n.remote,
                      episodes: [Episode(name: title, url: url, posterUrl: '')],
                    ),
                    videoUrl: url,
                  ),
                ).push<void>(context);
              }
            },
            child: Text(l10n.play),
          ),
        ],
      ),
    );
  }

}
