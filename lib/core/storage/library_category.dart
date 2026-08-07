enum LibraryCategory {
  favorite('favorite'),
  watching('watching'),
  planToWatch('pinned'),
  completed('completed'),
  onHold('onHold'),
  notInterested('noWatching');

  final String storageKey;
  const LibraryCategory(this.storageKey);

  static LibraryCategory fromStorageKey(String? raw) {
    final value = (raw ?? '').trim();
    for (final category in LibraryCategory.values) {
      if (category.storageKey == value) return category;
    }
    if (value == 'on_Hold') return LibraryCategory.onHold;
    if (value == 'no_watching') return LibraryCategory.notInterested;
    return LibraryCategory.favorite;
  }
}
