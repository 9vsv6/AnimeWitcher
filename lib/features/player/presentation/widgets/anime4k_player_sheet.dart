import 'dart:async';

import 'package:flutter/material.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import '../../data/anime4k.dart';
import 'hotstar_player_style.dart';
import 'player_ltr.dart';

/// Changes the Anime4K pipeline without leaving the episode.
///
/// The settings page is where the shader folder is chosen once; this is for
/// the part worth changing while watching. Whether mode A over-sharpens a
/// particular show, or whether the GPU can hold VL on this one, is not a
/// question anybody can answer from a settings screen — it is answered by
/// looking at the picture, which means changing it here and seeing.
class Anime4kPlayerSheet {
  const Anime4kPlayerSheet._();

  static void show({
    required BuildContext context,
    required Anime4kMode currentMode,
    required Anime4kQuality currentQuality,
    required ValueChanged<Anime4kMode> onModeSelected,
    required ValueChanged<Anime4kQuality> onQualitySelected,
    required Future<String> Function() appliedValue,
    required Future<void> Function(bool bypassed) onCompareHeld,
  }) {
    var mode = currentMode;
    var quality = currentQuality;

    showPlayerDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final size = MediaQuery.sizeOf(context);
            final isCompact = size.shortestSide < 600;
            final compactWidth = (size.width - 32)
                .clamp(280.0, 360.0)
                .toDouble();
            final maxWidth = isCompact
                ? compactWidth
                : (size.width >= 900 ? 520.0 : compactWidth);
            final maxHeight = (size.height * (isCompact ? 0.7 : 0.75))
                .clamp(200.0, 560.0)
                .toDouble();

            return Dialog(
              backgroundColor: HotstarPlayerStyle.background,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 16,
                vertical: isCompact ? 16 : 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isCompact ? 14 : 20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    brightness: Brightness.dark,
                    colorScheme: const ColorScheme.dark(
                      primary: HotstarPlayerStyle.accent,
                      surface: HotstarPlayerStyle.background,
                      onSurface: HotstarPlayerStyle.primaryText,
                    ),
                    chipTheme: ChipThemeData(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      selectedColor: HotstarPlayerStyle.accent.withValues(
                        alpha: 0.22,
                      ),
                      labelStyle: const TextStyle(
                        color: HotstarPlayerStyle.secondaryText,
                      ),
                      secondaryLabelStyle: const TextStyle(
                        color: HotstarPlayerStyle.primaryText,
                      ),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompact ? 16 : 24,
                      isCompact ? 12 : 18,
                      isCompact ? 16 : 24,
                      isCompact ? 16 : 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Anime4K',
                                style: TextStyle(
                                  color: HotstarPlayerStyle.primaryText,
                                  fontSize: isCompact ? 15 : 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                              color: HotstarPlayerStyle.secondaryText,
                              autofocus: true,
                            ),
                          ],
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label(
                                  context,
                                  appText(
                                    context,
                                    english: 'Mode',
                                    arabic: 'النمط',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final value in Anime4kMode.values)
                                      ChoiceChip(
                                        label: Text(
                                          value == Anime4kMode.off
                                              ? appText(
                                                  context,
                                                  english: 'Off',
                                                  arabic: 'إيقاف',
                                                )
                                              : value.label,
                                        ),
                                        selected: mode == value,
                                        onSelected: (_) {
                                          setState(() => mode = value);
                                          onModeSelected(value);
                                        },
                                      ),
                                  ],
                                ),
                                SizedBox(height: isCompact ? 16 : 22),
                                _label(
                                  context,
                                  appText(
                                    context,
                                    english: 'Quality',
                                    arabic: 'الجودة',
                                  ),
                                ),
                                Text(
                                  appText(
                                    context,
                                    english:
                                        'Each step up roughly doubles the '
                                        'work the GPU does.',
                                    arabic:
                                        'كل درجة أعلى تضاعف تقريبًا الحِمل '
                                        'على كرت الشاشة.',
                                  ),
                                  style: const TextStyle(
                                    color: HotstarPlayerStyle.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final value in Anime4kQuality.values)
                                      ChoiceChip(
                                        label: Text(value.suffix),
                                        selected: quality == value,
                                        // Turned off, the size decides
                                        // nothing, so it is left inert rather
                                        // than inviting a change that does
                                        // not show.
                                        onSelected: mode == Anime4kMode.off
                                            ? null
                                            : (_) {
                                                setState(() => quality = value);
                                                onQualitySelected(value);
                                              },
                                      ),
                                  ],
                                ),
                                SizedBox(height: isCompact ? 14 : 18),
                                if (mode != Anime4kMode.off)
                                  _CompareButton(onHeld: onCompareHeld),
                                SizedBox(height: isCompact ? 10 : 14),
                                _AppliedLine(read: appliedValue, mode: mode),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: const TextStyle(
        color: HotstarPlayerStyle.primaryText,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Says whether mpv is actually running the shaders.
///
/// The picture is the real answer, but "is it on at all" should not be a
/// judgement call: a wrong folder and a mode that is simply subtle look
/// identical from the sofa, and only one of them is worth investigating.
class _AppliedLine extends StatefulWidget {
  const _AppliedLine({required this.read, required this.mode});

  final Future<String> Function() read;
  final Anime4kMode mode;

  @override
  State<_AppliedLine> createState() => _AppliedLineState();
}

class _AppliedLineState extends State<_AppliedLine> {
  String? _value;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(_AppliedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _refresh();
  }

  Future<void> _refresh() async {
    // A moment for the apply that a chip tap has just started.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final value = await widget.read();
    if (mounted) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) return const SizedBox.shrink();

    final running = value.trim().isNotEmpty;
    final count = running
        ? value
              .split(RegExp(r'(?<!\)[:;]'))
              .where((p) => p.trim().isNotEmpty)
              .length
        : 0;

    if (widget.mode == Anime4kMode.off) {
      return Text(
        appText(context, english: 'Not running', arabic: 'غير مُفعّل'),
        style: const TextStyle(
          color: HotstarPlayerStyle.secondaryText,
          fontSize: 12,
        ),
      );
    }
    return Row(
      children: [
        Icon(
          running
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          size: 15,
          color: running
              ? HotstarPlayerStyle.accent
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            running
                ? appText(
                    context,
                    english: 'mpv is running $count shaders',
                    arabic: 'mpv يشغّل $count ملفات',
                  )
                : appText(
                    context,
                    english:
                        'mpv is running none — check the shader folder in '
                        'settings',
                    arabic:
                        'mpv لا يشغّل أي ملف — راجع مجلد الشيدرات في '
                        'الإعدادات',
                  ),
            style: TextStyle(
              color: running
                  ? HotstarPlayerStyle.secondaryText
                  : Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hold to see the picture without the shaders.
///
/// A settings screen cannot show what a mode does. The shaders run inside
/// mpv, on the frame being played, so the only truthful comparison is that
/// frame with them and without them — which means taking them away while a
/// finger is down and putting them back when it lifts. Pausing first makes it
/// easiest to see.
class _CompareButton extends StatefulWidget {
  const _CompareButton({required this.onHeld});

  final Future<void> Function(bool bypassed) onHeld;

  @override
  State<_CompareButton> createState() => _CompareButtonState();
}

class _CompareButtonState extends State<_CompareButton> {
  bool _held = false;

  Future<void> _set(bool held) async {
    if (_held == held) return;
    setState(() => _held = held);
    await widget.onHeld(held);
  }

  @override
  void dispose() {
    // Releasing by closing the sheet must not leave the shaders switched off
    // with nothing on screen saying so.
    if (_held) unawaited(widget.onHeld(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: _held
              ? HotstarPlayerStyle.accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _held
                ? HotstarPlayerStyle.accent
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _held ? Icons.visibility_off_rounded : Icons.compare_rounded,
              size: 17,
              color: HotstarPlayerStyle.primaryText,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _held
                    ? appText(
                        context,
                        english: 'Shaders off — release to restore',
                        arabic: 'بدون تحسين — ارفع إصبعك للعودة',
                      )
                    : appText(
                        context,
                        english: 'Hold to compare with the original',
                        arabic: 'اضغط مع الاستمرار للمقارنة بالأصل',
                      ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: HotstarPlayerStyle.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
