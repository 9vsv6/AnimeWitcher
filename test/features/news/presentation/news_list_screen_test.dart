import 'dart:io';
import 'dart:ui' as ui;

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/extensions/base_provider.dart';
import 'package:animewitcher/features/home/presentation/widgets/news_card.dart';
import 'package:animewitcher/features/news/presentation/news_list_screen.dart';
import 'package:animewitcher/features/news/presentation/news_utils.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_fonts.dart';
import '../../../support/debug_shots.dart';

NewsItem _item(String id, {String? title}) {
  return NewsItem(
    id: id,
    title: title ?? 'خبر $id',
    imageUrl: '',
    publishedAt: DateTime.now().subtract(Duration(hours: int.parse(id))),
  );
}

List<NewsItem> _items(int count) => [
  _item(
    '1',
    title: 'كرانشي رول ستجلب فيلم أنمي The Apothecary Diaries إلى دور السينما',
  ),
  for (var i = 2; i <= count; i++) _item('$i'),
];

Widget _app(Size size, List<NewsItem> items) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSansArabic',
        scaffoldBackgroundColor: Colors.black,
      ),
      home: RepaintBoundary(
        key: const ValueKey('news-shot'),
        child: NewsListScreen(
          initialItems: items,
          loadPage: (offset, limit) async => const ProviderNewsPage(
            items: <NewsItem>[],
            nextOffset: 0,
            hasMore: false,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size, int count) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(TestFonts.loadWalkthroughFonts);
  await tester.pumpWidget(_app(size, _items(count)));
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final artifacts = debugShotDirectory();
  if (artifacts == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('news-shot')),
    );
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${artifacts.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key)));

void main() {
  test('the magazine grid widens with the window', () {
    expect(NewsMagazineLayout.forWidth(366).columns, 2);
    expect(NewsMagazineLayout.forWidth(366).wideLead, isFalse);
    expect(NewsMagazineLayout.forWidth(640).wideLead, isTrue);
    expect(NewsMagazineLayout.forWidth(820).columns, 3);
    expect(NewsMagazineLayout.forWidth(1240).columns, 4);
    expect(NewsMagazineLayout.forWidth(1240).leadCount(2), 1);
    expect(NewsMagazineLayout.forWidth(1240).leadCount(9), 3);
  });

  testWidgets(
    'a tablet or computer shows one large story beside two, then four across',
    (tester) async {
      await _pumpAt(tester, const Size(1280, 800), 11);

      expect(tester.takeException(), isNull);
      expect(find.byType(NewsFeatureTile), findsNWidgets(3));
      expect(find.byType(AppPageAppBar), findsOneWidget);

      final lead = _rect(tester, 'news-lead-1');
      final second = _rect(tester, 'news-lead-2');
      final third = _rect(tester, 'news-lead-3');
      // Below the floating header, the newest story large on the reading side.
      expect(lead.top, greaterThan(kToolbarHeight));
      expect(lead.center.dx, greaterThan(second.center.dx));
      expect(lead.width, greaterThan(second.width * 1.5));
      // The other two stacked in one column beside it.
      expect((second.left - third.left).abs(), lessThan(1));
      expect(third.top, greaterThan(second.bottom - 1));
      expect((third.bottom - lead.bottom).abs(), lessThan(1));

      // Then a row of four.
      final row = [for (var i = 4; i <= 7; i++) _rect(tester, 'news-tile-$i')];
      for (final tile in row) {
        expect((tile.top - row.first.top).abs(), lessThan(1));
      }
      expect(row.first.top, greaterThan(lead.bottom));
      expect(row.first.center.dx, greaterThan(row.last.center.dx));
      await _shot(tester, 'news_magazine_desktop');
    },
  );

  // A phone keeps the plain list it had before the magazine.
  test('news list uses two columns in landscape and one in portrait', () {
    expect(newsListColumnCount(const Size(390, 844)), 1);
    expect(newsListColumnCount(const Size(844, 390)), 2);
    expect(
      newsListLandscapeMainAxisExtent(
        size: const Size(844, 390),
        padding: EdgeInsets.zero,
      ),
      closeTo(294, 0.5),
    );
  });

  testWidgets('news list scrolls under the progressive page header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(const Size(390, 844), <NewsItem>[_item('1'), _item('2')]),
    );
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    expect(find.byType(AppPageAppBar), findsOneWidget);

    final list = tester.widget<ListView>(find.byType(ListView).first);
    final padding = list.padding!.resolve(TextDirection.ltr);
    expect(padding.top, greaterThan(kToolbarHeight));
  });

  testWidgets('landscape news page places two articles on the first row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(TestFonts.loadWalkthroughFonts);

    await tester.pumpWidget(
      _app(const Size(844, 390), <NewsItem>[
        _item(
          '1',
          title:
              'الموسم الرابع من أنمي JUJUTSU KAISEN يكشف عن ملصق تشويقي مثير',
        ),
        _item('2'),
        _item('3'),
      ]),
    );
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(NewsCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    final first = tester.getRect(find.byType(NewsCard).at(0));
    final second = tester.getRect(find.byType(NewsCard).at(1));
    final third = tester.getRect(find.byType(NewsCard).at(2));
    expect((first.center.dy - second.center.dy).abs(), lessThan(2));
    expect(first.center.dx, greaterThan(second.center.dx));
    expect(third.top, greaterThan(first.bottom - 1));

    final artifacts = debugShotDirectory();
    if (artifacts == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('news-shot')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${artifacts.path}/news_list_landscape_two_per_row.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('portrait news page keeps one article per row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(const Size(390, 844), <NewsItem>[_item('1'), _item('2')]),
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    final first = tester.getRect(find.text('خبر 1'));
    final second = tester.getRect(find.text('خبر 2'));
    expect(second.top, greaterThan(first.bottom - 1));
  });
}
