/// Centralized spacing and layout values for consistent UI.
/// Use from details_screen, explore_carousel, and other layout code.
class LayoutConstants {
  LayoutConstants._();

  // Spacing
  static const double spacingXs = 8;
  static const double spacingSm = 12;
  static const double spacingMd = 16;
  static const double spacingLg = 24;

  // Details screen mobile header. AnimeWitcher defines these with the
  // scalable-dp library against a 300dp reference width. Keep the source
  // values here and scale them from the actual device width at runtime.
  static const double detailsSdpReferenceWidth = 300;
  static const double detailsExpandedHeightMobile = 230;
  static const double detailsBannerHeightMobile = 170;
  static const double detailsPosterTopMobile = 120;
  static const double detailsPosterWidthMobile = 65;
  static const double detailsPosterHeightMobile = 100;
  static const double detailsPosterStartMobile = 12;
  static const double detailsTitleStartMobile = 87;
  static const double detailsHeaderEndMobile = 16;
  static const double detailsHeaderBottomMobile = 5;
  static const double detailsExpandedHeightDesktop = 300;

  // Border Radius
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusXxl = 24;
  static const double radiusPill = 50;

  // Content constraints: the widest a single column of text/settings rows
  // may get before it stops being comfortably scannable on a big monitor.
  static const double contentMaxWidth = 800;

  // Dashboard layout (widescreen)
  static const double dashboardHeaderHeight = 56;
  static const double dashboardContentPadding = 24;
}
