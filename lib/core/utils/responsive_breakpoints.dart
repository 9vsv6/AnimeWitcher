import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum DeviceScreenType { mobile, tablet, desktop }

class ResponsiveBreakpoints {
  // Common standard breakpoints
  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 900;

  static const int handsetLandscapeAnimeColumns = 5;

  /// Column count used on a "reference" 1440pt-wide desktop window.
  ///
  /// Wide layouts no longer pin themselves to this number: the column count
  /// is derived from the available width so a poster keeps a comfortable
  /// physical size on every window. See [desktopLandscapeColumnsFor].
  static const int desktopLandscapeAnimeColumns = 8;

  /// Poster width that reads best on a desktop / TV screen.
  ///
  /// The column count on wide layouts is chosen so the resulting card lands
  /// as close as possible to this width. That keeps a poster physically the
  /// same size whether the app runs in a 900pt window or on a 4K monitor —
  /// the extra pixels buy *more* posters per row, not bigger ones.
  static const double desktopAnimeCardIdealWidth = 190;

  /// Hard bounds on the derived column count, so an extreme window can never
  /// produce a single-column desktop grid or an unusable 40-column wall.
  static const int desktopAnimeMinColumns = 4;
  static const int desktopAnimeMaxColumns = 24;

  /// Number of poster columns to use for [availableWidth] on a wide layout.
  ///
  /// [availableWidth] is the width already free of outer padding, and
  /// [spacing] is the gap between two adjacent cards. The column count that
  /// puts a card closest to [desktopAnimeCardIdealWidth] wins, clamped to
  /// [desktopAnimeMinColumns] … [desktopAnimeMaxColumns].
  static int desktopLandscapeColumnsFor(
    double availableWidth, {
    double spacing = 16,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return desktopAnimeMinColumns;
    }

    // Width of one card when the row is split into [columns] equal tracks.
    double cardWidthFor(int columns) =>
        (availableWidth - spacing * (columns - 1)) / columns;

    var bestColumns = desktopAnimeMinColumns;
    var bestDelta = (cardWidthFor(bestColumns) - desktopAnimeCardIdealWidth)
        .abs();
    for (
      var columns = desktopAnimeMinColumns + 1;
      columns <= desktopAnimeMaxColumns;
      columns++
    ) {
      final delta = (cardWidthFor(columns) - desktopAnimeCardIdealWidth).abs();
      // Strictly-less keeps the smallest (widest-card) count on ties.
      if (delta < bestDelta) {
        bestDelta = delta;
        bestColumns = columns;
      }
    }
    return bestColumns;
  }

  static bool isHandset(BuildContext context) {
    if (kIsWeb) return false;
    final isMobilePlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isMobilePlatform &&
        MediaQuery.sizeOf(context).shortestSide < tabletBreakpoint;
  }

