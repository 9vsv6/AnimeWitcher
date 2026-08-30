import 'package:animewitcher/core/utils/responsive_breakpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Width of one card once [availableWidth] is split into [columns] tracks.
double _cardWidth(double availableWidth, int columns, double spacing) {
  return (availableWidth - spacing * (columns - 1)) / columns;
}

Future<BuildContext> _pumpContext(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.binding.setSurfaceSize(null);
  });
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('desktopLandscapeColumnsFor', () {
    test('stays inside the documented column bounds', () {
      for (final width in <double>[1, 320, 700, 900, 1440, 2560, 3440, 5120]) {
        final columns = ResponsiveBreakpoints.desktopLandscapeColumnsFor(width);
        expect(
          columns,
          inInclusiveRange(
            ResponsiveBreakpoints.desktopAnimeMinColumns,
            ResponsiveBreakpoints.desktopAnimeMaxColumns,
          ),
          reason: 'width=$width produced $columns columns',
        );
      }
    });

    test('keeps a poster near the ideal width on every desktop size', () {
      // The whole point of the helper: extra pixels buy *more* posters, not
      // absurdly large ones. A 900pt window and a 5120pt wall should both
      // land within a reasonable band of the ideal poster width.
      const spacing = 16.0;
      const ideal = ResponsiveBreakpoints.desktopAnimeCardIdealWidth;
      for (final width in <double>[900, 1280, 1440, 1920, 2560, 3440, 5120]) {
        final columns = ResponsiveBreakpoints.desktopLandscapeColumnsFor(
          width,
          spacing: spacing,
        );
        final cardWidth = _cardWidth(width, columns, spacing);
        expect(
          cardWidth,
          inInclusiveRange(ideal * 0.75, ideal * 1.35),
          reason:
              'width=$width -> $columns columns -> '
              '${cardWidth.toStringAsFixed(1)}pt card',
        );
      }
    });

    test('never shrinks the column count as the window grows', () {
      var previous = 0;
      for (var width = 700.0; width <= 5120.0; width += 20) {
        final columns = ResponsiveBreakpoints.desktopLandscapeColumnsFor(width);
        expect(
          columns,
          greaterThanOrEqualTo(previous),
          reason: 'column count regressed at width=$width',
        );
        previous = columns;
      }
    });

    test('picks the count closest to the ideal poster width', () {
      // 1440pt inner width with 16pt gaps: 7 columns -> ~192pt, which is the
      // nearest match to the 190pt ideal, so 7 must win over 6 and 8.
      expect(
        ResponsiveBreakpoints.desktopLandscapeColumnsFor(1440, spacing: 16),
        7,
      );
    });

    test('falls back to the minimum for degenerate widths', () {
      for (final width in <double>[0, -100, double.nan, double.infinity]) {
        expect(
          ResponsiveBreakpoints.desktopLandscapeColumnsFor(width),
          ResponsiveBreakpoints.desktopAnimeMinColumns,
          reason: 'width=$width should fall back to the minimum',
        );
      }
    });

    test('honours the spacing it is given', () {
      // Wider gaps eat horizontal room, so the same window can never fit
      // *more* columns with more spacing than with less.
      final tight = ResponsiveBreakpoints.desktopLandscapeColumnsFor(
        1920,
        spacing: 4,
      );
      final loose = ResponsiveBreakpoints.desktopLandscapeColumnsFor(
        1920,
        spacing: 32,
      );
      expect(loose, lessThanOrEqualTo(tight));
    });
  });

  group(
    'animeGridDelegate after merging phone landscape with desktop adaptive',
    () {
      testWidgets(
        'phone landscape stays at 7 columns, not the desktop ~190pt algorithm',
        (tester) async {
          const size = Size(800, 360);
          final context = await _pumpContext(tester, size: size);
          // At 800pt the desktop helper would pick ~4 columns (~190pt cards).
          // Handsets must ignore that and keep the 7-poster landscape grid.
          expect(
            ResponsiveBreakpoints.desktopLandscapeColumnsFor(size.width),
            isNot(ResponsiveBreakpoints.handsetLandscapeAnimeColumns),
          );

          final delegate = ResponsiveBreakpoints.animeGridDelegate(
            context,
            maxCrossAxisExtent: 150,
            childAspectRatio: 0.52,
          );
          expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
          expect(
            (delegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount,
            ResponsiveBreakpoints.handsetLandscapeAnimeColumns,
          );
          expect(
            ResponsiveBreakpoints.animeGridCrossAxisCount(
              context,
              maxCrossAxisExtent: 150,
            ),
            ResponsiveBreakpoints.handsetLandscapeAnimeColumns,
          );
        },
      );

      testWidgets('phone portrait keeps the caller portrait count', (
        tester,
      ) async {
        final context = await _pumpContext(tester, size: const Size(390, 844));
        final delegate = ResponsiveBreakpoints.animeGridDelegate(
          context,
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.52,
          handsetPortraitCrossAxisCount: 3,
        );
        expect(
          (delegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          3,
        );
        expect(
          ResponsiveBreakpoints.animeGridCrossAxisCount(
            context,
            maxCrossAxisExtent: 150,
            handsetPortraitCrossAxisCount: 3,
          ),
          3,
        );
      });

      testWidgets('desktop landscape uses adaptive columns, not a frozen 8', (
        tester,
      ) async {
        const size = Size(3440, 1440);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final context = await _pumpContext(tester, size: size);
          final expected = ResponsiveBreakpoints.desktopLandscapeColumnsFor(
            size.width,
          );
          expect(
            expected,
            greaterThan(ResponsiveBreakpoints.desktopLandscapeAnimeColumns),
          );

          final delegate = ResponsiveBreakpoints.animeGridDelegate(
            context,
            maxCrossAxisExtent: 240,
            childAspectRatio: 0.54,
          );
          expect(
            (delegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount,
            expected,
          );
          expect(
            ResponsiveBreakpoints.animeGridCrossAxisCount(
              context,
              maxCrossAxisExtent: 240,
            ),
            expected,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    },
  );
}
