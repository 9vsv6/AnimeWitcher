import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import '../../data/anime4k.dart';
import '../../data/anime4k_download.dart';

/// One frame with the shaders and without, split by a divider you can drag.
///
/// Both halves are captured the same way, a moment apart with the shaders
/// switched off in between, so the only thing that differs between them is
/// the thing being judged. Dragging the divider across a single frame shows
/// far more than flipping between two pictures, because the eye can hold an
/// edge still and watch it change.
///
/// When mpv will not hand over its own rendered output — some builds cannot,
/// under a render API that owns no window — there is nothing honest to put in
/// the "after" half, so this asks for the project's own comparisons instead
/// of inventing one.
class Anime4kComparePreview extends StatefulWidget {
  const Anime4kComparePreview({
    super.key,
    required this.capture,
    required this.titleColor,
    required this.bodyColor,
    this.fillColor,
    this.height = 200,
  });

  /// Takes the pair, or null when this player cannot.
  final Future<Anime4kComparison?> Function() capture;

  final Color titleColor;
  final Color bodyColor;
  final Color? fillColor;
  final double height;

  @override
  State<Anime4kComparePreview> createState() => _Anime4kComparePreviewState();
}

class _Anime4kComparePreviewState extends State<Anime4kComparePreview> {
  Anime4kComparison? _pair;
  bool _busy = false;
  bool _tried = false;

  /// Where the divider sits, as a fraction of the width.
  double _split = 0.5;

  @override
  void initState() {
    super.initState();
    unawaited(_grab());
  }

  Future<void> _grab() async {
    if (_busy) return;
    setState(() => _busy = true);
    Anime4kComparison? pair;
    try {
      pair = await widget.capture();
    } catch (_) {
      pair = null;
    }
    if (!mounted) return;
    setState(() {
      _pair = pair;
      _busy = false;
      _tried = true;
    });
  }

  Future<void> _openComparisons() async {
    try {
      await launchUrl(
        Uri.parse(anime4kProjectUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Not worth an error in a settings panel.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pair;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                appText(
                  context,
                  english: 'Before and after',
                  arabic: 'قبل وبعد',
                ),
                style: TextStyle(
                  color: widget.titleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (pair != null)
              TextButton.icon(
                onPressed: _busy ? null : _grab,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: Text(
                  appText(
                    context,
                    english: 'This frame',
                    arabic: 'اللقطة الحالية',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.fillColor ?? Colors.white.withValues(alpha: 0.04),
              ),
              child: pair != null
                  ? _Split(
                      pair: pair,
                      split: _split,
                      onSplit: (value) => setState(() => _split = value),
                    )
                  : Center(child: _placeholder(context)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (pair != null)
          Text(
            appText(
              context,
              english: 'Drag the divider. Captured from what is playing.',
              arabic: 'اسحب الفاصل. اللقطة مأخوذة مما يعمل الآن.',
            ),
            style: TextStyle(
              color: widget.bodyColor,
              fontSize: 11,
              height: 1.4,
            ),
          )
        else if (_tried)
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

  Widget _placeholder(BuildContext context) {
    if (_busy || !_tried) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Text(
        appText(
          context,
          english:
              'A comparison needs an episode playing, and a player that can '
              'hand over its own rendered picture.',
          arabic:
              'تحتاج المقارنة إلى حلقة قيد التشغيل، وإلى مشغّل يستطيع تسليم '
              'الصورة التي رسمها.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: widget.bodyColor, fontSize: 12, height: 1.4),
      ),
    );
  }
}

/// The two frames stacked, the top one clipped to the divider.
class _Split extends StatelessWidget {
  const _Split({
    required this.pair,
    required this.split,
    required this.onSplit,
  });

  final Anime4kComparison pair;
  final double split;
  final ValueChanged<double> onSplit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void setFromDx(double dx) =>
            onSplit((dx / width).clamp(0.02, 0.98).toDouble());

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => setFromDx(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => setFromDx(d.localPosition.dx),
          onTapDown: (d) => setFromDx(d.localPosition.dx),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The source underneath, uncovered as the divider moves left.
              Image.memory(
                pair.before,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              // The enhanced picture over it, clipped to the divider.
              ClipRect(
                clipper: _LeftOf(split),
                child: Image.memory(
                  pair.after,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              // The divider, drawn where the clip ends.
              Positioned.fill(
                child: CustomPaint(painter: _DividerPainter(split)),
              ),
              // Direction is fixed, not mirrored with the interface: the
              // enhanced half is the one on the left of the divider whatever
              // the page direction, because that is where it is drawn.
              Positioned(
                left: 8,
                top: 8,
                child: _Tag(
                  text: appText(context, english: 'AFTER', arabic: 'بعد'),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: _Tag(
                  text: appText(context, english: 'BEFORE', arabic: 'قبل'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.split);
  final double split;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftOf oldClipper) => oldClipper.split != split;
}

class _DividerPainter extends CustomPainter {
  const _DividerPainter(this.split);
  final double split;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * split;
    canvas.drawRect(
      Rect.fromLTWH(x - 1, 0, 2, size.height),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_DividerPainter oldDelegate) => oldDelegate.split != split;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
