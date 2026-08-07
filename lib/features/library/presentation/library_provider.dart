import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_category.dart';
import '../../../../core/storage/library_repository.dart';

import './library_state.dart';

part 'library_provider.g.dart';

@Riverpod(keepAlive: true)
class Library extends _$Library {
  @override
  LibraryState build() {
    final repository = ref.read(libraryRepositoryProvider);
    final category = repository.getSelectedCategory();
    final items = repository.getLibraryItems(category: category);
    return items.isEmpty
        ? LibraryEmpty(category)
        : LibrarySuccess(items, category);
  }

  LibraryCategory get selectedCategory => state.category;

  LibraryState refresh({LibraryCategory? category}) {
    final repository = ref.read(libraryRepositoryProvider);
    final selected = category ?? state.category;
    final items = repository.getLibraryItems(category: selected);
    state = items.isEmpty
        ? LibraryEmpty(selected)
        : LibrarySuccess(items, selected);
    return state;
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

  Future<void> moveItem(String url, LibraryCategory category) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.moveToCategory(url, category);
    refresh();
  }

  Future<void> removeItem(String url) async {
    final repository = ref.read(libraryRepositoryProvider);
    await repository.removeFromLibrary(url);
    refresh();
  }

  bool isBookmarked(String url) {
    final repository = ref.read(libraryRepositoryProvider);
    return repository.isInLibrary(url);
  }

  LibraryCategory? itemCategory(String url) {
    final repository = ref.read(libraryRepositoryProvider);
    return repository.getItemCategory(url);
  }

  Future<void> clearAll() async {
    // repository.clearAll() if it exists
  }
}
