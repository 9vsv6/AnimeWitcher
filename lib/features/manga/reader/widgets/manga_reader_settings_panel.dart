import 'package:flutter/material.dart';

import '../manga_reader_settings.dart';

/// The reader's one settings button opens this: a floating card over the
/// page, its sections as tabs along the bottom and each section's choices
/// as large cards above them, the way Harbor lays out its reader settings.
///
/// It edits what the reader already has; the full list stays one tap away
/// behind "all settings".
class MangaReaderSettingsPanel extends StatefulWidget {
  const MangaReaderSettingsPanel({
    super.key,
    required this.settings,
    required this.mode,
    required this.doublePage,
    required this.onMode,
    required this.onDoublePage,
    required this.onUpdate,
    required this.onOpenAllSettings,
  });

  final MangaReaderSettings settings;

  /// The mode this manga is being read in, which can differ from the default.
  final MangaReaderMode mode;

  /// Whether two pages show side by side.
  final bool doublePage;

  final ValueChanged<MangaReaderMode> onMode;
  final ValueChanged<bool> onDoublePage;
  final void Function(MangaReaderSettings Function(MangaReaderSettings))
  onUpdate;
  final VoidCallback onOpenAllSettings;

  @override
  State<MangaReaderSettingsPanel> createState() =>
      _MangaReaderSettingsPanelState();
}

enum _Tab { mode, direction, fit, background, more }

/// The same mode turned the other way, or null when it has no direction.
MangaReaderMode? mangaReaderModeWithDirection(
  MangaReaderMode mode, {
  required bool rtl,
}) => switch (mode) {
  MangaReaderMode.pagedLtr || MangaReaderMode.pagedRtl =>
    rtl ? MangaReaderMode.pagedRtl : MangaReaderMode.pagedLtr,
  MangaReaderMode.horizontalContinuous ||
  MangaReaderMode.horizontalContinuousRtl =>
    rtl
        ? MangaReaderMode.horizontalContinuousRtl
        : MangaReaderMode.horizontalContinuous,
  _ => null,
};

class _MangaReaderSettingsPanelState extends State<MangaReaderSettingsPanel> {
  _Tab _tab = _Tab.mode;

  // The theme's own surfaces, so the panel matches the app in every theme.
  ColorScheme get _colors => Theme.of(context).colorScheme;
  Color get _panel => _colors.surfaceContainerHigh;
  Color get _card => _colors.surfaceContainerHighest;
  Color get _muted => _colors.onSurfaceVariant;
  Color get _text => _colors.onSurface;

