/// Whether the window's caption buttons should stay out of the way.
///
/// They are painted over the app's own content rather than in a bar of their
/// own, which is right nearly everywhere but wrong over a playing video: the
/// picture runs to the edges, and minimise / maximise / close sit on top of it
/// even after the player has hidden its own controls.
///
/// The player raises this while its controls are hidden and lowers it when
/// they come back or when it closes, so the buttons follow the same show and
/// hide the rest of the playback chrome does.
library;

import 'package:flutter/foundation.dart';

final ValueNotifier<bool> windowControlsHidden = ValueNotifier<bool>(false);
