import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/storage/library_category.dart';

void main() {
  test('legacy on-hold values map to Continue Later', () {
    expect(
      LibraryCategory.fromStorageKey('on_Hold'),
      LibraryCategory.continueLater,
    );
    expect(
      LibraryCategory.fromStorageKey('onHold'),
      LibraryCategory.continueLater,
    );
  });

  test('Favorites is independent from primary list categories', () {
    expect(LibraryCategory.favorite.isPrimary, isFalse);
    expect(
      LibraryCategory.primaryValues,
      containsAll(<LibraryCategory>[
        LibraryCategory.watching,
        LibraryCategory.continueLater,
        LibraryCategory.planToWatch,
        LibraryCategory.completed,
        LibraryCategory.notInterested,
      ]),
    );
    expect(
      LibraryCategory.primaryValues,
      isNot(contains(LibraryCategory.favorite)),
    );
  });
}
