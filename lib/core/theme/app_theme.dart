import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class _FixedLtrCupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FixedLtrCupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final contentDirection = Directionality.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (ltrContext) =>
            CupertinoPageTransitionsBuilder().buildTransitions<T>(
              route,
              ltrContext,
              animation,
              secondaryAnimation,
              Directionality(textDirection: contentDirection, child: child),
            ),
      ),
    );
  }
}

class AppTheme {
  static final PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          ...const PageTransitionsTheme().builders,
          TargetPlatform.iOS: const _FixedLtrCupertinoPageTransitionsBuilder(),
        },
      );
  // AnimeWitcher palette. The official Android app uses #EEC60A as
  // colorAccent across interactive controls, tabs, selection states and progress.
  static const Color animeWitcherAccent = Color(0xFFEEC60A);
  static const Color animeWitcherAccentTransparent = Color(0xAEEEC60A);

  // Premium Colors
  static const Color background = Color(0xFF0F0F13); // Deep dark blue-grey
  static const Color surface = Color(0xFF18181F);
  static const Color surfaceHighlight = Color(0xFF22222E);
  static const Color primary = animeWitcherAccent;
  static const Color primaryVariant = animeWitcherAccent;
  static const Color secondary = animeWitcherAccent;
  static const Color error = Color(0xFFEF4444);
  static const Color onSurface = Color(0xFFE5E7EB);
  static const Color textSecondary = Color(0xFF9CA3AF);

  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF5F1EC); // primary surface
  static const Color lightSurface = Color(0xFFFAF8F5); // surfaceContainerLowest
  static const Color lightSurfaceHighlight = Color(
    0xFFE8E2D8,
  ); // surfaceContainerHigh
  static const Color lightTextPrimary = Color(0xFF2C2521); // onSurface
  static const Color lightTextSecondary = Color(0xFF5C5C5C); // onSurfaceVariant

  /// Icons and secondary text on the dark theme's pure-black surfaces.
  static const Color darkIconNeutral = Color(0xFFD3D5DC);
  // Kept as a compatibility alias for existing callers/tests.
  static const Color lightCoral = animeWitcherAccent;

  static SnackBarThemeData snackBarThemeFor(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return SnackBarThemeData(
      backgroundColor: isDark ? surface : colorScheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(
        color: isDark ? onSurface : colorScheme.onSurface,
      ),
      actionTextColor: colorScheme.primary,
    );
  }

  /// The hairline every floating surface carries, matching the home search
  /// capsule and the taskbar pill. It is what makes a menu read as part of
  /// the app rather than a plain grey box dropped on top of it.
  /// Extra height for a title bar on a desktop window.
  ///
  /// The window's own controls are painted over the top of the app rather
  /// than in a bar of their own, so a toolbar of the usual height centres its
  /// title exactly where the minimise and close buttons sit. The taller bar
  /// drops the title clear of them; a phone has no such controls and keeps
  /// the standard height.
  static double? get _toolbarHeight {
    if (kIsWeb) return null;
    return Platform.isWindows || Platform.isMacOS ? 72 : null;
  }

  static BorderSide _hairline(ColorScheme scheme) =>
      BorderSide(color: scheme.onSurfaceVariant.withValues(alpha: 0.12));

  /// Menus, sheets and dialogs share one shape so they look like the same
  /// object appearing in different places.
  static const double _surfaceRadius = 16;

  static PopupMenuThemeData _popupMenuTheme(ColorScheme scheme) {
    return PopupMenuThemeData(
      color: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_surfaceRadius),
        side: _hairline(scheme),
      ),
    );
  }

  static MenuThemeData _menuTheme(ColorScheme scheme) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(
          scheme.surfaceContainerHighest,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_surfaceRadius),
            side: _hairline(scheme),
          ),
        ),
      ),
    );
  }

  static ThemeData createDarkTheme(ColorScheme? _) {
    // Keep the official AnimeWitcher accent fixed instead of allowing Android
    // dynamic colors to replace it with a device-specific blue/purple palette.
    var colorScheme = ColorScheme.fromSeed(
      seedColor: animeWitcherAccent,
      brightness: Brightness.dark,
      surface: const Color(0xFF000000),
    );

    // AnimeWitcher uses one gold accent for its interactive theme. Force the
    // key Material roles to that same accent while preserving semantic errors.
    colorScheme = colorScheme.copyWith(
      primary: animeWitcherAccent,
      onPrimary: Colors.black,
      secondary: animeWitcherAccent,
      onSecondary: Colors.black,
      tertiary: animeWitcherAccent,
      onTertiary: Colors.black,
      surface: const Color(0xFF000000),
      // The seeded value is a dim grey that all but disappears against a pure
      // black background. Icons and secondary labels are drawn in it
      // throughout the app, so it is lifted to something legible rather than
      // colouring each of them by hand.
      onSurfaceVariant: darkIconNeutral,
    );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _pageTransitionsTheme,
      brightness: Brightness.dark,
      // An icon that names no colour of its own still has to be visible on
      // black; Material's default leans too dark for this background.
      iconTheme: const IconThemeData(color: darkIconNeutral),
      scaffoldBackgroundColor: const Color(
        0xFF000000,
      ), // Pure Black Background for Screens
      // Dialog Theme (Premium Grey)
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF18181F),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_surfaceRadius),
          side: _hairline(colorScheme),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF9FAFB),
        ),
      ),

      // Bottom Sheet Theme (Premium Grey)
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: const Color(0xFF18181F),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: const Color(0xFF18181F),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(_surfaceRadius),
          ),
          side: _hairline(colorScheme),
        ),
      ),

      popupMenuTheme: _popupMenuTheme(colorScheme),
      menuTheme: _menuTheme(colorScheme),

      // Card Theme (Pitch Black for List Items)
      cardTheme: const CardThemeData(
        color: Color(0xFF000000),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Material 3 Color Scheme
      colorScheme: colorScheme,

      // Typography
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF9FAFB),
            ),
            displayMedium: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF9FAFB),
            ),
            displaySmall: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF9FAFB),
            ),
            headlineMedium: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF9FAFB),
            ),
            titleLarge: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF9FAFB),
            ),
            titleMedium: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF9FAFB),
            ),
            bodyLarge: GoogleFonts.outfit(
              fontSize: 16,
              color: const Color(0xFFE5E7EB),
            ),
            bodyMedium: GoogleFonts.outfit(
              fontSize: 14,
              color: const Color(0xFF9CA3AF),
            ),
            bodySmall: GoogleFonts.outfit(
              fontSize: 12,
              color: const Color(0xFF6B7280),
            ),
            labelLarge: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: const Color(0xFFF9FAFB),
            ),
          ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: _toolbarHeight,
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(
          0xFF000000,
        ), // Pure Black matches background
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        landscapeLayout: BottomNavigationBarLandscapeLayout.spread,
      ),

      // Keep SnackBars visually consistent with the dark application instead
      // of Material's default inverse (light) surface.
      snackBarTheme: snackBarThemeFor(colorScheme),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF18181F), // Slightly lighter grey for fields
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),

      // Chip Theme — the light theme styles chips explicitly, so the dark
      // theme has to as well or filter chips fall back to Material's default
      // grey and stop reading as part of the gold accent language.
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF18181F),
        disabledColor: colorScheme.onSurface.withValues(alpha: 0.12),
        selectedColor: colorScheme.primary.withValues(alpha: 0.18),
        secondarySelectedColor: colorScheme.primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(color: colorScheme.primary),
        checkmarkColor: colorScheme.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide.none,
        ),
      ),

      // Switch Theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),

      // Slider Theme — used by the player's seek/volume bars.
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.24),
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // Ripple / Splash / Highlights — pointer feedback matters far more on
      // desktop, where hover is the primary affordance for "this is tappable".
      splashColor: colorScheme.primary.withValues(alpha: 0.1),
      hoverColor: colorScheme.primary.withValues(alpha: 0.06),
      highlightColor: colorScheme.primary.withValues(alpha: 0.05),

      // Selection Text Theme — keeps the caret/selection gold instead of the
      // default blue that Material picks for dark schemes.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: colorScheme.primary,
      ),

      dividerColor: const Color(0xFF22222E),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        space: 1,
        color: Color(0xFF22222E),
      ),
    );
  }

  static ThemeData createLightTheme(ColorScheme? _) {
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: animeWitcherAccent,
      brightness: Brightness.light,
    );
    final colorScheme = generatedScheme.copyWith(
      primary: animeWitcherAccent,
      onPrimary: Colors.black,
      secondary: animeWitcherAccent,
      onSecondary: Colors.black,
      tertiary: animeWitcherAccent,
      onTertiary: Colors.black,
      surface: lightBackground,
      onSurface: lightTextPrimary,
      onSurfaceVariant: lightTextSecondary,
      outline: const Color(0xFFC9BBA6), // Warm sand outline
      outlineVariant: const Color(0xFFD9C9AE), // Soft warm tan outlineVariant
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      surfaceContainerLowest: lightSurface,
      surfaceContainerLow: const Color(0xFFF7F3EE),
      surfaceContainer: const Color(0xFFEFEAE2),
      surfaceContainerHigh: lightSurfaceHighlight,
      surfaceContainerHighest: const Color(0xFFE4D9C8),
    );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _pageTransitionsTheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colorScheme.surface,

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_surfaceRadius),
          side: _hairline(colorScheme),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(_surfaceRadius),
          ),
          side: _hairline(colorScheme),
        ),
      ),

      popupMenuTheme: _popupMenuTheme(colorScheme),
      menuTheme: _menuTheme(colorScheme),

      // Card Theme
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Material 3 Color Scheme
      colorScheme: colorScheme,

      // Typography
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            headlineMedium: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            titleLarge: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            bodyLarge: GoogleFonts.outfit(
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
            bodyMedium: GoogleFonts.outfit(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            bodySmall: GoogleFonts.outfit(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: 'Outfit',
        ),
        toolbarHeight: _toolbarHeight,
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showSelectedLabels: false,
        showUnselectedLabels: false,
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        disabledColor: colorScheme.onSurface.withValues(alpha: 0.12),
        selectedColor: colorScheme.primary.withValues(alpha: 0.15),
        secondarySelectedColor: colorScheme.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(color: colorScheme.primary),
        checkmarkColor: colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide.none,
        ),
      ),

      // Switch Theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),

      // Slider Theme
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.24),
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // SnackBar Theme
      snackBarTheme: snackBarThemeFor(colorScheme),

      // Ripple / Splash / Highlights
      splashColor: colorScheme.primary.withValues(alpha: 0.1),
      hoverColor: colorScheme.primary.withValues(alpha: 0.04),
      highlightColor: colorScheme.primary.withValues(alpha: 0.05),

      // Selection Text Theme
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: colorScheme.primary,
      ),

      dividerColor: colorScheme.outlineVariant,
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: colorScheme.outlineVariant,
      ),
    );
  }
}
