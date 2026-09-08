import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import '../../data/anime4k_download.dart';

/// The frame being played, as the source encoded it.
///
/// mpv's `video` screenshot is taken before the GPU pipeline the shaders run
/// in, so this still is genuinely without Anime4K however hard the shaders
/// are working on screen. Pause and the two are the same moment: the still
/// untouched, the picture around it enhanced.
///
/// There is deliberately no second still beside it. mpv can save its own
/// rendered window, but media_kit only ever asks for the `video` variant and
/// a window capture is not available under the render API this app draws
/// through — so a two-panel before-and-after would have to invent the
/// enhanced half, and an invented one teaches nothing.
///
/// With nothing playing there is no frame to take, which is the usual case
/// from the settings page. It says so, and offers the project's own
/// comparisons instead of a blank box.
class Anime4kFramePreview extends StatefulWidget {
  const Anime4kFramePreview({
    super.key,
    required this.capture,
    required this.titleColor,
    required this.bodyColor,
    this.fillColor,
    this.height = 132,
  });

  final Future<Uint8List?> Function() capture;
  final Color titleColor;
  final Color bodyColor;
  final Color? fillColor;
  final double height;

  @override
  State<Anime4kFramePreview> createState() => _Anime4kFramePreviewState();
}

class _Anime4kFramePreviewState extends State<Anime4kFramePreview> {
  Uint8List? _frame;
  bool _busy = false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    unawaited(_grab());
  }

  Future<void> _grab() async {
    if (_busy) return;
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      bytes = await widget.capture();
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    setState(() {
      _frame = bytes;
      _busy = false;
      _tried = true;
    });
  }

  Future<void> _openComparisons() async {
    final uri = Uri.parse('$anime4kProjectUrl#comparisons');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A browser that will not open is not worth an error in a settings
      // panel; the address is in the project's readme either way.
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final hasFrame = frame != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasFrame
                    ? appText(
                        context,
                        english: 'This frame, before enhancing',
                        arabic: 'هذه اللقطة قبل التحسين',
                      )
                    : appText(context, english: 'Compare', arabic: 'المقارنة'),
                style: TextStyle(
                  color: widget.titleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (hasFrame)
              TextButton.icon(
                onPressed: _busy ? null : _grab,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: Text(
                  appText(context, english: 'Refresh', arabic: 'تحديث'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            // Fixed rather than sixteen by nine across the panel: a full-width
            // frame is a third of the dialog on its own and pushes the
            // controls under it out of reach on a phone.
            height: widget.height,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.fillColor ?? Colors.white.withValues(alpha: 0.04),
              ),
              child: hasFrame
                  ? Image.memory(
                      frame,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  : Center(
                      child: _busy || !_tried
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              child: Text(
                                appText(
                                  context,
                                  english:
                                      'Nothing is playing. Open the Anime4K '
                                      'panel during an episode to compare a '
                                      'real frame.',
                                  arabic:
                                      'لا يوجد تشغيل حاليًا. افتح لوحة '
                                      'Anime4K أثناء حلقة لمقارنة لقطة '
                                      'حقيقية.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: widget.bodyColor,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (hasFrame)
          Text(
            appText(
              context,
              english:
                  'Pause, then compare this with the picture behind — same '
                  'moment, enhanced.',
              arabic:
                  'أوقف التشغيل ثم قارنها بالصورة خلف هذه النافذة — اللقطة '
                  'نفسها بعد التحسين.',
            ),
            style: TextStyle(
              color: widget.bodyColor,
              fontSize: 11,
              height: 1.4,
            ),
          )
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openComparisons,
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(
                appText(
                  context,
                  english: "See the project's own comparisons",
                  arabic: 'شاهد أمثلة المقارنة من المشروع',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
