import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum DeviceScreenType { mobile, tablet, desktop }

class ResponsiveBreakpoints {
  // Common standard breakpoints
  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 900;

  static const int handsetLandscapeAnimeColumns = 5;

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

  static SliverGridDelegate animeGridDelegate(
    BuildContext context, {
    required double maxCrossAxisExtent,
    required double childAspectRatio,
    double crossAxisSpacing = 16,
    double mainAxisSpacing = 16,
    int? handsetPortraitCrossAxisCount,
  }) {
    final fixedCount = isHandsetLandscape(context)
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
  bool get isTv =>
      MediaQuery.maybeNavigationModeOf(this) == NavigationMode.directional ||
      (Platform.isAndroid &&
          MediaQuery.of(this).size.aspectRatio > 1.0 &&
          MediaQuery.of(this).padding.top == 0);
}
