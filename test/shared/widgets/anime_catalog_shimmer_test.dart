import 'package:animewitcher/shared/widgets/anime_catalog_shimmer.dart';
import 'package:animewitcher/shared/widgets/multimedia_card.dart';
import 'package:animewitcher/shared/widgets/shimmer_placeholder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpCatalog(
  WidgetTester tester, {
  bool characterCaptionSpace = false,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimeCatalogShimmer(
            itemCount: 6,
            physics: const NeverScrollableScrollPhysics(),
            characterCaptionSpace: characterCaptionSpace,
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared mobile catalog metrics match the search reference', () {
    expect(MultimediaCardLayout.handsetPortraitGridColumns, 3);
    expect(MultimediaCardLayout.handsetPortraitGridHorizontalPadding, 12);
    expect(MultimediaCardLayout.handsetPortraitGridCrossAxisSpacing, 10);
    expect(MultimediaCardLayout.handsetPortraitGridMainAxisSpacing, 14);
    expect(
      MultimediaCardLayout.characterGridAspectRatio,
      greaterThan(MultimediaCardLayout.portraitGridAspectRatio),
    );
  });

  testWidgets('catalog skeleton poster matches the final bounded card size', (
    tester,
  ) async {
    await _pumpCatalog(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final shimmers = find.byType(ShimmerPlaceholder);
    expect(shimmers, findsNWidgets(6));

    final first = tester.getRect(shimmers.at(0));
    final fourth = tester.getRect(shimmers.at(3));
    const expectedWidth =
        (390 -
            MultimediaCardLayout.handsetPortraitGridHorizontalPadding * 2 -
            MultimediaCardLayout.handsetPortraitGridCrossAxisSpacing * 2) /
        MultimediaCardLayout.handsetPortraitGridColumns;
    final context = tester.element(find.byType(AnimeCatalogShimmer));
    final expectedCaption = MultimediaCardLayout.animeCaptionExtent(context);
    const expectedCellHeight =
        expectedWidth / MultimediaCardLayout.portraitGridAspectRatio;

    expect(first.width, closeTo(expectedWidth, 0.5));
    expect(first.height, closeTo(expectedCellHeight - expectedCaption, 0.75));

    final rowStride = fourth.top - first.top;
    final reservedCaptionSpace =
        rowStride -
        first.height -
        MultimediaCardLayout.handsetPortraitGridMainAxisSpacing;
    expect(reservedCaptionSpace, closeTo(expectedCaption, 0.75));
  });

  testWidgets('character loading keeps a smaller empty caption area', (
    tester,
  ) async {
    await _pumpCatalog(tester);
    final animeShimmers = find.byType(ShimmerPlaceholder);
    final animeFirst = tester.getRect(animeShimmers.at(0));
    final animeFourth = tester.getRect(animeShimmers.at(3));
    final animeReserved =
        animeFourth.top -
        animeFirst.top -
        animeFirst.height -
        MultimediaCardLayout.handsetPortraitGridMainAxisSpacing;

    await _pumpCatalog(tester, characterCaptionSpace: true);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final characterShimmers = find.byType(ShimmerPlaceholder);
    final characterFirst = tester.getRect(characterShimmers.at(0));
    final characterFourth = tester.getRect(characterShimmers.at(3));
    final characterReserved =
        characterFourth.top -
        characterFirst.top -
        characterFirst.height -
        MultimediaCardLayout.handsetPortraitGridMainAxisSpacing;

    final context = tester.element(find.byType(AnimeCatalogShimmer));
    expect(
      animeReserved,
      closeTo(MultimediaCardLayout.animeCaptionExtent(context), 0.75),
    );
    expect(
      characterReserved,
      closeTo(MultimediaCardLayout.characterCaptionExtent(context), 0.75),
    );
    expect(characterFirst.width, closeTo(animeFirst.width, 0.5));
    expect(characterReserved, lessThan(animeReserved));
  });
}
