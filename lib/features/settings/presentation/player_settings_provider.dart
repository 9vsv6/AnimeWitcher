import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/storage/settings_repository.dart';

part 'player_settings_provider.g.dart';

enum PlayerGesture { brightness, volume, none }

class PlayerSettings {
  final PlayerGesture leftGesture;
  final PlayerGesture rightGesture;
  final bool doubleTapEnabled;
  final bool swipeSeekEnabled;
  final int seekDuration;
  final String defaultResizeMode;
  final double subtitleSize;
  final int subtitleColor;
  final int subtitleBackgroundColor;
  final double subtitleBackgroundOpacity;
  final bool hardwareDecoding;
  final String?
  preferredPlayer; // null = internal, 'vlc' / 'mpv' etc. = external
  final int readaheadSeconds;
  final double subtitlePosition;

  // New subtitle appearance properties
  final double? subFixedTextSize;
  final int? subTypeface;
  final String? subTypefaceFilePath;
  final int subEdgeType;
  final double? subEdgeSize;
  final double? subBackgroundRadius;
  final int subElevation;
  final bool subRemoveBloat;
  final bool subRemoveCaptions;
  final bool subUpperCase;
  final bool subBold;
  final bool subItalic;
  final int subForegroundColor;
  final int subBackgroundColor;
  final int subEdgeColor;
  final double subBackgroundOpacity;
  final int? subAlignment;

  /// When true, the progress-bar time header shows the remaining time
  /// (e.g. "-1:23:45 / 2:00:00") instead of the elapsed time. Sticky
  /// across sessions because users who prefer one view almost always
  /// want it always.
  final bool showRemainingTime;

  /// Default playback speed restored on every new playback session.
  /// 1.0 = normal. Stored as a double to support fractional values
  /// (1.25, 1.5, 1.75, 2.0). Capped at the engine's supported range
  /// at playback time (`maxPlaybackSpeed`).
  final double defaultPlaybackSpeed;

  /// Toggles for the remaining optional player control-bar buttons.
  /// All default to visible.
  final bool showPip;
  final bool showResize;
  final bool showRotate;
  final bool showPlaybackSpeed;
  final bool showEpisodes;

  const PlayerSettings({
    this.leftGesture = PlayerGesture.brightness,
    this.rightGesture = PlayerGesture.volume,
    this.doubleTapEnabled = true,
    this.swipeSeekEnabled = true,
    this.seekDuration = 10,
    this.defaultResizeMode = 'Fit',
    this.subtitleSize = 22.0,
    this.subtitleColor = 0xFFFFFFFF, // White
    this.subtitleBackgroundColor = 0x00000000, // Transparent
    this.subtitleBackgroundOpacity = 0.5, // Default opacity (50%)
    this.hardwareDecoding = true,
    this.preferredPlayer,
    this.readaheadSeconds = 180,
    this.subtitlePosition = 100.0,
    this.subFixedTextSize,
    this.subTypeface,
    this.subTypefaceFilePath,
    this.subEdgeType = 1,
    this.subEdgeSize,
    this.subBackgroundRadius,
    this.subElevation = 20,
    this.subRemoveBloat = true,
    this.subRemoveCaptions = false,
    this.subUpperCase = false,
    this.subBold = false,
    this.subItalic = false,
    this.subForegroundColor = 0xFFFFFFFF,
    this.subBackgroundColor = 0x00000000,
    this.subEdgeColor = 0xFF000000,
    this.subBackgroundOpacity = 0.5,
    this.subAlignment,
    this.showRemainingTime = false,
    this.defaultPlaybackSpeed = 1.0,
    this.showPip = true,
    this.showResize = true,
    this.showRotate = true,
    this.showPlaybackSpeed = true,
    this.showEpisodes = true,
  });

