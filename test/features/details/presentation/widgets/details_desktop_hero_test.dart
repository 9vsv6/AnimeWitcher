import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/widgets/details_desktop_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'portrait phone hero keeps a wide banner below the top isolation and centers info on the larger poster',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final item = MultimediaItem(
        title: 'One Piece',
        url: 'https://example.test/one-piece',
        posterUrl: '',
        bannerUrl: '',
        catalogType: 'مسلسل',
        year: 1999,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                viewPadding: EdgeInsets.only(top: 44),
              ),
              child: Scaffold(
                body: DetailsDesktopHero(
                  compact: true,
                  showPoster: true,
                  displayItem: item,
                  details: item,
                  detailsState: AsyncValue<MultimediaItem?>.data(item),
                  isMovie: false,
                  itemUrl: item.url,
                  onRefresh: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final banner = find.byKey(
        const ValueKey<String>('details-hero-portrait-banner'),
      );
      final poster = find.byKey(const ValueKey<String>('details-hero-poster'));
      final info = find.byKey(const ValueKey<String>('details-hero-info'));

      expect(banner, findsOneWidget);
      expect(poster, findsOneWidget);
      expect(info, findsOneWidget);

      final bannerRect = tester.getRect(banner);
      final posterRect = tester.getRect(poster);
      final infoRect = tester.getRect(info);

      expect(bannerRect.top, closeTo(44, 0.5));
      expect(bannerRect.width, closeTo(390, 0.5));
      expect(bannerRect.height, closeTo(390 * 9 / 16, 1));
      expect(posterRect.width, greaterThanOrEqualTo(118));
      expect(
        (posterRect.center.dy - infoRect.center.dy).abs(),
        lessThanOrEqualTo(2),
      );
    },
  );
}
