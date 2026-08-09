import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../account/account_providers.dart';
import '../account/animewitcher_account_service.dart';
import '../domain/entity/multimedia_item.dart';
import 'library_category.dart';
import 'storage_service.dart';

part 'library_repository.g.dart';

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) {
  return LibraryRepository(
    ref.watch(storageServiceProvider),
    ref.watch(animeWitcherAccountServiceProvider),
  );
}

class LibraryRepository {
  final StorageService _storageService;
  final AnimeWitcherAccountService _accountService;

  LibraryRepository(this._storageService, this._accountService);

  Future<void> addToLibrary(
    MultimediaItem item, {
    LibraryCategory? category,
  }) async {
    final target = category ?? getSelectedCategory();
    await _storageService.addToLibrary(
      item,
      category: target.storageKey,
    );
    _syncInBackground(
      _accountService.saveLibraryItem(item, target),
      'save library item',
    );
  }

  Future<void> moveToCategory(String url, LibraryCategory category) async {
    await _storageService.setLibraryItemCategory(url, category.storageKey);
    final item = _findItem(url);
    if (item != null) {
      _syncInBackground(
        _accountService.saveLibraryItem(item, category),
        'move library item',
      );
    }
  }

  Future<void> removeFromLibrary(String url) async {
    await _storageService.removeFromLibrary(url);
    _syncInBackground(
      _accountService.removeLibraryItem(url),
      'remove library item',
    );
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

  MultimediaItem? _findItem(String url) {
    for (final item in _storageService.getLibraryItems()) {
      if (item.url == url) return item;
    }
    return null;
  }

  void _syncInBackground(Future<void> operation, String label) {
    unawaited(
      operation.catchError((Object error) {
        if (kDebugMode) {
          debugPrint('[AnimeWitcherAccount] Could not $label: $error');
        }
      }),
    );
  }
}