  PlayerSettings copyWith({
    PlayerGesture? leftGesture,
    PlayerGesture? rightGesture,
    bool? doubleTapEnabled,
    bool? swipeSeekEnabled,
    int? seekDuration,
    String? defaultResizeMode,
    double? subtitleSize,
    int? subtitleColor,
    int? subtitleBackgroundColor,
    double? subtitleBackgroundOpacity,
    bool? hardwareDecoding,
    String? preferredPlayer,
    bool clearPreferredPlayer = false,
    int? readaheadSeconds,
    double? subtitlePosition,
    double? Function()? subFixedTextSize,
    int? Function()? subTypeface,
    String? Function()? subTypefaceFilePath,
    int? subEdgeType,
    double? Function()? subEdgeSize,
    double? Function()? subBackgroundRadius,
    int? subElevation,
    bool? subRemoveBloat,
    bool? subRemoveCaptions,
    bool? subUpperCase,
    bool? subBold,
    bool? subItalic,
    int? subForegroundColor,
    int? subBackgroundColor,
    int? subEdgeColor,
    double? subBackgroundOpacity,
    int? Function()? subAlignment,
    bool? showRemainingTime,
    double? defaultPlaybackSpeed,
    bool? showPip,
    bool? showResize,
    bool? showRotate,
    bool? showPlaybackSpeed,
    bool? showEpisodes,
  }) {
    return PlayerSettings(
      leftGesture: leftGesture ?? this.leftGesture,
      rightGesture: rightGesture ?? this.rightGesture,
      doubleTapEnabled: doubleTapEnabled ?? this.doubleTapEnabled,
      swipeSeekEnabled: swipeSeekEnabled ?? this.swipeSeekEnabled,
      seekDuration: seekDuration ?? this.seekDuration,
      defaultResizeMode: defaultResizeMode ?? this.defaultResizeMode,
      subtitleSize: subtitleSize ?? this.subtitleSize,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      subtitleBackgroundColor:
          subtitleBackgroundColor ?? this.subtitleBackgroundColor,
      subtitleBackgroundOpacity:
          subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      preferredPlayer: clearPreferredPlayer
          ? null
          : (preferredPlayer ?? this.preferredPlayer),
      readaheadSeconds: readaheadSeconds ?? this.readaheadSeconds,
      subtitlePosition: subtitlePosition ?? this.subtitlePosition,
      subFixedTextSize: subFixedTextSize != null
          ? subFixedTextSize()
          : this.subFixedTextSize,
      subTypeface: subTypeface != null ? subTypeface() : this.subTypeface,
      subTypefaceFilePath: subTypefaceFilePath != null
          ? subTypefaceFilePath()
          : this.subTypefaceFilePath,
      subEdgeType: subEdgeType ?? this.subEdgeType,
      subEdgeSize: subEdgeSize != null ? subEdgeSize() : this.subEdgeSize,
      subBackgroundRadius: subBackgroundRadius != null
          ? subBackgroundRadius()
          : this.subBackgroundRadius,
      subElevation: subElevation ?? this.subElevation,
      subRemoveBloat: subRemoveBloat ?? this.subRemoveBloat,
      subRemoveCaptions: subRemoveCaptions ?? this.subRemoveCaptions,
      subUpperCase: subUpperCase ?? this.subUpperCase,
      subBold: subBold ?? this.subBold,
      subItalic: subItalic ?? this.subItalic,
      subForegroundColor: subForegroundColor ?? this.subForegroundColor,
      subBackgroundColor: subBackgroundColor ?? this.subBackgroundColor,
      subEdgeColor: subEdgeColor ?? this.subEdgeColor,
      subBackgroundOpacity: subBackgroundOpacity ?? this.subBackgroundOpacity,
      subAlignment: subAlignment != null ? subAlignment() : this.subAlignment,
      showRemainingTime: showRemainingTime ?? this.showRemainingTime,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      showPip: showPip ?? this.showPip,
      showResize: showResize ?? this.showResize,
      showRotate: showRotate ?? this.showRotate,
      showPlaybackSpeed: showPlaybackSpeed ?? this.showPlaybackSpeed,
      showEpisodes: showEpisodes ?? this.showEpisodes,
    );
  }
}

