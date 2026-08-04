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

  String _status(bool isArabic) {
    switch (item.status) {
      case ShowStatus.completed:
        return isArabic ? 'مكتمل' : 'Completed';
      case ShowStatus.upcoming:
        return isArabic ? 'قادم' : 'Upcoming';
      case ShowStatus.ongoing:
        return isArabic ? 'مستمر' : 'Ongoing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final data = item.syncData ?? const <String, String>{};
    final entries = <({String label, String value, IconData icon})>[];

    void add(String ar, String en, dynamic value, IconData icon) {
      final cleaned = _clean(value);
      if (cleaned == null) return;
      entries.add((label: isArabic ? ar : en, value: cleaned, icon: icon));
    }

    add(
      'العنوان الإنجليزي',
      'English title',
      _read(data, const ['awEnglishTitle']),
      Icons.translate_rounded,
    );
    add(
      'الاستديو',
      'Studio',
      _read(data, const ['awStudio']),
      Icons.apartment_rounded,
    );
    add(
      'المصدر',
      'Source',
      _read(data, const ['awSource']) ?? item.source,
      Icons.menu_book_rounded,
    );
    add(
      'الحالة',
      'Status',
      _read(data, const ['awState']) ?? _status(isArabic),
      Icons.wifi_tethering_rounded,
    );
    add(
      'موسم العرض',
      'Airing season',
      _read(data, const ['awSeason']),
      Icons.calendar_month_rounded,
    );
    add(
      'رقم الموسم',
      'Season number',
      _read(data, const ['awSeasonNumber']),
      Icons.format_list_numbered_rounded,
    );
    add(
      'تاريخ البداية',
      'Start date',
      _read(data, const ['awStartDate']),
      Icons.play_circle_outline_rounded,
    );
    add(
      'تاريخ النهاية',
      'End date',
      _read(data, const ['awEndDate']),
      Icons.stop_circle_outlined,
    );
    add(
      'عدد الحلقات',
      'Episodes',
      _read(data, const ['awEpisodes']),
      Icons.video_library_outlined,
    );
    add(
      'مدة الحلقة',
      'Episode duration',
      _read(data, const ['awDuration']) ??
          (item.duration == null ? null : '${item.duration} min'),
      Icons.schedule_rounded,
    );
    add(
      'التصنيف العمري',
      'Age rating',
      _read(data, const ['awAge']) ?? item.contentRating,
      Icons.shield_outlined,
    );

    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'معلومات الأنمي' : 'Anime information',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 480
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(entry.icon, size: 21, color: colors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  SelectableText(
                                    entry.value,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
