enum LibraryCategory {
  favorite('favorite'),
  watching('watching'),
  continueLater('onHold'),
  planToWatch('pinned'),
  completed('completed'),
  notInterested('noWatching');

  final String storageKey;
  const LibraryCategory(this.storageKey);

  bool get isPrimary => this != LibraryCategory.favorite;

  static const List<LibraryCategory> primaryValues = <LibraryCategory>[
    LibraryCategory.watching,
    LibraryCategory.continueLater,
    LibraryCategory.planToWatch,
    LibraryCategory.completed,
    LibraryCategory.notInterested,
  ];

  static LibraryCategory fromStorageKey(String? raw) {
    final value = (raw ?? '').trim();
    if (value == 'on_Hold' ||
        value == 'onHold' ||
        value == 'continueLater' ||
        value == 'continue_later') {
      return LibraryCategory.continueLater;
    }
    for (final category in LibraryCategory.values) {
      if (category.storageKey == value) return category;
    }
    if (value == 'no_watching') return LibraryCategory.notInterested;
    if (value == 'pin') return LibraryCategory.planToWatch;
    return LibraryCategory.favorite;
  }
}