@Riverpod(keepAlive: true)
class PlayerSettingsNotifier extends _$PlayerSettingsNotifier {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  Future<PlayerSettings> build() async {
    final storage = _repository;
    final l =
        storage.getPlayerSetting<String>(
          'player_gesture_left',
          defaultValue: 'brightness',
        ) ??
        'brightness';
    final r =
        storage.getPlayerSetting<String>(
          'player_gesture_right',
          defaultValue: 'volume',
        ) ??
        'volume';
    final dt =
        storage.getPlayerSetting<bool>(
          'player_double_tap',
          defaultValue: true,
        ) ??
        true;
    final dur =
        storage.getPlayerSetting<int>(
          'player_seek_duration',
          defaultValue: 10,
        ) ??
        10;
    final resize =
        storage.getPlayerSetting<String>(
          'player_default_resize',
          defaultValue: 'Fit',
        ) ??
        'Fit';
    final subSize =
        (storage.getPlayerSetting('player_sub_size') as num?)?.toDouble() ??
        22.0;
    final subColor =
        storage.getPlayerSetting<int>(
          'player_sub_color',
          defaultValue: 0xFFFFFFFF,
        ) ??
        0xFFFFFFFF;
    final subBg =
        (storage.getPlayerSetting('player_sub_bg') as num?)?.toInt() ??
        0x00000000;
    final subBgOpacity =
        (storage.getPlayerSetting('player_sub_bg_opacity') as num?)
            ?.toDouble() ??
        0.5;
    final prefPlayer = storage.getPlayerSetting<String>('player_preferred');
    final swipeSeek =
        storage.getPlayerSetting<bool>(
          'player_swipe_seek',
          defaultValue: true,
        ) ??
        true;
    final hwDec =
        storage.getPlayerSetting<bool>('player_hw_dec', defaultValue: true) ??
        true;
    final rSecons =
        storage.getPlayerSetting<int>('player_readahead', defaultValue: 180) ??
        180;
    final subPos =
        (storage.getPlayerSetting('player_sub_pos') as num?)?.toDouble() ??
        100.0;
    final showRemaining =
        storage.getPlayerSetting<bool>(
          'player_show_remaining',
          defaultValue: false,
        ) ??
        false;
    final defaultSpeed =
        (storage.getPlayerSetting('player_default_speed') as num?)
            ?.toDouble() ??
        1.0;
    final subFixedTextSize =
        (storage.getPlayerSetting('player_sub_fixed_text_size') as num?)
            ?.toDouble();
    final subTypeface = storage.getPlayerSetting<int>('player_sub_typeface');
    final subTypefaceFilePath = storage.getPlayerSetting<String>(
      'player_sub_typeface_file_path',
    );
    final subEdgeType =
        storage.getPlayerSetting<int>(
          'player_sub_edge_type',
          defaultValue: 1,
        ) ??
        1;
    final subEdgeSize =
        (storage.getPlayerSetting('player_sub_edge_size') as num?)?.toDouble();
    final subBackgroundRadius =
        (storage.getPlayerSetting('player_sub_bg_radius') as num?)?.toDouble();
    final subElevation =
        storage.getPlayerSetting<int>(
          'player_sub_elevation',
          defaultValue: 20,
        ) ??
        20;
    final subRemoveBloat =
        storage.getPlayerSetting<bool>(
          'player_sub_remove_bloat',
          defaultValue: true,
        ) ??
        true;
    final subRemoveCaptions =
        storage.getPlayerSetting<bool>(
          'player_sub_remove_captions',
          defaultValue: false,
        ) ??
        false;
    final subUpperCase =
        storage.getPlayerSetting<bool>(
          'player_sub_uppercase',
          defaultValue: false,
        ) ??
        false;
    final subBold =
        storage.getPlayerSetting<bool>(
          'player_sub_bold',
          defaultValue: false,
        ) ??
        false;
    final subItalic =
        storage.getPlayerSetting<bool>(
          'player_sub_italic',
          defaultValue: false,
        ) ??
        false;
    final subForegroundColor =
        storage.getPlayerSetting<int>(
          'player_sub_foreground_color',
          defaultValue: 0xFFFFFFFF,
        ) ??
        0xFFFFFFFF;
    final subBackgroundColor =
        storage.getPlayerSetting<int>(
          'player_sub_background_color',
          defaultValue: 0x00000000,
        ) ??
        0x00000000;
    final subEdgeColor =
        storage.getPlayerSetting<int>(
          'player_sub_edge_color',
          defaultValue: 0xFF000000,
        ) ??
        0xFF000000;
    final subBackgroundOpacity =
        (storage.getPlayerSetting(
                  'player_sub_background_opacity',
                  defaultValue: 0.5,
                )
                as num?)
            ?.toDouble() ??
        0.5;
    final subAlignment = storage.getPlayerSetting<int>('player_sub_alignment');

    final showPip = storage.getPlayerSetting<bool>(
          'player_show_pip',
          defaultValue: true,
        ) ??
        true;
    final showResize = storage.getPlayerSetting<bool>(
          'player_show_resize',
          defaultValue: true,
        ) ??
        true;
    final showRotate = storage.getPlayerSetting<bool>(
          'player_show_rotate',
          defaultValue: true,
        ) ??
        true;
    final showPlaybackSpeed = storage.getPlayerSetting<bool>(
          'player_show_playback_speed',
          defaultValue: true,
        ) ??
        true;
    final showEpisodes = storage.getPlayerSetting<bool>(
          'player_show_episodes',
          defaultValue: true,
        ) ??
        true;

