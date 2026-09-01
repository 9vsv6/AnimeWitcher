import 'package:flutter/material.dart';

import '../../../../core/domain/entity/multimedia_item.dart';

/// Trims empty, unknown, and "?" placeholders out of details metadata.
String? cleanAnimeInfoValue(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  final lower = value.toLowerCase();
  if (lower == 'null' ||
      lower == 'n/a' ||
      lower == 'none' ||
      lower == 'unknown' ||
      value == '?' ||
      value == '؟') {
    return null;
  }
  return value;
}

/// True when [value] is the app/provider name rather than a real source.
bool isPlaceholderAnimeSource(String value) {
  final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return compact == 'animewitcher' || compact == 'animewitchernative';
}

/// Real manga/light-novel source only — never the app name.
String? displayableAnimeSource({String? syncSource, String? itemSource}) {
  for (final raw in <String?>[syncSource, itemSource]) {
    final cleaned = cleanAnimeInfoValue(raw);
    if (cleaned == null || isPlaceholderAnimeSource(cleaned)) continue;
    return cleaned;
  }
  return null;
}

class AnimeInformationSection extends StatelessWidget {
  final MultimediaItem item;

  const AnimeInformationSection({super.key, required this.item});

  String? _read(Map<String, String> data, List<String> keys) {
    for (final key in keys) {
      final value = cleanAnimeInfoValue(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _durationLabel(BuildContext context, Map<String, String> data) {
    final raw = cleanAnimeInfoValue(data['awDuration']);
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
      TextDirection? valueTextDirection,
    }) {
      final cleaned = cleanAnimeInfoValue(value);
      if (cleaned == null) return null;
      return _AnimeInfoEntry(
        label: isArabic ? ar : en,
        value: cleaned,
        showFullValue: showFullValue,
        valueTextDirection: valueTextDirection,
      );
    }

    final source = displayableAnimeSource(
      syncSource: _read(data, const ['awSource']),
      itemSource: item.source,
    );
    final startDate = _read(data, const ['awStartDate']);
    final endDate = _read(data, const ['awEndDate']);

    final entries = <_AnimeInfoEntry?>[
      entry('المصدر', 'Source', source),
      entry('مدة الحلقة', 'Episode duration', _durationLabel(context, data)),
      if (startDate != null || endDate != null) ...[
        _AnimeInfoEntry(
          label: isArabic ? 'بداية العرض' : 'Start date',
          value: startDate ?? '?',
        ),
        _AnimeInfoEntry(
          label: isArabic ? 'نهاية العرض' : 'End date',
          value: endDate ?? '?',
        ),
      ],
      entry('الاستديو', 'Studio', _read(data, const ['awStudio'])),
      entry(
        'العنوان الإنجليزي',
        'English title',
        _read(data, const ['awEnglishTitle']),
        showFullValue: true,
        // Always Latin script: keep LTR/left-aligned even on the Arabic RTL
        // details page. The Arabic label still inherits page direction.
        valueTextDirection: TextDirection.ltr,
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
  final TextDirection? valueTextDirection;

  const _AnimeInfoEntry({
    required this.label,
    required this.value,
    this.showFullValue = false,
    this.valueTextDirection,
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
        SizedBox(
          width: entry.valueTextDirection == TextDirection.ltr
              ? double.infinity
              : null,
          child: Text(
            entry.value,
            textDirection: entry.valueTextDirection,
            textAlign: entry.valueTextDirection == TextDirection.ltr
                ? TextAlign.start
                : null,
            maxLines: entry.showFullValue ? null : 2,
            overflow: entry.showFullValue
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
