/// Room to leave for the window's own controls, which are painted over the
/// top strip of the app rather than in a bar of their own.
///
/// Anything placed along that strip has to keep clear of them or it ends up
/// underneath the caption buttons, where it cannot be clicked.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

const bool _isDesktopShell = !kIsWeb;

/// Width of the minimise / maximise / close group on Windows, which sits at
/// the trailing edge. macOS puts its controls at the leading edge instead.
double get windowControlsTrailingInset =>
    _isDesktopShell && Platform.isWindows ? 128 : 0;

/// Width of the macOS traffic lights, which sit at the leading edge.
double get windowControlsLeadingInset =>
    _isDesktopShell && Platform.isMacOS ? 88 : 0;

/// The larger of the two, for content that should stay centred in the window
/// rather than shifted away from whichever edge is occupied.
double get windowControlsSymmetricInset =>
    windowControlsTrailingInset > windowControlsLeadingInset
    ? windowControlsTrailingInset
    : windowControlsLeadingInset;

/// Reserves the trailing gap in an `AppBar`'s action slot.
///
/// These headers put the screen's title against the trailing edge — which in
/// Arabic is the corner the window paints minimise, maximise and close over —
/// and an `AppBar` sizes its title around whatever actions it carries. An
/// empty box of the right width is enough to move the title clear, and it
/// collapses to nothing on every platform that has no controls there.
class WindowControlsGap extends StatelessWidget {
  const WindowControlsGap({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: windowControlsTrailingInset);
}