    return PlayerSettings(
      leftGesture: _parse(l),
      rightGesture: _parse(r),
      doubleTapEnabled: dt,
      swipeSeekEnabled: swipeSeek,
      seekDuration: dur,
      defaultResizeMode: resize,
      subtitleSize: subSize,
      subtitleColor: subColor,
      subtitleBackgroundColor: subBg,
      subtitleBackgroundOpacity: subBgOpacity,
      hardwareDecoding: hwDec,
      preferredPlayer: prefPlayer,
      readaheadSeconds: rSecons,
      subtitlePosition: subPos,
      subFixedTextSize: subFixedTextSize,
      subTypeface: subTypeface,
      subTypefaceFilePath: subTypefaceFilePath,
      subEdgeType: subEdgeType,
      subEdgeSize: subEdgeSize,
      subBackgroundRadius: subBackgroundRadius,
      subElevation: subElevation,
      subRemoveBloat: subRemoveBloat,
      subRemoveCaptions: subRemoveCaptions,
      subUpperCase: subUpperCase,
      subBold: subBold,
      subItalic: subItalic,
      subForegroundColor: subForegroundColor,
      subBackgroundColor: subBackgroundColor,
      subEdgeColor: subEdgeColor,
      subBackgroundOpacity: subBackgroundOpacity,
      subAlignment: subAlignment,
      showRemainingTime: showRemaining,
      defaultPlaybackSpeed: defaultSpeed,
      showPip: showPip,
      showResize: showResize,
      showRotate: showRotate,
      showPlaybackSpeed: showPlaybackSpeed,
      showEpisodes: showEpisodes,
    );
  }

  Future<void> setSubtitleAppearanceSettings(PlayerSettings newSettings) async {
    final storage = _repository;

    // Sync the legacy settings to match the new appearance settings
    final syncedSettings = newSettings.copyWith(
      subtitleSize: newSettings.subFixedTextSize ?? 22.0,
      subtitleColor: newSettings.subForegroundColor,
      subtitleBackgroundColor: newSettings.subBackgroundColor,
      subtitleBackgroundOpacity: newSettings.subBackgroundOpacity,
    );

    await storage.setPlayerSetting(
      'player_sub_fixed_text_size',
      syncedSettings.subFixedTextSize,
    );
    await storage.setPlayerSetting(
      'player_sub_typeface',
      syncedSettings.subTypeface,
    );
    await storage.setPlayerSetting(
      'player_sub_typeface_file_path',
      syncedSettings.subTypefaceFilePath,
    );
    await storage.setPlayerSetting(
      'player_sub_edge_type',
      syncedSettings.subEdgeType,
    );
    await storage.setPlayerSetting(
      'player_sub_edge_size',
      syncedSettings.subEdgeSize,
    );
    await storage.setPlayerSetting(
      'player_sub_bg_radius',
      syncedSettings.subBackgroundRadius,
    );
    await storage.setPlayerSetting(
      'player_sub_elevation',
      syncedSettings.subElevation,
    );
    await storage.setPlayerSetting(
      'player_sub_remove_bloat',
      syncedSettings.subRemoveBloat,
    );
    await storage.setPlayerSetting(
      'player_sub_remove_captions',
      syncedSettings.subRemoveCaptions,
    );
    await storage.setPlayerSetting(
      'player_sub_uppercase',
      syncedSettings.subUpperCase,
    );
    await storage.setPlayerSetting('player_sub_bold', syncedSettings.subBold);
    await storage.setPlayerSetting(
      'player_sub_italic',
      syncedSettings.subItalic,
    );
    await storage.setPlayerSetting(
      'player_sub_foreground_color',
      syncedSettings.subForegroundColor,
    );
    await storage.setPlayerSetting(
      'player_sub_background_color',
      syncedSettings.subBackgroundColor,
    );
    await storage.setPlayerSetting(
      'player_sub_edge_color',
      syncedSettings.subEdgeColor,
    );
    await storage.setPlayerSetting(
      'player_sub_background_opacity',
      syncedSettings.subBackgroundOpacity,
    );
    await storage.setPlayerSetting(
      'player_sub_alignment',
      syncedSettings.subAlignment,
    );

    // Persist legacy settings to database too
    await storage.setPlayerSetting(
      'player_sub_size',
      syncedSettings.subtitleSize,
    );
    await storage.setPlayerSetting(
      'player_sub_color',
      syncedSettings.subtitleColor,
    );
    await storage.setPlayerSetting(
      'player_sub_bg',
      syncedSettings.subtitleBackgroundColor,
    );
    await storage.setPlayerSetting(
      'player_sub_bg_opacity',
      syncedSettings.subtitleBackgroundOpacity,
    );

    state = AsyncData(syncedSettings);
  }

