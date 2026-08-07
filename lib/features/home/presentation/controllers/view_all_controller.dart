import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../view_all_screen.dart';

part 'view_all_controller.g.dart';

class ViewAllState {
  final ViewAllCategory? category;
  final List<MultimediaItem> items;
  final int page;
  final bool isLoading;
  final bool hasMore;

  const ViewAllState({
    this.category,
    this.items = const [],
    this.page = 1,
    this.isLoading = false,
    this.hasMore = false,
  });

  ViewAllState copyWith({
    ViewAllCategory? category,
    List<MultimediaItem>? items,
    int? page,
    bool? isLoading,
    bool? hasMore,
  }) => ViewAllState(
        category: category ?? this.category,
        items: items ?? this.items,
        page: page ?? this.page,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
      );
}

@riverpod
class ViewAllController extends _$ViewAllController {
  @override
  ViewAllState build(ViewAllCategory category) => ViewAllState(category: category);

  void init(List<MultimediaItem> initialItems) {
    if (state.items.isEmpty) {
      state = state.copyWith(items: List<MultimediaItem>.from(initialItems));
    }
  }

  void setProviderContentLoading(bool value) =>
      state = state.copyWith(isLoading: value);

  void replaceProviderContent(List<MultimediaItem> items) => state = state.copyWith(
        items: List<MultimediaItem>.from(items),
        isLoading: false,
        hasMore: false,
      );

  Future<void> fetchNextPage() async {}
}
