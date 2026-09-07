import 'dart:async';

import 'package:animewitcher/core/account/account_providers.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/network/dio_client_provider.dart';
import 'package:animewitcher/core/storage/library_category.dart';
import 'package:animewitcher/core/storage/library_repository.dart';
import 'package:animewitcher/core/utils/catalog_metadata_enricher.dart';
import 'package:animewitcher/core/utils/catalog_rating.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import './library_auth.dart';
import './library_state.dart';

part 'library_provider.g.dart';

@Riverpod(keepAlive: true)
class Library extends _$Library {
  final Map<String, MultimediaItem> _metadataCache = <String, MultimediaItem>{};
  final Set<String> _metadataInFlight = <String>{};

  @override
  LibraryState build() {
    ref.watch(accountDataRevisionProvider);
    final repository = ref.read(libraryRepositoryProvider);
    final category = repository.getSelectedCategory();
    final items = _withCachedMetadata(
      repository.getLibraryItems(category: category),
    );
    _scheduleMetadataEnrichment(items, category);
    return items.isEmpty
        ? LibraryEmpty(category)
        : LibrarySuccess(items, category);
  }

  LibraryCategory get selectedCategory => state.category;

  LibraryState refresh({LibraryCategory? category}) {
    final repository = ref.read(libraryRepositoryProvider);
    final selected = category ?? state.category;
    final items = _withCachedMetadata(
      repository.getLibraryItems(category: selected),
    );
    state = items.isEmpty
        ? LibraryEmpty(selected)
        : LibrarySuccess(items, selected);
    _scheduleMetadataEnrichment(items, selected);
    return state;
  }

  List<MultimediaItem> _withCachedMetadata(List<MultimediaItem> items) {
    return items
        .map((item) {
          final metadata = _metadataCache[item.url];
          return metadata == null
              ? item
              : CatalogMetadataEnricher.merge(item, metadata);
        })
        .toList(growable: false);
  }

  void _scheduleMetadataEnrichment(
    List<MultimediaItem> items,
    LibraryCategory category,
  ) {
    final pending = items
        .where(
          (item) =>
              !_metadataInFlight.contains(item.url) &&
              (item.year == null || preferredCatalogRating(item) == null),
        )
        .toList(growable: false);
    if (pending.isEmpty) return;
    _metadataInFlight.addAll(pending.map((item) => item.url));
    unawaited(_enrichMetadata(pending, category));
  }

  Future<void> _enrichMetadata(
    List<MultimediaItem> pending,
    LibraryCategory category,
  ) async {
    try {
      final enriched = await CatalogMetadataEnricher.enrich(
        ref.read(dioClientProvider),
        pending,
      );
      var changed = false;
      for (var index = 0; index < enriched.length; index++) {
        final before = pending[index];
        final after = enriched[index];
        final gainedYear = before.year == null && after.year != null;
        final gainedRating =
            preferredCatalogRating(before) == null &&
            preferredCatalogRating(after) != null;
        if (!gainedYear && !gainedRating) continue;
        _metadataCache[before.url] = after;
        changed = true;
      }
      if (!changed || state.category != category) return;

      final repository = ref.read(libraryRepositoryProvider);
      final items = _withCachedMetadata(
        repository.getLibraryItems(category: category),
      );
      state = items.isEmpty
          ? LibraryEmpty(category)
          : LibrarySuccess(items, category);
    } finally {
      _metadataInFlight.removeAll(pending.map((item) => item.url));
    }
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
    _requireSignedIn();
    final repository = ref.read(libraryRepositoryProvider);
    await repository.addToLibrary(
      item,
      category: category ?? state.category,
    );
    refresh();
  }

  Future<void> clearItemCategory(String url) async {
    _requireSignedIn();
    final repository = ref.read(libraryRepositoryProvider);
    await repository.clearCategory(url);
    refresh();
  }

  Future<void> setFavorite(MultimediaItem item, bool favorite) async {
    _requireSignedIn();
    final repository = ref.read(libraryRepositoryProvider);
    await repository.setFavorite(item, favorite);
    refresh();
  }

  void _requireSignedIn() {
    requireLibrarySignIn(
      ref.read(animeWitcherAccountServiceProvider).isSignedIn,
    );
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
