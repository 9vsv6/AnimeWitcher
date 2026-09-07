from pathlib import Path

path = Path('lib/core/extensions/providers/animewitcher_native_provider.dart')
text = path.read_text(encoding='utf-8')

if 'Future<ProviderMediaPage> getStudioPage(' not in text:
    marker = '  Future<ProviderMediaPage> _mediaPageFromAlgolia(\n'
    if marker not in text:
        raise RuntimeError('studio page insertion marker not found')
    method = '''  /// Loads anime that belong to exactly the same AnimeWitcher studio.\n  /// Uses the studio facet directly instead of a fuzzy text search.\n  Future<ProviderMediaPage> getStudioPage(\n    String studio, {\n    int offset = 0,\n    int limit = 30,\n  }) async {\n    final value = studio.trim();\n    final safeOffset = offset < 0 ? 0 : offset;\n    if (value.isEmpty) {\n      return ProviderMediaPage(\n        items: const <MultimediaItem>[],\n        nextOffset: safeOffset,\n        hasMore: false,\n      );\n    }\n\n    await _refreshRemoteConstants();\n    if (_algoliaBrowseApiKey.isEmpty) {\n      throw StateError('AnimeWitcher studio catalog request failed.');\n    }\n\n    final safeLimit = limit.clamp(1, _mainListBrowseHitsPerPage).toInt();\n    final pageNumber = safeOffset ~/ safeLimit;\n    final payload = await _algoliaBrowseGet(\n      index: 'series',\n      appId: _algoliaAppId,\n      apiKey: _algoliaBrowseApiKey,\n      page: pageNumber,\n      hitsPerPage: safeLimit,\n      filters: _filterGroup('details.studio', <String>[value], 'OR'),\n      attributes: _searchAttributes,\n      throwOnFailure: true,\n    );\n    return _mediaPageFromAlgolia(\n      payload,\n      pageNumber: pageNumber,\n      hitsPerPage: safeLimit,\n    );\n  }\n\n'''
    text = text.replace(marker, method + marker, 1)

path.write_text(text, encoding='utf-8')
print('studio page patch applied')
