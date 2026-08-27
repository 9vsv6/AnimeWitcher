import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/features/home/presentation/view_all_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderMediaPage _page(List<MultimediaItem> items, {bool hasMore = false}) {
  return ProviderMediaPage(
    items: items,
    nextOffset: items.length,
    hasMore: hasMore,
  );
}

MultimediaItem _item(String title, String id) {
  return MultimediaItem(
    title: title,
    url: 'https://animewitcher.com/watch/$id',
    posterUrl: '',
  );
}

void main() {
  testWidgets('a failed first page can be retried', (tester) async {
    var calls = 0;

    Future<ProviderMediaPage> loadPage(int offset) async {
      calls += 1;
      if (calls == 1) throw StateError('offline');
      return _page(<MultimediaItem>[_item('Recovered result', 'recovered')]);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ViewAllScreen(
          title: 'All titles',
          initialMediaList: const <MultimediaItem>[],
          category: ViewAllCategory.providerContent,
          loadPage: loadPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل النتائج.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Recovered result'), findsWidgets);
  });

  testWidgets('a failed later page keeps results and can be retried', (
    tester,
  ) async {
    var calls = 0;

    Future<ProviderMediaPage> loadPage(int offset) async {
      calls += 1;
      if (calls == 1) {
        return _page(<MultimediaItem>[
          _item('First result', 'first'),
        ], hasMore: true);
      }
      if (calls == 2) throw StateError('offline');
      return _page(<MultimediaItem>[_item('Second result', 'second')]);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ViewAllScreen(
          title: 'All titles',
          initialMediaList: const <MultimediaItem>[],
          category: ViewAllCategory.providerContent,
          loadPage: loadPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First result'), findsWidgets);
    expect(find.text('تعذر تحميل المزيد من النتائج.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(calls, 3);
    expect(find.text('First result'), findsWidgets);
    expect(find.text('Second result'), findsWidgets);
  });
}