  Future<void> resetSubtitleAppearanceSettings() async {
    final current = state.requireValue;
    final newState = current.copyWith(
      subFixedTextSize: () => null,
      subTypeface: () => null,
      subTypefaceFilePath: () => null,
      subEdgeType: 1,
      subEdgeSize: () => null,
      subBackgroundRadius: () => null,
      subElevation: 20,
      subRemoveBloat: true,
      subRemoveCaptions: false,
      subUpperCase: false,
      subBold: false,
      subItalic: false,
      subForegroundColor: 0xFFFFFFFF,
      subBackgroundColor: 0x00000000,
      subEdgeColor: 0xFF000000,
      subBackgroundOpacity: 0.5,
      subAlignment: () => null,
      // Reset legacy settings as well
      subtitleSize: 22.0,
      subtitleColor: 0xFFFFFFFF,
      subtitleBackgroundColor: 0x00000000,
      subtitleBackgroundOpacity: 0.5,
    );

    final storage = _repository;
    await storage.setPlayerSetting('player_sub_fixed_text_size', null);
    await storage.setPlayerSetting('player_sub_typeface', null);
    await storage.setPlayerSetting('player_sub_typeface_file_path', null);
    await storage.setPlayerSetting('player_sub_edge_type', 1);
    await storage.setPlayerSetting('player_sub_edge_size', null);
    await storage.setPlayerSetting('player_sub_bg_radius', null);
    await storage.setPlayerSetting('player_sub_elevation', 20);
    await storage.setPlayerSetting('player_sub_remove_bloat', true);
    await storage.setPlayerSetting('player_sub_remove_captions', false);
    await storage.setPlayerSetting('player_sub_uppercase', false);
    await storage.setPlayerSetting('player_sub_bold', false);
    await storage.setPlayerSetting('player_sub_italic', false);
    await storage.setPlayerSetting('player_sub_foreground_color', 0xFFFFFFFF);
    await storage.setPlayerSetting('player_sub_background_color', 0x00000000);
    await storage.setPlayerSetting('player_sub_edge_color', 0xFF000000);
    await storage.setPlayerSetting('player_sub_background_opacity', 0.5);
    await storage.setPlayerSetting('player_sub_alignment', null);

    // Reset legacy keys in storage too
    await storage.setPlayerSetting('player_sub_size', 22.0);
    await storage.setPlayerSetting('player_sub_color', 0xFFFFFFFF);
    await storage.setPlayerSetting('player_sub_bg', 0x00000000);
    await storage.setPlayerSetting('player_sub_bg_opacity', 0.5);

    state = AsyncData(newState);
  }

  Future<void> setLeftGesture(PlayerGesture g) async {
    await _repository.setPlayerSetting('player_gesture_left', g.name);
    state = AsyncData(state.requireValue.copyWith(leftGesture: g));
  }

  Future<void> setRightGesture(PlayerGesture g) async {
    await _repository.setPlayerSetting('player_gesture_right', g.name);
    state = AsyncData(state.requireValue.copyWith(rightGesture: g));
  }

  Future<void> setDoubleTapEnabled(bool val) async {
    await _repository.setPlayerSetting('player_double_tap', val);
    state = AsyncData(state.requireValue.copyWith(doubleTapEnabled: val));
  }

  Future<void> setSwipeSeekEnabled(bool val) async {
    await _repository.setPlayerSetting('player_swipe_seek', val);
    state = AsyncData(state.requireValue.copyWith(swipeSeekEnabled: val));
  }

  Future<void> setSeekDuration(int seconds) async {
    await _repository.setPlayerSetting('player_seek_duration', seconds);
    state = AsyncData(state.requireValue.copyWith(seekDuration: seconds));
  }

  Future<void> setDefaultResizeMode(String mode) async {
    await _repository.setPlayerSetting('player_default_resize', mode);
    state = AsyncData(state.requireValue.copyWith(defaultResizeMode: mode));
  }

