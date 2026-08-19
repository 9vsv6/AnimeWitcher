import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_category.dart';

sealed class LibraryState {
  final LibraryCategory category;
  const LibraryState(this.category);
}

class LibraryLoading extends LibraryState {
  const LibraryLoading(super.category);
}

class LibraryEmpty extends LibraryState {
  const LibraryEmpty(super.category);
}

class LibrarySuccess extends LibraryState {
  final List<MultimediaItem> items;
  const LibrarySuccess(this.items, super.category);
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message, super.category);
}
