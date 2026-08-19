import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:skystream/core/account/account_providers.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_category.dart';
import '../../../../core/storage/library_repository.dart';

import './library_state.dart';

part 'library_provider.g.dart';

/// The ordering modes exposed by the Library sort menu.
enum LibrarySortOrder {
  favorite,
  productionDateAsc,
  productionDateDesc,
  titleAsc,
  titleDesc,
  latestAdded,
}

final librarySortOrderProvider =
    StateProvider<LibrarySortOrder>((ref) => LibrarySortOrder.favorite);

@Riverpod(keepAlive: true)
class Library extends _$Library {
  @override
  LibraryState build() {
    ref.watch(accountDataRevisionProvider);
    final repository = ref.read(libraryRepositoryProvider);
    final category = repository.getSelectedCategory();
    final sortOrder = ref.watch(librarySortOrderProvider);
    final items = _sortItems(
      repository.getLibraryItems(category: category),
      repository,
      sortOrder,
    );
    return items.isEmpty
        ? LibraryEmpty(category)
        : LibrarySuccess(items, category);
  }

  LibraryCategory get selectedCategory => state.category;

  LibraryState refresh({LibraryCategory? category}) {
    final repository = ref.read(libraryRepositoryProvider);
    final selected = category ?? state.category;
    final sortOrder = ref.read(librarySortOrderProvider);
    final items = _sortItems(
      repository.getLibraryItems(category: selected),
      repository,
      sortOrder,
    );
    state = items.isEmpty
        ? LibraryEmpty(selected)
        : LibrarySuccess(items, selected);
    return state;
  }

  LibrarySortOrder get sortOrder => ref.read(librarySortOrderProvider);

  Future<void> selectSortOrder(LibrarySortOrder sortOrder) async {
    ref.read(librarySortOrderProvider.notifier).state = sortOrder;
  }

  Future<void> selectCategory(LibraryCategory category) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.setSelectedCategory(category);
    refresh(category: category);
  }


  List<MultimediaItem> _sortItems(
    List<MultimediaItem> source,
    LibraryRepository repository,
    LibrarySortOrder order,
  ) {
    final items = List<MultimediaItem>.from(source);

    int titleCompare(MultimediaItem a, MultimediaItem b) {
      return a.title.trim().toLowerCase().compareTo(
        b.title.trim().toLowerCase(),
      );
    }

    int yearCompare(MultimediaItem a, MultimediaItem b) {
      return (a.year ?? 0).compareTo(b.year ?? 0);
    }

    int addedCompare(MultimediaItem a, MultimediaItem b) {
      return repository
          .getLibraryItemUpdatedAt(b.url)
          .compareTo(repository.getLibraryItemUpdatedAt(a.url));
    }

    int favoriteCompare(MultimediaItem a, MultimediaItem b) {
      final aFavorite = repository.isFavorite(a.url) ? 0 : 1;
      final bFavorite = repository.isFavorite(b.url) ? 0 : 1;
      return aFavorite.compareTo(bFavorite);
    }

    items.sort((a, b) {
      switch (order) {
        case LibrarySortOrder.favorite:
          final favorite = favoriteCompare(a, b);
          return favorite != 0 ? favorite : addedCompare(a, b);
        case LibrarySortOrder.productionDateAsc:
          final year = yearCompare(a, b);
          return year != 0 ? year : titleCompare(a, b);
        case LibrarySortOrder.productionDateDesc:
          final year = yearCompare(b, a);
          return year != 0 ? year : titleCompare(a, b);
        case LibrarySortOrder.titleAsc:
          return titleCompare(a, b);
        case LibrarySortOrder.titleDesc:
          return titleCompare(b, a);
        case LibrarySortOrder.latestAdded:
          final added = addedCompare(a, b);
          return added != 0 ? added : titleCompare(a, b);
      }
    });

    return items;
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
