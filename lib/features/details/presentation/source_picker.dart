import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../core/domain/entity/multimedia_item.dart';

Future<StreamResult?> showStreamSourcePicker(
  BuildContext context,
  List<StreamResult> sources, {
  required bool forDownload,
}) {
  final groups = LinkedHashMap<String, List<StreamResult>>();
  for (final source in sources) {
    final quality = (source.quality ?? '').trim();
    final key = quality.isEmpty ? 'متعدد' : quality;
    groups.putIfAbsent(key, () => <StreamResult>[]).add(source);
  }

  const preferredOrder = <String>['1080', '720', '480', 'متعدد'];
  final orderedKeys = <String>[
    ...preferredOrder.where(groups.containsKey),
    ...groups.keys.where((key) => !preferredOrder.contains(key)),
  ];
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
                itemCount: orderedKeys.length,
                itemBuilder: (context, groupIndex) {
                  final quality = orderedKeys[groupIndex];
                  final items = groups[quality]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Text(
                          quality,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                      for (final source in items)
                        ListTile(
                          leading: Icon(
                            forDownload
                                ? Icons.file_download_outlined
                                : Icons.play_circle_outline,
                          ),
                          title: Text(
                            source.source,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.of(sheetContext).pop(source),
                        ),
                    ],
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
