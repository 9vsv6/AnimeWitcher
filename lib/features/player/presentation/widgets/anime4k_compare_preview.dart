import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animewitcher/core/utils/localized_text.dart';
import '../../data/anime4k_download.dart';

/// The Anime4K project's own before-and-after, shown so a mode can be judged
/// before an episode is running.
///
/// Rendered by the people who wrote the shaders, on frames they chose to show
/// the work — which is a fairer demonstration than anything this app could
/// produce, since it cannot run the shaders outside mpv. Fetched from their
/// repository rather than copied into this one: it is their picture, and it
/// should stay theirs.
///
/// Cached after the first fetch, so opening the panel again costs nothing.
class Anime4kComparePreview extends StatelessWidget {
  const Anime4kComparePreview({
    super.key,
    required this.titleColor,
    required this.bodyColor,
    this.fillColor,
    this.height = 190,
  });

  final Color titleColor;
  final Color bodyColor;
  final Color? fillColor;
  final double height;

  /// Mode A on a real frame — the default pipeline, so the one worth showing.
  static const String imageUrl =
      'https://raw.githubusercontent.com/bloc97/Anime4K/master/'
      'results/Comparisons/Cropped_Screenshots/Slime.png';

  Future<void> _openProject() async {
    try {
      await launchUrl(
        Uri.parse(anime4kProjectUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A browser that will not open is not worth an error here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = fillColor ?? Colors.white.withValues(alpha: 0.04);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(context, english: 'Before and after', arabic: 'قبل وبعد'),
          style: TextStyle(
            color: titleColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                // The source is around fifteen hundred pixels wide and this
                // box is a few hundred; decoding the rest would cost memory
                // nobody can see.
                memCacheWidth: 1000,
                placeholder: (context, _) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      appText(
                        context,
                        english:
                            'The example could not be loaded. It is fetched '
                            'from the Anime4K project.',
                        arabic: 'تعذّر تحميل المثال. يُجلب من مشروع Anime4K.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                appText(
                  context,
                  english: 'Mode A, by the Anime4K project',
                  arabic: 'النمط A، من مشروع Anime4K',
                ),
                style: TextStyle(color: bodyColor, fontSize: 11, height: 1.4),
              ),
            ),
            TextButton.icon(
              onPressed: _openProject,
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(
                appText(context, english: 'More', arabic: 'المزيد'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
