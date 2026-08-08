import 'package:flutter/material.dart';

import '../../../core/domain/entity/multimedia_item.dart';

Future<StreamResult?> showStreamSourcePicker(
  BuildContext context,
  List<StreamResult> sources, {
  required bool forDownload,
}) {
  final isArabic =
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  return showModalBottomSheet<StreamResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                isArabic ? 'اختر المصدر' : 'Choose source',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final quality = source.quality;
                  final hasQuality =
                      quality != null && quality.trim().isNotEmpty;

                  return ListTile(
                    leading: Icon(
                      forDownload
                          ? Icons.file_download_outlined
                          : Icons.play_circle_outline,
                    ),
                    title: Text(
                      source.source,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: hasQuality ? Text(quality) : null,
                    onTap: () => Navigator.of(sheetContext).pop(source),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
