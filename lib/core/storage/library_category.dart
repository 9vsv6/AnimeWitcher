enum LibraryCategory {
  favorite('favorite'),
  watching('watching'),
  planToWatch('pinned'),
  completed('completed'),
  notInterested('noWatching');

  final String storageKey;
  const LibraryCategory(this.storageKey);

  static LibraryCategory fromStorageKey(String? raw) {
    final value = (raw ?? '').trim();
    // The removed On Hold category is migrated into Plan to Watch so existing
    // saved items never disappear after the UI option is removed.
    if (value == 'on_Hold' || value == 'onHold') {
      return LibraryCategory.planToWatch;
    }
    for (final category in LibraryCategory.values) {
      if (category.storageKey == value) return category;
    }
    if (value == 'no_watching') return LibraryCategory.notInterested;
    return LibraryCategory.favorite;
  }
}