  static bool isHandsetLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return isHandset(context) && size.width > size.height;
  }

  static bool isDesktopPlatform() {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static bool isDesktopLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return isDesktopPlatform() && size.width > size.height;
  }

  static double handsetLandscapeAnimeCardWidth(
    BuildContext context, {
    double horizontalPadding = 16,
    double spacing = 8,
  }) {
    final innerWidth =
        MediaQuery.sizeOf(context).width - (horizontalPadding * 2);
    return ((innerWidth / handsetLandscapeAnimeColumns) - spacing)
        .clamp(72.0, 200.0)
        .toDouble();
  }

  /// Poster width for horizontal rails on wide layouts.
  ///
  /// The column count adapts to the window (see
  /// [desktopLandscapeColumnsFor]) so a rail shows readable posters on a
  /// 900pt window and does not blow them up to 400pt on an ultrawide
  /// display. The returned width is the exact track width, so a rail using
  /// `itemExtent: width + spacing` stays pixel-aligned with the grids.
  static double desktopLandscapeAnimeCardWidth(
    BuildContext context, {
    double horizontalPadding = 16,
    double spacing = 16,
  }) {
    final innerWidth =
        MediaQuery.sizeOf(context).width - (horizontalPadding * 2);
    if (innerWidth <= 0) return desktopAnimeCardIdealWidth;

    final columns = desktopLandscapeColumnsFor(innerWidth, spacing: spacing);
    final trackWidth = (innerWidth - spacing * (columns - 1)) / columns;
    return trackWidth.clamp(72.0, double.infinity).toDouble();
  }

  /// Column count a wide-layout grid will actually use for [context].
  ///
  /// Screens that need the number itself (to size loading placeholders, or
  /// to append "load more" tiles that complete the last row) must call this
  /// instead of recomputing it, so the placeholder count can never drift
  /// from what [animeGridDelegate] laid out.
  static int animeGridCrossAxisCount(
    BuildContext context, {
    required double maxCrossAxisExtent,
    double crossAxisSpacing = 16,
    double horizontalPadding = 0,
    int? handsetPortraitCrossAxisCount,
  }) {
    final innerWidth =
        MediaQuery.sizeOf(context).width - (horizontalPadding * 2);
    if (isDesktopLandscape(context)) {
      return desktopLandscapeColumnsFor(innerWidth, spacing: crossAxisSpacing);
    }
    if (isHandsetLandscape(context)) return handsetLandscapeAnimeColumns;
    if (isHandset(context) && handsetPortraitCrossAxisCount != null) {
      return handsetPortraitCrossAxisCount;
    }
    // Mirrors SliverGridDelegateWithMaxCrossAxisExtent's own arithmetic.
    if (innerWidth <= 0 || maxCrossAxisExtent <= 0) return 1;
    return (innerWidth / (maxCrossAxisExtent + crossAxisSpacing)).ceil().clamp(
      1,
      40,
    );
  }

  static SliverGridDelegate animeGridDelegate(
    BuildContext context, {
    required double maxCrossAxisExtent,
    required double childAspectRatio,
    double crossAxisSpacing = 16,
    double mainAxisSpacing = 16,
    int? handsetPortraitCrossAxisCount,

    /// Horizontal padding applied around the grid, so the derived desktop
    /// column count is based on the width the cards really get.
    double horizontalPadding = 0,
  }) {
    final fixedCount = isDesktopLandscape(context)
        ? desktopLandscapeColumnsFor(
            MediaQuery.sizeOf(context).width - (horizontalPadding * 2),
            spacing: crossAxisSpacing,
          )
        : isHandsetLandscape(context)
        ? handsetLandscapeAnimeColumns
        : (isHandset(context) ? handsetPortraitCrossAxisCount : null);
    if (fixedCount != null) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: fixedCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      );
    }
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  static DeviceScreenType getDeviceType(BuildContext context) {
    if (isHandset(context)) return DeviceScreenType.mobile;
    final width = MediaQuery.sizeOf(context).width;

    if (width >= desktopBreakpoint) {
      return DeviceScreenType.desktop;
    } else if (width >= tabletBreakpoint) {
      return DeviceScreenType.tablet;
    } else {
      return DeviceScreenType.mobile;
    }
  }

  static bool isMobile(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.mobile;

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.tablet;

  static bool isDesktop(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.desktop;

  static bool isTabletOrLarger(BuildContext context) =>
      getDeviceType(context) != DeviceScreenType.mobile;
}

// Extension for easy access from BuildContext
extension ResponsiveContext on BuildContext {
  DeviceScreenType get deviceType => ResponsiveBreakpoints.getDeviceType(this);
  bool get isMobile => ResponsiveBreakpoints.isMobile(this);
  bool get isTablet => ResponsiveBreakpoints.isTablet(this);
  bool get isDesktop => ResponsiveBreakpoints.isDesktop(this);
  bool get isTabletOrLarger => ResponsiveBreakpoints.isTabletOrLarger(this);
  bool get isHandset => ResponsiveBreakpoints.isHandset(this);
  bool get isHandsetLandscape => ResponsiveBreakpoints.isHandsetLandscape(this);
  bool get isDesktopLandscape => ResponsiveBreakpoints.isDesktopLandscape(this);
  bool get isTv =>
      MediaQuery.maybeNavigationModeOf(this) == NavigationMode.directional ||
      (Platform.isAndroid &&
          MediaQuery.of(this).size.aspectRatio > 1.0 &&
          MediaQuery.of(this).padding.top == 0);
}
