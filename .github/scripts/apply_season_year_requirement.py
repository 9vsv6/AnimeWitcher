from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


dialog_path = Path('lib/features/home/presentation/widgets/provider_search_filter_dialog.dart')
dialog = dialog_path.read_text(encoding='utf-8')

dialog = replace_once(
    dialog,
    """  bool get _isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
""",
    """  bool get _isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  bool get _seasonRequiresYear => _seasons.isNotEmpty && _years.isEmpty;
""",
    'season validation getter',
)

dialog = replace_once(
    dialog,
    """                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _value.isEmpty ? null : _clearAll,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: Text(_isArabic ? 'مسح الكل' : 'Clear all'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(_value),
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
                ),
""",
    """                Padding(
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
""",
    'season/year apply validation',
)

dialog_path.write_text(dialog, encoding='utf-8')

provider_path = Path('lib/core/extensions/providers/animewitcher_native_provider.dart')
provider = provider_path.read_text(encoding='utf-8')
provider = replace_once(
    provider,
    """  String _seasonFilter(ProviderSearchFilters filters) {
    final seasons = filters.seasons
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (seasons.isEmpty) return '';

    final selectedYears = filters.years
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final years = selectedYears.isNotEmpty
        ? selectedYears
        : <String>[
            for (var year = 2028; year >= 1961; year--) year.toString(),
          ];
    final values = <String>[
      for (final season in seasons)
        for (final year in years) '$season عام $year',
    ];
    return _filterGroup('details.season', values, 'OR');
  }

  String _buildFilters(ProviderSearchFilters filters) {
    return <String>[
      _filterGroup('details.state', filters.statuses, 'OR'),
      _filterGroup('type', filters.types, 'OR'),
      _filterGroup('details.age', filters.ageRatings, 'OR'),
      _filterGroup('details.year', filters.years, 'OR'),
      _seasonFilter(filters),
      _filterGroup('tags', filters.genres, 'AND'),
    ].where((value) => value.isNotEmpty).join(' AND ');
  }
""",
    """  String _seasonFilter(ProviderSearchFilters filters) {
    final seasons = filters.seasons
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (seasons.isEmpty) return '';

    final selectedYears = filters.years
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (selectedYears.isEmpty) {
      // The UI blocks this state. Keep a defensive no-match filter for any
      // persisted/programmatic filter that selects a season without a year.
      return _filterGroup(
        'details.season',
        const <String>['__season_requires_year__'],
        'OR',
      );
    }

    final values = <String>[
      for (final season in seasons)
        for (final year in selectedYears) '$season عام $year',
    ];
    return _filterGroup('details.season', values, 'OR');
  }

  String _buildFilters(ProviderSearchFilters filters) {
    final hasSeason = filters.seasons.any((value) => value.trim().isNotEmpty);
    return <String>[
      _filterGroup('details.state', filters.statuses, 'OR'),
      _filterGroup('type', filters.types, 'OR'),
      _filterGroup('details.age', filters.ageRatings, 'OR'),
      if (!hasSeason) _filterGroup('details.year', filters.years, 'OR'),
      _seasonFilter(filters),
      _filterGroup('tags', filters.genres, 'AND'),
    ].where((value) => value.isNotEmpty).join(' AND ');
  }
""",
    'provider season/year semantics',
)
provider_path.write_text(provider, encoding='utf-8')

print('Season/year filter patch applied.')