  Future<void> setHardwareDecoding(bool val) async {
    await _repository.setPlayerSetting('player_hw_dec', val);
    state = AsyncData(state.requireValue.copyWith(hardwareDecoding: val));
  }

  Future<void> setShowPip(bool val) async {
    await _repository.setPlayerSetting('player_show_pip', val);
    state = AsyncData(state.requireValue.copyWith(showPip: val));
  }

  Future<void> setShowResize(bool val) async {
    await _repository.setPlayerSetting('player_show_resize', val);
    state = AsyncData(state.requireValue.copyWith(showResize: val));
  }

  Future<void> setShowRotate(bool val) async {
    await _repository.setPlayerSetting('player_show_rotate', val);
    state = AsyncData(state.requireValue.copyWith(showRotate: val));
  }

  Future<void> setShowPlaybackSpeed(bool val) async {
    await _repository.setPlayerSetting('player_show_playback_speed', val);
    state = AsyncData(state.requireValue.copyWith(showPlaybackSpeed: val));
  }

  Future<void> setShowEpisodes(bool val) async {
    await _repository.setPlayerSetting('player_show_episodes', val);
    state = AsyncData(state.requireValue.copyWith(showEpisodes: val));
  }

  Future<void> setSubtitleSettings(
    double size,
    int color,
    int bg, [
    double? opacity,
  ]) async {
    await _repository.setPlayerSetting('player_sub_size', size);
    await _repository.setPlayerSetting('player_sub_color', color);
    await _repository.setPlayerSetting('player_sub_bg', bg);
    if (opacity != null) {
      await _repository.setPlayerSetting('player_sub_bg_opacity', opacity);
    }
    state = AsyncData(
      state.requireValue.copyWith(
        subtitleSize: size,
        subtitleColor: color,
        subtitleBackgroundColor: bg,
        subtitleBackgroundOpacity:
            opacity ?? state.requireValue.subtitleBackgroundOpacity,
      ),
    );
  }

  Future<void> setPreferredPlayer(String? playerId) async {
    if (playerId == null) {
      await _repository.setPlayerSetting('player_preferred', null);
      state = AsyncData(
        state.requireValue.copyWith(clearPreferredPlayer: true),
      );
    } else {
      await _repository.setPlayerSetting('player_preferred', playerId);
      state = AsyncData(state.requireValue.copyWith(preferredPlayer: playerId));
    }
  }

  Future<void> setReadaheadSeconds(int seconds) async {
    await _repository.setPlayerSetting('player_readahead', seconds);
    state = AsyncData(state.requireValue.copyWith(readaheadSeconds: seconds));
  }

  Future<void> setSubtitlePosition(double pos) async {
    await _repository.setPlayerSetting('player_sub_pos', pos);
    state = AsyncData(state.requireValue.copyWith(subtitlePosition: pos));
  }

  Future<void> setSubtitleBackgroundOpacity(double val) async {
    await _repository.setPlayerSetting('player_sub_bg_opacity', val);
    state = AsyncData(
      state.requireValue.copyWith(subtitleBackgroundOpacity: val),
    );
  }

  Future<void> resetSubtitleSettings() async {
    final current = state.requireValue;
    final newState = current.copyWith(
      subtitleSize: 22.0,
      subtitleColor: 0xFFFFFFFF,
      subtitleBackgroundColor: 0x00000000,
      subtitleBackgroundOpacity: 0.5,
      subtitlePosition: 100.0,
    );

    await _repository.setPlayerSetting('player_sub_size', 22.0);
    await _repository.setPlayerSetting('player_sub_color', 0xFFFFFFFF);
    await _repository.setPlayerSetting('player_sub_bg', 0x00000000);
    await _repository.setPlayerSetting('player_sub_bg_opacity', 0.5);
    await _repository.setPlayerSetting('player_sub_pos', 100.0);

    state = AsyncData(newState);
  }

  Future<void> setShowRemainingTime(bool val) async {
    await _repository.setPlayerSetting('player_show_remaining', val);
    state = AsyncData(state.requireValue.copyWith(showRemainingTime: val));
  }

  Future<void> setDefaultPlaybackSpeed(double speed) async {
    await _repository.setPlayerSetting('player_default_speed', speed);
    state = AsyncData(state.requireValue.copyWith(defaultPlaybackSpeed: speed));
  }

  PlayerGesture _parse(String s) {
    return PlayerGesture.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PlayerGesture.none,
    );
  }


}
