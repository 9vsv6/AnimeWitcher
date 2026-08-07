import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/entity/multimedia_item.dart';
import 'library_category.dart';
import 'storage_service.dart';

part 'library_repository.g.dart';

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) {
  return LibraryRepository(ref.watch(storageServiceProvider));
}

class LibraryRepository {
  final StorageService _storageService;

  LibraryRepository(this._storageService);

  Future<void> addToLibrary(
    MultimediaItem item, {
    LibraryCategory? category,
  }) async {
    final target = category ?? getSelectedCategory();
    await _storageService.addToLibrary(
      item,
      category: target.storageKey,
    );
  }

  Future<void> moveToCategory(String url, LibraryCategory category) async {
    await _storageService.setLibraryItemCategory(url, category.storageKey);
  }

  Future<void> removeFromLibrary(String url) async {
    await _storageService.removeFromLibrary(url);
  }

  bool isInLibrary(String url) {
    return _storageService.isInLibrary(url);
  }

  LibraryCategory? getItemCategory(String url) {
    final value = _storageService.getLibraryItemCategory(url);
    return value == null ? null : LibraryCategory.fromStorageKey(value);
  }

  List<MultimediaItem> getLibraryItems({LibraryCategory? category}) {
    return _storageService.getLibraryItems(category: category?.storageKey);
  }

  Future<void> setSelectedCategory(LibraryCategory category) async {
    await _storageService.setSelectedLibraryCategory(category.storageKey);
  }

  LibraryCategory getSelectedCategory() {
    return LibraryCategory.fromStorageKey(
      _storageService.getSelectedLibraryCategory(),
    );
  }
}
