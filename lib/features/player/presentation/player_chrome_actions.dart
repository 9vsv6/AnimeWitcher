/// Optional buttons on the player bottom-right cluster, in visual LTR order.
///
/// Touch layout right-aligns this list (`PlayerBottomBar` reverse scroll),
/// so index 0 sits immediately left of the following icon. PiP is placed
/// just before rotate — left of the rotation button in the screenshot.
enum PlayerChromeAction {
  playbackSpeed,
  pip,
  rotate,
  episodes,
  resize,
  desktopFullscreen,
}

class PlayerChromeActions {
  const PlayerChromeActions._();

  static List<PlayerChromeAction> visible({
    required bool showPlaybackSpeed,
    required bool supportsPlaybackSpeed,
    required bool showPip,
    required bool pipSupported,
    required bool showRotate,
    required bool canRotate,
    required bool showEpisodes,
    required bool hasEpisodePicker,
    required bool showResize,
    required bool isDesktop,
  }) {
    return [
      if (supportsPlaybackSpeed && showPlaybackSpeed)
        PlayerChromeAction.playbackSpeed,
      if (showPip && pipSupported) PlayerChromeAction.pip,
      if (showRotate && canRotate) PlayerChromeAction.rotate,
      if (hasEpisodePicker && showEpisodes) PlayerChromeAction.episodes,
      if (showResize) PlayerChromeAction.resize,
      if (isDesktop) PlayerChromeAction.desktopFullscreen,
    ];
  }
}
