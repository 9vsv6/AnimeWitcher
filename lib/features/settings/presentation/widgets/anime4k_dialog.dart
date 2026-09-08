import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import '../../../../shared/widgets/glass_dialog.dart';
import '../../../player/data/anime4k.dart';
import '../../../player/data/anime4k_shader_library.dart';
import '../../../player/presentation/player_controller.dart';
import '../player_settings_provider.dart';

/// Picks an Anime4K pipeline, its network size, and the folder the shaders
/// live in.
///
/// The shaders are not shipped with the app — they are a separate download
/// from the Anime4K project — so the folder comes first here, and the modes
/// are shown against what that folder actually contains rather than as a list
/// of promises.
void showAnime4kDialog(BuildContext context, WidgetRef ref) {
  showGlassDialog<void>(
    context: context,
    builder: (context) => const _Anime4kDialog(),
  );
}

class _Anime4kDialog extends ConsumerStatefulWidget {
  const _Anime4kDialog();

  @override
  ConsumerState<_Anime4kDialog> createState() => _Anime4kDialogState();
}

class _Anime4kDialogState extends ConsumerState<_Anime4kDialog> {
  Anime4kPipeline? _pipeline;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshPipeline();
  }

  PlayerSettings get _settings =>
      ref.read(playerSettingsProvider).asData?.value ?? const PlayerSettings();

  /// Resolves the chosen mode against the folder so the dialog can say what
  /// will actually run, instead of leaving it to be discovered mid-episode.
  Future<void> _refreshPipeline() async {
    final settings = _settings;
    if (settings.anime4kShaderDirectory.trim().isEmpty) {
      if (mounted) setState(() => _pipeline = null);
      return;
    }
    setState(() => _checking = true);
    final pipeline = await ref
        .read(anime4kShaderLibraryProvider)
        .pipeline(
          mode: settings.anime4kMode == Anime4kMode.off
              ? Anime4kMode.a
              : settings.anime4kMode,
          quality: settings.anime4kQuality,
          directory: settings.anime4kShaderDirectory,
        );
    if (!mounted) return;
    setState(() {
      _pipeline = pipeline;
      _checking = false;
    });
  }

  Future<void> _chooseFolder() async {
    final chosen = await FilePicker.getDirectoryPath();
    if (chosen == null || !mounted) return;
    await ref
        .read(playerSettingsProvider.notifier)
        .setAnime4kShaderDirectory(chosen);
    if (!mounted) return;
    await _refreshPipeline();
    await _reapply();
  }

  /// Pushes the change onto whatever is playing, so a mode can be judged
  /// against the picture rather than on the next episode.
  Future<void> _reapply() async {
    try {
      await ref.read(playerControllerProvider.notifier).applyAnime4kShaders();
    } catch (_) {
      // Nothing is playing, which is the common case from the settings page.
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(
      playerSettingsProvider.select(
        (value) => value.asData?.value ?? const PlayerSettings(),
      ),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final folder = settings.anime4kShaderDirectory.trim();
    final hasFolder = folder.isNotEmpty;

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Anime4K'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText(
                  context,
                  english:
                      'Restores and upscales anime on the GPU while it '
                      'plays. Works with the built-in player only.',
                  arabic:
                      'يحسّن الصورة ويكبّرها على كرت الشاشة أثناء التشغيل. '
                      'يعمل مع المشغّل المدمج فقط.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // --- the folder ------------------------------------------------
              Text(
                appText(
                  context,
                  english: 'Shader folder',
                  arabic: 'مجلد الشيدرات',
                ),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                hasFolder
                    ? folder
                    : appText(
                        context,
                        english:
                            'Not chosen. Download the Anime4K GLSL shaders '
                            'and point here at the folder holding them.',
                        arabic:
                            'لم يُختَر بعد. نزّل ملفات Anime4K بصيغة GLSL '
                            'ثم اختر المجلد الذي يحويها.',
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _chooseFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(
                    hasFolder
                        ? appText(
                            context,
                            english: 'Change folder',
                            arabic: 'تغيير المجلد',
                          )
                        : appText(
                            context,
                            english: 'Choose folder',
                            arabic: 'اختيار المجلد',
                          ),
                  ),
                ),
              ),
              if (hasFolder) ...[
                const SizedBox(height: 8),
                _StatusLine(pipeline: _pipeline, checking: _checking),
              ],

              const Divider(height: 28),

              // --- the pipeline ----------------------------------------------
              Text(
                appText(context, english: 'Mode', arabic: 'النمط'),
                style: theme.textTheme.labelLarge,
              ),
              RadioGroup<Anime4kMode>(
                groupValue: settings.anime4kMode,
                onChanged: (value) async {
                  if (value == null) return;
                  await ref
                      .read(playerSettingsProvider.notifier)
                      .setAnime4kMode(value);
                  await _refreshPipeline();
                  await _reapply();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mode in Anime4kMode.values)
                      RadioListTile<Anime4kMode>(
                        value: mode,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          mode == Anime4kMode.off
                              ? appText(
                                  context,
                                  english: 'Off',
                                  arabic: 'إيقاف',
                                )
                              : '${appText(context, english: "Mode", arabic: "النمط")} ${mode.label}',
                        ),
                        subtitle: Text(_modeHint(context, mode)),
                      ),
                  ],
                ),
              ),

              if (settings.anime4kMode != Anime4kMode.off) ...[
                const Divider(height: 28),
                Text(
                  appText(context, english: 'Quality', arabic: 'الجودة'),
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  appText(
                    context,
                    english:
                        'Each step up roughly doubles the work the GPU does.',
                    arabic: 'كل درجة أعلى تضاعف تقريبًا الحِمل على كرت الشاشة.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final quality in Anime4kQuality.values)
                      ChoiceChip(
                        label: Text(quality.suffix),
                        selected: settings.anime4kQuality == quality,
                        onSelected: (_) async {
                          await ref
                              .read(playerSettingsProvider.notifier)
                              .setAnime4kQuality(quality);
                          await _refreshPipeline();
                          await _reapply();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<void>(context),
          child: Text(appText(context, english: 'Done', arabic: 'تم')),
        ),
      ],
    );
  }

  String _modeHint(BuildContext context, Anime4kMode mode) {
    return switch (mode) {
      Anime4kMode.off => appText(
        context,
        english: 'The picture is left as the source made it',
        arabic: 'تُترك الصورة كما هي من المصدر',
      ),
      Anime4kMode.a => appText(
        context,
        english: 'For compressed sources — most of what streams',
        arabic: 'للمصادر المضغوطة — وهي أغلب ما يُبَث',
      ),
      Anime4kMode.b => appText(
        context,
        english: 'A gentler restore, when A over-sharpens',
        arabic: 'ترميم أخف، حين يبالغ النمط A في الحدة',
      ),
      Anime4kMode.c => appText(
        context,
        english: 'For sources that are already clean',
        arabic: 'للمصادر النظيفة أصلًا',
      ),
      Anime4kMode.aa => appText(
        context,
        english: 'A run twice — slower, for badly degraded sources',
        arabic: 'النمط A مرتين — أبطأ، للمصادر السيئة جدًا',
      ),
      Anime4kMode.bb => appText(
        context,
        english: 'B run twice',
        arabic: 'النمط B مرتين',
      ),
      Anime4kMode.ca => appText(
        context,
        english: 'C followed by a restore pass',
        arabic: 'النمط C يتبعه ترميم',
      ),
    };
  }
}

/// Says what the chosen folder can actually run.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.pipeline, required this.checking});

  final Anime4kPipeline? pipeline;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (checking) {
      return Text(
        appText(context, english: 'Reading…', arabic: 'جارٍ القراءة…'),
        style: theme.textTheme.bodySmall,
      );
    }
    final resolved = pipeline;
    if (resolved == null) return const SizedBox.shrink();

    if (resolved.files.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              appText(
                context,
                english: 'No Anime4K shaders found in this folder',
                arabic: 'لا توجد ملفات Anime4K في هذا المجلد',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      );
    }

    final found = appText(
      context,
      english: '${resolved.files.length} shaders found',
      arabic: 'تم العثور على ${resolved.files.length} ملفات',
    );
    if (resolved.missing.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: colors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(found, style: theme.textTheme.bodySmall)),
        ],
      );
    }
    return Text(
      '$found — ${appText(context, english: "missing", arabic: "ناقص")}: '
      '${resolved.missing.join(", ")}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );
  }
}
