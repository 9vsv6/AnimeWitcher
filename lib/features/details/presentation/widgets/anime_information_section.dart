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

  String? _durationLabel(
    BuildContext context,
    Map<String, String> data,
  ) {
    final raw = _clean(data['awDuration']);
    int? minutes;

    if (raw != null) {
      final match = RegExp(r'[0-9]+').firstMatch(raw);
      minutes = match == null ? null : int.tryParse(match.group(0)!);
    }

    if (minutes == null || minutes <= 0) {
      minutes = item.duration;
    }
    if (minutes == null || minutes <= 0) return null;

    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    return isArabic ? '\${minutes} دقيقة' : '\${minutes} minutes';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final data = item.syncData ?? const <String, String>{};

    _AnimeInfoEntry? entry(String ar, String en, dynamic value, IconData icon) {
      final cleaned = _clean(value);
      if (cleaned == null) return null;
      return _AnimeInfoEntry(
        label: isArabic ? ar : en,
        value: cleaned,
        icon: icon,
      );
    }

    final rows = <List<_AnimeInfoEntry?>>[
      [
        entry(
          'المصدر',
          'Source',
          _read(data, const ['awSource']) ?? item.source,
          Icons.menu_book_rounded,
        ),
        entry(
          'مدة الحلقة',
          'Episode duration',
          _durationLabel(context, data),
          Icons.timer_outlined,
        ),
      ],
      [
        entry(
          'بداية العرض',
          'Start date',
          _read(data, const ['awStartDate']),
          Icons.play_circle_outline_rounded,
        ),
        entry(
          'نهاية العرض',
          'End date',
          _read(data, const ['awEndDate']),
          Icons.stop_circle_outlined,
        ),
      ],
      [
        entry(
          'الاستديو',
          'Studio',
          _read(data, const ['awStudio']),
          Icons.apartment_rounded,
        ),
      ],
    ];

    final englishTitle = entry(
      'العنوان الإنجليزي',
      'English title',
      _read(data, const ['awEnglishTitle']),
      Icons.translate_rounded,
    );

    final hasRows = rows.any((row) => row.any((value) => value != null));
    if (!hasRows && englishTitle == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'معلومات الأنمي' : 'Anime information',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final row in rows) ...[
          if (row.any((value) => value != null))
            Row(
              // The section is inside a vertically unbounded scroll view.
              // Stretch would request an infinite height at runtime.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < row.length; index++) ...[
                  if (row[index] != null)
                    Expanded(child: _AnimeInfoCard(entry: row[index]!)),
                  if (index == 0 && row[0] != null && row[1] != null)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          if (row.any((value) => value != null)) const SizedBox(height: 8),
        ],
        if (englishTitle != null)
          SizedBox(
            width: double.infinity,
            child: _AnimeInfoCard(entry: englishTitle),
          ),
      ],
    );
  }
}

class _AnimeInfoEntry {
  final String label;
  final String value;
  final IconData icon;

  const _AnimeInfoEntry({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _AnimeInfoCard extends StatelessWidget {
  final _AnimeInfoEntry entry;

  const _AnimeInfoCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(entry.icon, size: 18, color: colors.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    entry.value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
