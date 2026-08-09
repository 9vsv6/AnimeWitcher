from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


provider_path = Path('lib/core/extensions/providers/animewitcher_native_provider.dart')
provider = provider_path.read_text(encoding='utf-8')
if 'class AnimeWitcherSeasonConfig' not in provider:
    provider = replace_once(
        provider,
        '/// Native AnimeWitcher implementation used during the JS-to-native migration.\n',
        '''class AnimeWitcherSeasonConfig {
  final String past;
  final String current;
  final String next;

  const AnimeWitcherSeasonConfig({
    required this.past,
    required this.current,
    required this.next,
  });
}

const List<String> animeWitcherBroadcastDays = <String>[
  'السبت',
  'الأحد',
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
];

/// Native AnimeWitcher implementation used during the JS-to-native migration.
''',
        'provider DTOs',
    )
    provider = replace_once(
        provider,
        '''  DateTime _remoteConstantsExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _remoteConstantsRequest;
''',
        '''  DateTime _remoteConstantsExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _remoteConstantsRequest;
  String _seasonPast = '';
  String _seasonCurrent = '';
  String _seasonNext = '';
  List<String>? _allSeasonsCache;
  DateTime _allSeasonsExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
''',
        'provider season state',
    )
    provider = replace_once(
        provider,
        '''      final serverLoadType = _text(fields['load_servers_type']).toLowerCase();
      if (serverLoadType.isNotEmpty) _serverLoadType = serverLoadType;
      _remoteConstantsExpiresAt = now.add(_remoteConstantsTtl);
''',
        '''      final serverLoadType = _text(fields['load_servers_type']).toLowerCase();
      if (serverLoadType.isNotEmpty) _serverLoadType = serverLoadType;

      final seasons = _map(fields['seasons']);
      final past = _text(seasons['past']);
      final current = _text(seasons['current']);
      final next = _text(seasons['next']);
      if (past.isNotEmpty) _seasonPast = past;
      if (current.isNotEmpty) _seasonCurrent = current;
      if (next.isNotEmpty) _seasonNext = next;

      _remoteConstantsExpiresAt = now.add(_remoteConstantsTtl);
''',
        'provider constants seasons',
    )
    provider_api = r'''  AnimeWitcherSeasonConfig _fallbackSeasonConfig() {
    const names = <String>['شتاء', 'ربيع', 'صيف', 'خريف'];
    final now = DateTime.now();
    final currentIndex = ((now.month - 1) ~/ 3).clamp(0, 3).toInt();

    String valueFor(int index, int year) => '${names[index]} عام $year';

    final previousIndex = (currentIndex + 3) % 4;
    final nextIndex = (currentIndex + 1) % 4;
    final previousYear = currentIndex == 0 ? now.year - 1 : now.year;
    final nextYear = currentIndex == 3 ? now.year + 1 : now.year;
    return AnimeWitcherSeasonConfig(
      past: valueFor(previousIndex, previousYear),
      current: valueFor(currentIndex, now.year),
      next: valueFor(nextIndex, nextYear),
    );
  }

  Future<AnimeWitcherSeasonConfig> getSeasonConfig() async {
    await _refreshRemoteConstants();
    final fallback = _fallbackSeasonConfig();
    return AnimeWitcherSeasonConfig(
      past: _seasonPast.isEmpty ? fallback.past : _seasonPast,
      current: _seasonCurrent.isEmpty ? fallback.current : _seasonCurrent,
      next: _seasonNext.isEmpty ? fallback.next : _seasonNext,
    );
  }

  Future<List<String>> getAllSeasons({bool refresh = false}) async {
    final now = DateTime.now();
    final cached = _allSeasonsCache;
    if (!refresh && cached != null && _allSeasonsExpiresAt.isAfter(now)) {
      return List<String>.unmodifiable(cached);
    }

    final payload = await _getJson(_firestoreUrl('Settings/all_seasons'));
    final fields = payload == null
        ? <String, dynamic>{}
        : _firestoreFields(payload['fields']);
    final values = _list(fields['all_seasons'])
        .map<String>(_text)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (values.isNotEmpty) {
      _allSeasonsCache = values;
      _allSeasonsExpiresAt = now.add(_remoteConstantsTtl);
    }
    return List<String>.unmodifiable(values);
  }

  Future<ProviderMediaPage> getSeasonPage(
    String season, {
    int offset = 0,
    int limit = 30,
  }) async {
    final value = season.trim();
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(10, 50).toInt();
    if (value.isEmpty) {
      return ProviderMediaPage(
        items: const <MultimediaItem>[],
        nextOffset: safeOffset,
        hasMore: false,
      );
    }

    final pageNumber = safeOffset ~/ safeLimit;
    final payload = await _algoliaQuery(
      'series',
      query: '',
      page: pageNumber,
      hitsPerPage: safeLimit,
      filters: _filterGroup('details.season', <String>[value], 'OR'),
      attributes: _searchAttributes,
    );
    final rawHits = _list(payload['hits']);
    final items = await _dedupeHitsWithAniListPosters(rawHits);
    final nbPages = int.tryParse(_text(payload['nbPages'])) ?? 0;
    final hasMore = nbPages > 0
        ? pageNumber + 1 < nbPages
        : rawHits.length >= safeLimit;
    return ProviderMediaPage(
      items: items,
      nextOffset: (pageNumber + 1) * safeLimit,
      hasMore: hasMore,
    );
  }

  Future<Map<String, List<MultimediaItem>>> getBroadcastSchedule() async {
    final values = animeWitcherBroadcastDays
        .map<Map<String, dynamic>>(
          (day) => <String, dynamic>{'stringValue': day},
        )
        .toList(growable: false);
    final raw = await _postAny(
      _firestoreRunQueryUrl(),
      <String, dynamic>{
        'structuredQuery': <String, dynamic>{
          'from': const <Map<String, dynamic>>[
            <String, dynamic>{'collectionId': 'anime_list'},
          ],
          'where': <String, dynamic>{
            'fieldFilter': <String, dynamic>{
              'field': const <String, dynamic>{'fieldPath': 'show_time'},
              'op': 'IN',
              'value': <String, dynamic>{
                'arrayValue': <String, dynamic>{'values': values},
              },
            },
          },
          'limit': 500,
        },
      },
    );

    final grouped = <String, List<Map<String, dynamic>>>{
      for (final day in animeWitcherBroadcastDays)
        day: <Map<String, dynamic>>[],
    };
    for (final rowRaw in _list(raw)) {
      final document = _map(_map(rowRaw)['document']);
      if (document.isEmpty) continue;
      final hit = _firestoreDocumentHit(document);
      if (hit.isEmpty) continue;
      final day = _text(hit['show_time']);
      grouped[day]?.add(hit);
    }

    final lists = await Future.wait(
      animeWitcherBroadcastDays.map(
        (day) => _dedupeHitsWithAniListPosters(grouped[day]!),
      ),
    );
    return <String, List<MultimediaItem>>{
      for (var i = 0; i < animeWitcherBroadcastDays.length; i++)
        animeWitcherBroadcastDays[i]: lists[i],
    };
  }

'''
    provider = replace_once(
        provider,
        '  @override\n  Future<List<MultimediaItem>> search(\n',
        provider_api + '  @override\n  Future<List<MultimediaItem>> search(\n',
        'provider season/schedule API',
    )
    provider_path.write_text(provider, encoding='utf-8')