  bool get _ar =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
  String _t(String en, String ar) => _ar ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('manga-reader-settings-panel'),
      color: _panel,
      elevation: 12,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: KeyedSubtree(
                  key: ValueKey<_Tab>(_tab),
                  child: _section(context),
                ),
              ),
              const SizedBox(height: 14),
              _tabs(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final tabs = <(_Tab, IconData, String)>[
      (
        _Tab.mode,
        Icons.auto_stories_outlined,
        _t('Reading mode', 'وضع القراءة'),
      ),
      (_Tab.direction, Icons.swap_horiz_rounded, _t('Direction', 'الاتجاه')),
      (_Tab.fit, Icons.fit_screen_outlined, _t('Fit', 'الملاءمة')),
      (_Tab.background, Icons.contrast_rounded, _t('Background', 'الخلفية')),
      (_Tab.more, Icons.tune_rounded, _t('More', 'المزيد')),
    ];
    return Row(
      children: <Widget>[
        for (final (tab, icon, label) in tabs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                key: ValueKey<String>('manga-reader-panel-tab-${tab.name}'),
                color: _tab == tab
                    ? accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _tab = tab),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: <Widget>[
                        Icon(
                          icon,
                          size: 22,
                          color: _tab == tab ? accent : _muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            color: _tab == tab ? accent : _muted,
                            fontWeight: _tab == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(BuildContext context) => switch (_tab) {
    _Tab.mode => _modeSection(context),
    _Tab.direction => _directionSection(context),
    _Tab.fit => _fitSection(context),
    _Tab.background => _backgroundSection(context),
    _Tab.more => _moreSection(context),
  };

  Widget _cards(List<Widget> cards) => Wrap(
    spacing: 10,
    runSpacing: 10,
    alignment: WrapAlignment.center,
    children: cards,
  );

  Widget _choice({
    required String keyName,
    required Widget visual,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        key: ValueKey<String>('manga-reader-choice-$keyName'),
        color: selected ? accent.withValues(alpha: 0.14) : _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: SizedBox(
              width: 112,
              height: 116,
              child: Stack(
                children: <Widget>[
                  if (selected)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: accent,
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: _colors.onPrimary,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          visual,
                          const SizedBox(height: 8),
                          ExcludeSemantics(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon) => Icon(icon, size: 34, color: _text);

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
    ),
  );

  Widget _switch({
    required String keyName,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    key: ValueKey<String>('manga-reader-switch-$keyName'),
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: Text(
      label,
      style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600),
    ),
    value: value,
    onChanged: onChanged,
  );

  /// Every reading mode the reader has, each as its own card, and two pages
  /// side by side as a switch for the modes that turn pages.
  Widget _modeSection(BuildContext context) {
    Widget card(MangaReaderMode mode, IconData icon, String label) => _choice(
      keyName: 'mode-${mode.name}',
      visual: _icon(icon),
      label: label,
      selected: widget.mode == mode,
      onTap: widget.mode == mode ? () {} : () => widget.onMode(mode),
    );
    final paged =
        widget.mode == MangaReaderMode.pagedLtr ||
        widget.mode == MangaReaderMode.pagedRtl ||
        widget.mode == MangaReaderMode.vertical;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _cards(<Widget>[
          card(
            MangaReaderMode.webtoon,
            Icons.view_day_outlined,
            _t('Webtoon', 'ويب تون'),
          ),
          card(
            MangaReaderMode.verticalContinuous,
            Icons.view_stream_outlined,
            _t('Vertical continuous', 'عمودي مستمر'),
          ),
          card(
            MangaReaderMode.vertical,
            Icons.swipe_vertical_outlined,
            _t('Vertical', 'عمودي'),
          ),
          card(
            MangaReaderMode.pagedRtl,
            Icons.format_textdirection_r_to_l_rounded,
            _t('Right to left', 'من اليمين لليسار'),
          ),
          card(
            MangaReaderMode.pagedLtr,
            Icons.format_textdirection_l_to_r_rounded,
            _t('Left to right', 'من اليسار لليمين'),
          ),
          card(
            MangaReaderMode.horizontalContinuous,
            Icons.view_week_outlined,
            _t('Horizontal continuous', 'أفقي مستمر'),
          ),
          card(
            MangaReaderMode.horizontalContinuousRtl,
            Icons.view_week_rounded,
            _t('Horizontal continuous (RTL)', 'أفقي مستمر (RTL)'),
          ),
        ]),
        if (paged) ...<Widget>[
          const SizedBox(height: 6),
          _switch(
            keyName: 'double-page',
            label: _t('Two pages side by side', 'صفحتان جنبًا إلى جنب'),
            value: widget.doublePage,
            onChanged: widget.onDoublePage,
          ),
        ],
      ],
    );
  }

  Widget _directionSection(BuildContext context) {
    final ltrMode = mangaReaderModeWithDirection(widget.mode, rtl: false);
    final applies = ltrMode != null;
    final rtl = widget.mode.isRtl;
    void pick(bool toRtl) {
      final next = mangaReaderModeWithDirection(widget.mode, rtl: toRtl);
      if (next != null && next != widget.mode) widget.onMode(next);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _cards(<Widget>[
          _choice(
            keyName: 'ltr',
            visual: _icon(Icons.format_textdirection_l_to_r_rounded),
            label: _t('Left to right', 'من اليسار لليمين'),
            selected: applies && !rtl,
            onTap: applies ? () => pick(false) : null,
          ),
          _choice(
            keyName: 'rtl',
            visual: _icon(Icons.format_textdirection_r_to_l_rounded),
            label: _t('Right to left', 'من اليمين لليسار'),
            selected: applies && rtl,
            onTap: applies ? () => pick(true) : null,
          ),
        ]),
        if (!applies)
          _note(
            _t(
              'A strip reads top to bottom, so direction applies to page and horizontal modes.',
              'الشريط يُقرأ من الأعلى للأسفل، لذا الاتجاه للأوضاع ذات الصفحات والأفقية فقط.',
            ),
          ),
        if (widget.doublePage)
          _switch(
            keyName: 'invert-double',
            label: _t('Swap the two pages', 'عكس الصفحتين'),
            value: widget.settings.dualPageInvert,
            onChanged: (value) =>
                widget.onUpdate((s) => s.copyWith(dualPageInvert: value)),
          ),
      ],
    );
  }

  Widget _fitSection(BuildContext context) {
    Widget card(MangaReaderScaleType type, IconData icon, String label) =>
        _choice(
          keyName: 'fit-${type.name}',
          visual: _icon(icon),
          label: label,
          selected: widget.settings.scaleType == type,
          onTap: () => widget.onUpdate((s) => s.copyWith(scaleType: type)),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _cards(<Widget>[
          card(
            MangaReaderScaleType.fitScreen,
            Icons.fit_screen_outlined,
            _t('Fit screen', 'ملء الشاشة'),
          ),
          card(
            MangaReaderScaleType.fitWidth,
            Icons.width_normal_outlined,
            _t('Fit width', 'ملاءمة العرض'),
          ),
          card(
            MangaReaderScaleType.fitHeight,
            Icons.height_rounded,
            _t('Fit height', 'ملاءمة الارتفاع'),
          ),
          card(
            MangaReaderScaleType.originalSize,
            Icons.crop_free_rounded,
            _t('Original', 'الحجم الأصلي'),
          ),
        ]),
        const SizedBox(height: 6),
        _switch(
          keyName: 'crop',
          label: _t('Crop borders', 'قص الحواف'),
          value: widget.settings.cropBorders,
          onChanged: (value) =>
              widget.onUpdate((s) => s.copyWith(cropBorders: value)),
        ),
      ],
    );
  }

  Widget _backgroundSection(BuildContext context) {
    Widget swatch(Color color, {bool split = false}) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: split ? null : color,
        gradient: split
            ? const LinearGradient(
                colors: <Color>[
                  Colors.black,
                  Colors.black,
                  Colors.white,
                  Colors.white,
                ],
                stops: <double>[0, 0.5, 0.5, 1],
              )
            : null,
        border: Border.all(color: _colors.outlineVariant),
      ),
    );
    Widget card(MangaReaderBackground value, Widget visual, String label) =>
        _choice(
          keyName: 'background-${value.name}',
          visual: visual,
          label: label,
          selected: widget.settings.background == value,
          onTap: () => widget.onUpdate((s) => s.copyWith(background: value)),
        );
    return _cards(<Widget>[
      card(
        MangaReaderBackground.black,
        swatch(Colors.black),
        _t('Dark', 'داكن'),
      ),
      card(
        MangaReaderBackground.grey,
        swatch(const Color(0xFF5A5A5A)),
        _t('Dim', 'معتم'),
      ),
      card(
        MangaReaderBackground.white,
        swatch(Colors.white),
        _t('Light', 'فاتح'),
      ),
      card(
        MangaReaderBackground.automatic,
        swatch(Colors.black, split: true),
        _t('Automatic', 'تلقائي'),
      ),
    ]);
  }

  Widget _moreSection(BuildContext context) {
    final settings = widget.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _switch(
          keyName: 'keep-on',
          label: _t('Keep screen on', 'إبقاء الشاشة مضاءة'),
          value: settings.keepScreenOn,
          onChanged: (value) =>
              widget.onUpdate((s) => s.copyWith(keepScreenOn: value)),
        ),
        _switch(
          keyName: 'page-number',
          label: _t('Show page number', 'إظهار رقم الصفحة'),
          value: settings.showPageNumber,
          onChanged: (value) =>
              widget.onUpdate((s) => s.copyWith(showPageNumber: value)),
        ),
        _switch(
          keyName: 'vertical-bar',
          label: _t('Page bar down the side', 'شريط الصفحات عمودي على الجانب'),
          value: settings.verticalPageBar,
          onChanged: (value) =>
              widget.onUpdate((s) => s.copyWith(verticalPageBar: value)),
        ),
        _switch(
          keyName: 'page-gaps',
          label: _t('Gaps between pages', 'فواصل بين الصفحات'),
          value: settings.showPageGaps,
          onChanged: (value) =>
              widget.onUpdate((s) => s.copyWith(showPageGaps: value)),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey<String>('manga-reader-all-settings'),
            onPressed: widget.onOpenAllSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: Text(_t('All reader settings', 'كل إعدادات القارئ')),
          ),
        ),
      ],
    );
  }
}
