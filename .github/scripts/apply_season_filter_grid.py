from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


base_path = Path('lib/core/extensions/base_provider.dart')
base = base_path.read_text(encoding='utf-8')
base = replace_once(base, "  final List<String> years;\n  final List<String> genres;", "  final List<String> years;\n  final List<String> seasons;\n  final List<String> genres;", 'options fields')
base = replace_once(base, "    this.years = const <String>[],\n    this.genres = const <String>[],", "    this.years = const <String>[],\n    this.seasons = const <String>[],\n    this.genres = const <String>[],", 'options constructor')
base = replace_once(base, "      years.isEmpty &&\n      genres.isEmpty;", "      years.isEmpty &&\n      seasons.isEmpty &&\n      genres.isEmpty;", 'options isEmpty')
base = replace_once(base, "      years: read('years'),\n      genres: read('genres'),", "      years: read('years'),\n      seasons: read('seasons'),\n      genres: read('genres'),", 'options fromJson')
base = replace_once(base, "  final Set<String> years;\n  final Set<String> genres;", "  final Set<String> years;\n  final Set<String> seasons;\n  final Set<String> genres;", 'filter fields')
base = replace_once(base, "    this.years = const <String>{},\n    this.genres = const <String>{},", "    this.years = const <String>{},\n    this.seasons = const <String>{},\n    this.genres = const <String>{},", 'filter constructor')
base = replace_once(base, "      years.length +\n      genres.length;", "      years.length +\n      seasons.length +\n      genres.length;", 'filter count')
base = replace_once(base, "      'years': years.toList(growable: false),\n      'genres': genres.toList(growable: false),", "      'years': years.toList(growable: false),\n      'seasons': seasons.toList(growable: false),\n      'genres': genres.toList(growable: false),", 'filter json')
base = replace_once(base, "    Set<String>? years,\n    Set<String>? genres,", "    Set<String>? years,\n    Set<String>? seasons,\n    Set<String>? genres,", 'copyWith args')
base = replace_once(base, "      years: years ?? this.years,\n      genres: genres ?? this.genres,", "      years: years ?? this.years,\n      seasons: seasons ?? this.seasons,\n      genres: genres ?? this.genres,", 'copyWith body')
base_path.write_text(base, encoding='utf-8')


dialog_path = Path('lib/features/home/presentation/widgets/provider_search_filter_dialog.dart')
dialog = dialog_path.read_text(encoding='utf-8')
dialog = replace_once(dialog, "  late Set<String> _years;\n  late Set<String> _genres;", "  late Set<String> _years;\n  late Set<String> _seasons;\n  late Set<String> _genres;", 'dialog fields')
dialog = replace_once(dialog, "    _years = {...widget.initialValue.years};\n    _genres = {...widget.initialValue.genres};", "    _years = {...widget.initialValue.years};\n    _seasons = {...widget.initialValue.seasons};\n    _genres = {...widget.initialValue.genres};", 'dialog init')
dialog = replace_once(dialog, "  void _clearAll() {", "  void _toggleSeason(String value) {\n    setState(() {\n      if (_seasons.contains(value)) {\n        _seasons.clear();\n      } else {\n        _seasons\n          ..clear()\n          ..add(value);\n      }\n    });\n  }\n\n  void _clearAll() {", 'season toggle')
dialog = replace_once(dialog, "      _years.clear();\n      _genres.clear();", "      _years.clear();\n      _seasons.clear();\n      _genres.clear();", 'clear seasons')
dialog = replace_once(dialog, "    years: {..._years},\n    genres: {..._genres},", "    years: {..._years},\n    seasons: {..._seasons},\n    genres: {..._genres},", 'dialog value')
dialog = replace_once(dialog, "                            active: _years.isNotEmpty,", "                            active: _years.isNotEmpty || _seasons.isNotEmpty,", 'year tab active')
dialog = replace_once(dialog, """                      _MultiSelectGrid(
                        values: widget.options.years,
                        selected: _years,
                        onToggle: (value) => _toggle(_years, value),
                        crossAxisCount: 3,
                      ),""", """                      _SeasonYearGrid(
                        seasons: widget.options.seasons,
                        years: widget.options.years,
                        selectedSeasons: _seasons,
                        selectedYears: _years,
                        onSeasonToggle: _toggleSeason,
                        onYearToggle: (value) => _toggle(_years, value),
                      ),""", 'year grid')
season_grid = r'''
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

'''
dialog = replace_once(dialog, 'class _MultiSelectGrid extends StatelessWidget {', season_grid + 'class _MultiSelectGrid extends StatelessWidget {', 'season/year grid class')
dialog_path.write_text(dialog, encoding='utf-8')


provider_path = Path('lib/core/extensions/providers/animewitcher_native_provider.dart')
provider = provider_path.read_text(encoding='utf-8')
provider = replace_once(provider, """  String _buildFilters(ProviderSearchFilters filters) {
    return <String>[
      _filterGroup('details.state', filters.statuses, 'OR'),
      _filterGroup('type', filters.types, 'OR'),
      _filterGroup('details.age', filters.ageRatings, 'OR'),
      _filterGroup('details.year', filters.years, 'OR'),
      _filterGroup('tags', filters.genres, 'AND'),
    ].where((value) => value.isNotEmpty).join(' AND ');
  }
""", """  String _seasonFilter(ProviderSearchFilters filters) {
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
""", 'provider filter builder')
provider = replace_once(provider, "      years: years,\n      genres: const <String>[", "      years: years,\n      seasons: const <String>['شتاء', 'ربيع', 'صيف', 'خريف'],\n      genres: const <String>[", 'provider season options')
provider_path.write_text(provider, encoding='utf-8')

print('Season filter patch applied successfully.')