taskbar_path = Path('lib/core/navigation/taskbar_destination.dart')
taskbar = taskbar_path.read_text(encoding='utf-8')
if "? 'المزيد' : 'More'" not in taskbar:
    taskbar = replace_once(
        taskbar,
        'TaskbarDestination.settings => Icons.settings_outlined,',
        'TaskbarDestination.settings => Icons.more_horiz_rounded,',
        'taskbar icon',
    )
    taskbar = replace_once(
        taskbar,
        'TaskbarDestination.settings => Icons.settings,',
        'TaskbarDestination.settings => Icons.more_horiz_rounded,',
        'taskbar selected icon',
    )
    taskbar = replace_once(
        taskbar,
        'TaskbarDestination.settings => l10n.settings,',
        "TaskbarDestination.settings =>\n      l10n.localeName.toLowerCase().startsWith('ar') ? 'المزيد' : 'More',",
        'taskbar label',
    )
    taskbar_path.write_text(taskbar, encoding='utf-8')


router_path = Path('lib/core/router/app_router.dart')
router = router_path.read_text(encoding='utf-8')
if 'features/more/presentation/more_screen.dart' not in router:
    router = replace_once(
        router,
        "import 'package:skystream/features/settings/presentation/settings_screen.dart';",
        "import 'package:skystream/features/more/presentation/more_screen.dart';",
        'router import',
    )
    router = replace_once(
        router,
        '      const SettingsScreen();',
        '      const MoreScreen();',
        'router settings branch body',
    )
    router_path.write_text(router, encoding='utf-8')


checks = {
    provider_path: ['getSeasonConfig', 'Settings/all_seasons', 'getBroadcastSchedule', "'fieldPath': 'show_time'"],
    taskbar_path: ['المزيد', 'Icons.more_horiz_rounded'],
    router_path: ['MoreScreen'],
}
for path, markers in checks.items():
    text = path.read_text(encoding='utf-8')
    missing = [marker for marker in markers if marker not in text]
    if missing:
        raise RuntimeError(f'{path}: missing markers {missing}')

print('Applied More, Seasons, and Broadcast Schedule source changes.')
