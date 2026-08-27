import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/features/home/presentation/view_all_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a failed provider page can be retried', (tester) async {
    var calls = 0;

    Future<ProviderMediaPage> loadPage(int offset) async {
      calls += 1;
      if (calls == 1) throw StateError('offline');
      return ProviderMediaPage(
        items: const <MultimediaItem>[
          MultimediaItem(
            title: 'Recovered result',
            url: 'https://animewitcher.com/watch/recovered',
            posterUrl: '',
          ),
        ],
        nextOffset: 1,
        hasMore: false,
      );
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

    expect(find.text('Could not load more results.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Recovered result'), findsOneWidget);
  });
}
