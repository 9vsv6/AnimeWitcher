import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_category.dart';

enum LibrarySortOrder {
  favorite,
  productionDateAsc,
  productionDateDesc,
  titleAsc,
  titleDesc,
  latestAdded,
}

sealed class LibraryState {
  final LibraryCategory category;
  final LibrarySortOrder sortOrder;
  const LibraryState(this.category, this.sortOrder);
}

class LibraryLoading extends LibraryState {
  const LibraryLoading(super.category, super.sortOrder);
}

class LibraryEmpty extends LibraryState {
  const LibraryEmpty(super.category, super.sortOrder);
}

class LibrarySuccess extends LibraryState {
  final List<MultimediaItem> items;
  const LibrarySuccess(this.items, super.category, super.sortOrder);
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message, super.category, super.sortOrder);
}
