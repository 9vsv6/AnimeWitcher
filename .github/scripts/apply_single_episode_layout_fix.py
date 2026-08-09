from pathlib import Path

controller_path = Path('lib/features/details/presentation/details_controller.dart')
controller = controller_path.read_text(encoding='utf-8')

old = "isMovie: contextItem.contentType == MultimediaContentType.movie,"
new = """isMovie:
            contextItem.contentType == MultimediaContentType.movie ||
            contextItem.contentType == MultimediaContentType.livestream,"""
if controller.count(old) != 1:
    raise SystemExit(f'Unexpected empty-episode movie marker count: {controller.count(old)}')
controller = controller.replace(old, new, 1)

old = """    bool isMovie =
        contextItem.contentType == MultimediaContentType.movie ||
        contextItem.contentType == MultimediaContentType.livestream;"""
new = """    final isMovie =
        contextItem.contentType == MultimediaContentType.movie ||
        contextItem.contentType == MultimediaContentType.livestream;"""
if controller.count(old) != 1:
    raise SystemExit(f'Unexpected isMovie declaration count: {controller.count(old)}')
controller = controller.replace(old, new, 1)

old = """    if (!isMovie && episodes.length == 1) {
      isMovie = true;
    }
"""
new = """    // Episode count must not decide the page layout. A one-episode anime/OVA/
    // special is still episodic content and should keep the same Details /
    // Episodes UI as every other anime. Reclassifying it as a movie only after
    // the episodes request finishes caused the mobile page to visibly switch
    // layouts for a fraction of a second while loading.
"""
if controller.count(old) != 1:
    raise SystemExit(f'Unexpected single-episode heuristic count: {controller.count(old)}')
controller = controller.replace(old, new, 1)
controller_path.write_text(controller, encoding='utf-8')

provider_path = Path('lib/core/extensions/providers/animewitcher_native_provider.dart')
provider = provider_path.read_text(encoding='utf-8')
old = """    final value = _text(raw).toLowerCase();
    return value.contains('فيلم') ||
        value == 'movie' ||"""
new = """    final value = _text(raw).trim().toLowerCase();
    return value.contains('فيلم') ||
        value.contains('فلم') ||
        value == 'movie' ||"""
if provider.count(old) != 1:
    raise SystemExit(f'Unexpected AnimeWitcher movie parser count: {provider.count(old)}')
provider = provider.replace(old, new, 1)
provider_path.write_text(provider, encoding='utf-8')

controller = controller_path.read_text(encoding='utf-8')
provider = provider_path.read_text(encoding='utf-8')
assert 'episodes.length == 1' not in controller
assert "value.contains('فلم')" in provider
assert controller.count('{') == controller.count('}')
assert provider.count('{') == provider.count('}')
