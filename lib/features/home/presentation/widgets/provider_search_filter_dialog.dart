import 'package:flutter/material.dart';

import '../../../../shared/widgets/apple_liquid_glass.dart';

import '../../../../core/extensions/base_provider.dart';
import '../../../../core/utils/layout_constants.dart';

class ProviderSearchFilterDialog extends StatefulWidget {
  final ProviderSearchFilterOptions options;
  final ProviderSearchFilters initialValue;

  const ProviderSearchFilterDialog({
    super.key,
    required this.options,
    required this.initialValue,
  });

  @override
  State<ProviderSearchFilterDialog> createState() =>
      _ProviderSearchFilterDialogState();
}

class _ProviderSearchFilterDialogState extends State<ProviderSearchFilterDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Set<String> _statuses;
  late Set<String> _types;
  late Set<String> _ageRatings;
  late Set<String> _years;
  late Set<String> _seasons;
  late Set<String> _genres;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  bool get _seasonRequiresYear => _seasons.isNotEmpty && _years.isEmpty;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _statuses = {...widget.initialValue.statuses};
    _types = {...widget.initialValue.types};
    _ageRatings = {...widget.initialValue.ageRatings};
    _years = {...widget.initialValue.years};
    _seasons = {...widget.initialValue.seasons};
    _genres = {...widget.initialValue.genres};
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggle(Set<String> target, String value) {
    setState(() {
      if (!target.add(value)) target.remove(value);
    });
  }

  void _toggleSeason(String value) {
    setState(() {
      if (_seasons.contains(value)) {
        _seasons.clear();
      } else {
        _seasons
          ..clear()
          ..add(value);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _statuses.clear();
      _types.clear();
      _ageRatings.clear();
      _years.clear();
      _seasons.clear();
      _genres.clear();
    });
  }

  ProviderSearchFilters get _value => ProviderSearchFilters(
    statuses: {..._statuses},
    types: {..._types},
    ageRatings: {..._ageRatings},
    years: {..._years},
    seasons: {..._seasons},
    genres: {..._genres},
    sort: widget.initialValue.sort,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.82;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: double.infinity,
          height: height.clamp(520.0, 720.0).toDouble(),
          child: AppleLiquidGlassSurface(
            borderRadius: BorderRadius.circular(28),
            style: 'regular',
            interactive: true,
            fallbackColor: colors.surfaceContainerHigh.withValues(alpha: 0.96),
            fallbackBorder: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.34),
            ),
            child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: colors.primary,
                              size: 28,
                            ),
                            const SizedBox(width: LayoutConstants.spacingSm),
                            Text(
                              _isArabic ? 'فلاتر البحث' : 'Search filters',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_value.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(
                                  '${_value.count}',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: colors.primary,
                        labelColor: colors.primary,
                        unselectedLabelColor: colors.onSurfaceVariant,
                        tabs: [
                          _FilterTab(
                            icon: Icons.local_offer_outlined,
                            label: _isArabic ? 'التصنيفات' : 'Genres',
                            active: _genres.isNotEmpty,
                          ),
                          _FilterTab(
                            icon: Icons.calendar_today_outlined,
                            label: _isArabic ? 'السنة' : 'Year',
                            active: _years.isNotEmpty || _seasons.isNotEmpty,
                          ),
                          _FilterTab(
                            icon: Icons.shield_outlined,
                            label: _isArabic ? 'العمر' : 'Age',
                            active: _ageRatings.isNotEmpty,
                          ),
                          _FilterTab(
                            icon: Icons.category_outlined,
                            label: _isArabic ? 'النوع' : 'Type',
                            active: _types.isNotEmpty,
                          ),
                          _FilterTab(
                            icon: Icons.wifi_tethering_rounded,
                            label: _isArabic ? 'الحالة' : 'Status',
                            active: _statuses.isNotEmpty,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _MultiSelectGrid(
                        values: widget.options.genres,
                        selected: _genres,
                        onToggle: (value) => _toggle(_genres, value),
                        crossAxisCount: 3,
                        compact: true,
                      ),
                      _SeasonYearGrid(
                        seasons: widget.options.seasons,
                        years: widget.options.years,
                        selectedSeasons: _seasons,
                        selectedYears: _years,
                        onSeasonToggle: _toggleSeason,
                        onYearToggle: (value) => _toggle(_years, value),
                      ),
                      _MultiSelectGrid(
                        values: widget.options.ageRatings,
                        selected: _ageRatings,
                        onToggle: (value) => _toggle(_ageRatings, value),
                        crossAxisCount: 2,
                      ),
                      _MultiSelectGrid(
                        values: widget.options.types,
                        selected: _types,
                        onToggle: (value) => _toggle(_types, value),
                        crossAxisCount: 2,
                      ),
                      _MultiSelectGrid(
                        values: widget.options.statuses,
                        selected: _statuses,
                        onToggle: (value) => _toggle(_statuses, value),
                        crossAxisCount: 2,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_seasonRequiresYear)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isArabic
                                      ? 'اختر سنة مع الموسم'
                                      : 'Choose a year with the season',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _value.isEmpty ? null : _clearAll,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: Text(_isArabic ? 'مسح الكل' : 'Clear all'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _seasonRequiresYear
                                  ? null
                                  : () => Navigator.of(context).pop(_value),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: colors.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _isArabic ? 'تطبيق' : 'Apply',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _FilterTab({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20),
              if (active)
                const Positioned(
                  right: -3,
                  top: -3,
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: Colors.redAccent,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }
}


class _SeasonYearGrid extends StatelessWidget {
  final List<String> seasons;
  final List<String> years;
  final Set<String> selectedSeasons;
  final Set<String> selectedYears;
  final ValueChanged<String> onSeasonToggle;
  final ValueChanged<String> onYearToggle;

  const _SeasonYearGrid({
    required this.seasons,
    required this.years,
    required this.selectedSeasons,
    required this.selectedYears,
    required this.onSeasonToggle,
    required this.onYearToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = <String>[...seasons, ...years];

    return GridView.builder(
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 10,
      ),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final isSeason = index < seasons.length;
        final value = values[index];
        final isSelected = isSeason
            ? selectedSeasons.contains(value)
            : selectedYears.contains(value);

        return InkWell(
          onTap: () => isSeason ? onSeasonToggle(value) : onYearToggle(value),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.2)
                  : colors.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? colors.primary
                    : colors.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 17,
                  color: isSelected
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? colors.primary : colors.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MultiSelectGrid extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final int crossAxisCount;
  final bool compact;

  const _MultiSelectGrid({
    required this.values,
    required this.selected,
    required this.onToggle,
    required this.crossAxisCount,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: compact ? 2.05 : 2.5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final value = values[index];
        final isSelected = selected.contains(value);

        return InkWell(
          onTap: () => onToggle(value),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.2)
                  : colors.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? colors.primary
                    : colors.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: compact ? 17 : 19,
                  color: isSelected
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 11.5 : 13,
                      color: isSelected ? colors.primary : colors.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
