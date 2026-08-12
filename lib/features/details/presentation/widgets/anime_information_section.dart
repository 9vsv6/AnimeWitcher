import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';

class AnimeInformationSection extends StatelessWidget {
  final MultimediaItem item;

  const AnimeInformationSection({super.key, required this.item});

  String? _clean(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    return value;
  }

  String? _read(Map<String, String> data, List<String> keys) {
    for (final key in keys) {
      final value = _clean(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _durationLabel(BuildContext context, Map<String, String> data) {
    final raw = _clean(data['awDuration']);
    int? minutes;
    if (raw != null) {
      final match = RegExp(r'[0-9]+').firstMatch(raw);
      minutes = match == null ? null : int.tryParse(match.group(0)!);
    }
    if (minutes == null || minutes <= 0) minutes = item.duration;
    if (minutes == null || minutes <= 0) return null;
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    return isArabic ? '$minutes دقيقة' : '$minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final data = item.syncData ?? const <String, String>{};
    final colors = Theme.of(context).colorScheme;

    _AnimeInfoEntry? entry(
      String ar,
      String en,
      dynamic value, {
      bool showFullValue = false,
    }) {
      final cleaned = _clean(value);
      if (cleaned == null) return null;
      return _AnimeInfoEntry(
        label: isArabic ? ar : en,
        value: cleaned,
        showFullValue: showFullValue,
      );
    }

    final entries = <_AnimeInfoEntry?>[
      entry('المصدر', 'Source', _read(data, const ['awSource']) ?? item.source),
      entry('مدة الحلقة', 'Episode duration', _durationLabel(context, data)),
      entry('بداية العرض', 'Start date', _read(data, const ['awStartDate']) ?? '?'),
      entry('نهاية العرض', 'End date', _read(data, const ['awEndDate']) ?? '?'),
      entry('الاستديو', 'Studio', _read(data, const ['awStudio'])),
      entry(
        'العنوان الإنجليزي',
        'English title',
        _read(data, const ['awEnglishTitle']),
        showFullValue: true,
      ),
    ].whereType<_AnimeInfoEntry>().toList(growable: false);

    if (entries.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - 20) / 2;
            return Wrap(
              spacing: 20,
              runSpacing: 22,
              children: [
                for (final value in entries)
                  SizedBox(
                    width: cellWidth,
                    child: _AnimeInfoValue(entry: value),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnimeInfoEntry {
  final String label;
  final String value;
  final bool showFullValue;

  const _AnimeInfoEntry({
    required this.label,
    required this.value,
    this.showFullValue = false,
  });
}

class _AnimeInfoValue extends StatelessWidget {
  final _AnimeInfoEntry entry;

  const _AnimeInfoValue({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.value,
          maxLines: entry.showFullValue ? null : 2,
          overflow: entry.showFullValue ? TextOverflow.visible : TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
