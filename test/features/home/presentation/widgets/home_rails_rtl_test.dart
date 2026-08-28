import 'dart:io';
import 'dart:ui' as ui;

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/home/presentation/view_all_screen.dart';
import 'package:animewitcher/features/home/presentation/widgets/home_section_header.dart';
import 'package:animewitcher/features/home/presentation/widgets/media_horizontal_list.dart';
import 'package:animewitcher/features/home/presentation/widgets/news_section.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

MultimediaItem _anime(String title, String id) {
  return MultimediaItem(
    title: title,
    url: 'https://animewitcher.test/watch/$id',
    posterUrl: '',
  );
}

NewsItem _news(String title, String id) {
  return NewsItem(id: id, title: title, imageUrl: '');
}

Widget _rtlApp({required Widget child, Size? size}) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFEEC60A),
        surface: Color(0xFF000000),
        onSurface: Color(0xFFE5E7EB),
      ),
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: size?.width, child: child),
      ),
    ),
  );
}

MediaHorizontalList _rail({required String title, required List<String> ids}) {
  return MediaHorizontalList(
    title: title,
    mediaList: [for (final id in ids) _anime(id, id)],
    category: ViewAllCategory.providerContent,
    showViewAll: true,
    onTap: (_) {},
    heroTagPrefix: title,
    forcePortrait: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home header puts the title on the right and view-all on the left',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _rtlApp(
          child: HomeSectionHeader(
            title: 'الحلقات الجديدة',
            action: HomeViewAllButton(onTap: () {}),
          ),
        ),
      );
      await tester.pump();

      final titleBox = tester.getRect(find.text('الحلقات الجديدة'));
      final viewAllBox = tester.getRect(find.text('عرض الكل'));
      expect(titleBox.left, greaterThan(viewAllBox.left));
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);

      final labelRight = tester.getTopRight(find.text('عرض الكل')).dx;
      final chevronLeft = tester
          .getTopLeft(find.byIcon(Icons.arrow_back_ios_new))
          .dx;
      expect(
        chevronLeft,
        greaterThan(labelRight - 1),
        reason: 'chevron comes after عرض الكل and points left',
      );
    },
  );

  testWidgets('latest-episode rail starts on the right', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const title = 'الحلقات الجديدة';
    await tester.pumpWidget(
      _rtlApp(
        child: _rail(
          title: title,
          ids: const ['FirstShow', 'SecondShow', 'ThirdShow'],
        ),
      ),
    );
    await tester.pump();

    final first = tester.getTopLeft(
      find.byKey(const ValueKey('$title-rail-0')),
    );
    final last = tester.getTopLeft(find.byKey(const ValueKey('$title-rail-2')));
    expect(first.dx, greaterThan(last.dx));
  });

  testWidgets('latest-added, most-watched, and news rails start on the right', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const latestAdded = 'آخر الأعمال المضافة';
    const mostWatched = 'الانميشن الاكثر مشاهدة';
    const newsTitle = 'الأخبار';

    await tester.pumpWidget(
      _rtlApp(
        child: ListView(
          children: [
            _rail(
              title: latestAdded,
              ids: const ['AddedOne', 'AddedTwo', 'AddedThree'],
            ),
            _rail(
              title: mostWatched,
              ids: const ['WatchOne', 'WatchTwo', 'WatchThree'],
            ),
            NewsSection(
              title: newsTitle,
              items: [
                _news('خبر أول', 'n1'),
                _news('خبر ثان', 'n2'),
                _news('خبر ثالث', 'n3'),
              ],
              onViewAll: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final addedFirst = tester.getTopLeft(
      find.byKey(const ValueKey('$latestAdded-rail-0')),
    );
    final addedLast = tester.getTopLeft(
      find.byKey(const ValueKey('$latestAdded-rail-2')),
    );
    expect(addedFirst.dx, greaterThan(addedLast.dx));

    final watchedFirst = tester.getTopLeft(
      find.byKey(const ValueKey('$mostWatched-rail-0')),
    );
    final watchedLast = tester.getTopLeft(
      find.byKey(const ValueKey('$mostWatched-rail-2')),
    );
    expect(watchedFirst.dx, greaterThan(watchedLast.dx));

    final newsFirst = tester.getTopLeft(
      find.byKey(const ValueKey('news-rail-n1')),
    );
    final newsLast = tester.getTopLeft(
      find.byKey(const ValueKey('news-rail-n3')),
    );
    expect(newsFirst.dx, greaterThan(newsLast.dx));

    expect(find.text(latestAdded), findsOneWidget);
    expect(find.text(mostWatched), findsOneWidget);
    expect(find.text(newsTitle), findsOneWidget);
    expect(find.text('عرض الكل'), findsNWidgets(3));
  });

  testWidgets('home rails screenshot for walkthrough', (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _rtlApp(
        size: size,
        child: RepaintBoundary(
          key: const ValueKey('home-rails-shot'),
          child: ColoredBox(
            color: Colors.black,
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                _rail(
                  title: 'الحلقات الجديدة',
                  ids: const [
                    'Bai Ri Cheng Wang',
                    'Shiguang Dailiren III',
                    'Otome Kaijuu',
                  ],
                ),
                _rail(
                  title: 'آخر الأعمال المضافة',
                  ids: const ['The Mighty B!', 'Evangelion Movie', 'Lupin III'],
                ),
                _rail(
                  title: 'الانميشن الاكثر مشاهدة',
                  ids: const ['Most One', 'Most Two', 'Most Three'],
                ),
                NewsSection(
                  title: 'الأخبار',
                  items: [
                    _news('خبر الأنمي الأول', 'shot-n1'),
                    _news('خبر الأنمي الثاني', 'shot-n2'),
                    _news('خبر الأنمي الثالث', 'shot-n3'),
                  ],
                  onViewAll: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final artifacts = Directory('/opt/cursor/artifacts');
    if (!artifacts.existsSync()) {
      return;
    }

    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('home-rails-shot')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${artifacts.path}/home_rails_rtl_phone.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
