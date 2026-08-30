import 'package:animewitcher/core/utils/responsive_breakpoints.dart';
import 'package:flutter_test/flutter_test.dart';

/// Width of one card once [availableWidth] is split into [columns] tracks.
double _cardWidth(double availableWidth, int columns, double spacing) {
  return (availableWidth - spacing * (columns - 1)) / columns;
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
}
