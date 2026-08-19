import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:skystream/core/account/account_providers.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_category.dart';
import '../../../../core/storage/library_repository.dart';

import './library_state.dart';

part 'library_provider.g.dart';

@Riverpod(keepAlive: true)
class Library extends _$Library {
  @override
  LibraryState build() {
    ref.watch(accountDataRevisionProvider);
    final repository = ref.read(libraryRepositoryProvider);
    final category = repository.getSelectedCategory();
    final items = _sortByLatestAdded(
      repository.getLibraryItems(category: category),
      repository,
    );
    return items.isEmpty
        ? LibraryEmpty(category)
        : LibrarySuccess(items, category);
  }

  LibraryCategory get selectedCategory => state.category;

  LibraryState refresh({LibraryCategory? category}) {
    final repository = ref.read(libraryRepositoryProvider);
    final selected = category ?? state.category;
    final items = _sortByLatestAdded(
      repository.getLibraryItems(category: selected),
      repository,
    );
    state = items.isEmpty
        ? LibraryEmpty(selected)
        : LibrarySuccess(items, selected);
    return state;
  }

  List<MultimediaItem> _sortByLatestAdded(
    List<MultimediaItem> source,
    LibraryRepository repository,
  ) {
    final items = List<MultimediaItem>.from(source);
    items.sort((a, b) {
      final added = repository
          .getLibraryItemUpdatedAt(b.url)
          .compareTo(repository.getLibraryItemUpdatedAt(a.url));
      if (added != 0) return added;
      return 0;
    });
    return items;
  }

  Future<void> selectCategory(LibraryCategory category) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.setSelectedCategory(category);
    refresh(category: category);
  }

  Future<void> addItem(
    MultimediaItem item, {
    LibraryCategory? category,
  }) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.addToLibrary(
      item,
      category: category ?? state.category,
    );
    refresh();
  }

  Future<void> clearItemCategory(String url) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.clearCategory(url);
    refresh();
  }

  Future<void> setFavorite(MultimediaItem item, bool favorite) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.setFavorite(item, favorite);
    refresh();
  }

  bool isFavorite(String url) {
    final repository = ref.read(libraryRepositoryProvider);
    return repository.isFavorite(url);
  }

  LibraryCategory? itemCategory(String url) {
    final repository = ref.read(libraryRepositoryProvider);
    return repository.getItemCategory(url);
  }
}
