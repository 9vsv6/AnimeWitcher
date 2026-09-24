import 'package:animewitcher/features/manga/reader/manga_reader_settings.dart';
import 'package:animewitcher/features/manga/reader/widgets/manga_reader_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading direction', () {
    test('a strip has no direction to turn', () {
      expect(
        mangaReaderModeWithDirection(MangaReaderMode.webtoon, rtl: true),
        isNull,
      );
      expect(
        mangaReaderModeWithDirection(MangaReaderMode.pagedLtr, rtl: true),
        MangaReaderMode.pagedRtl,
      );
    });
  });

  group('panel', () {
    late MangaReaderMode? pickedMode;
    late bool? pickedDouble;
    late MangaReaderSettings settings;

    Future<void> pump(
      WidgetTester tester, {
      MangaReaderMode mode = MangaReaderMode.pagedLtr,
      bool doublePage = false,
    }) async {
      pickedMode = null;
      pickedDouble = null;
      settings = const MangaReaderSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => MangaReaderSettingsPanel(
                  settings: settings,
                  mode: mode,
                  doublePage: doublePage,
                  onMode: (value) => pickedMode = value,
                  onDoublePage: (value) => pickedDouble = value,
                  onUpdate: (change) =>
                      setState(() => settings = change(settings)),
                  onOpenAllSettings: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('two pages is a switch under the page modes', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-switch-double-page')),
      );
      expect(pickedDouble, isTrue);
      expect(pickedMode, isNull, reason: 'the mode itself is unchanged');
    });

    testWidgets('every reading mode has its own card', (tester) async {
      await pump(tester);

      for (final mode in MangaReaderMode.values) {
        expect(
          find.byKey(ValueKey<String>('manga-reader-choice-mode-${mode.name}')),
          findsOneWidget,
          reason: mode.name,
        );
      }
    });

    testWidgets('a mode card switches the mode', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-choice-mode-webtoon')),
      );
      expect(pickedMode, MangaReaderMode.webtoon);
    });

    testWidgets('direction is offered only where it applies', (tester) async {
      await pump(tester, mode: MangaReaderMode.webtoon);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-panel-tab-direction')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-choice-rtl')),
      );
      expect(pickedMode, isNull, reason: 'a strip has no direction');

      await pump(tester, mode: MangaReaderMode.pagedLtr);
      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-panel-tab-direction')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-choice-rtl')),
      );
      expect(pickedMode, MangaReaderMode.pagedRtl);
    });

    testWidgets('fit and background change the saved settings', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-panel-tab-fit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-choice-fit-fitWidth')),
      );
      await tester.pumpAndSettle();
      expect(settings.scaleType, MangaReaderScaleType.fitWidth);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-panel-tab-background')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('manga-reader-choice-background-white'),
        ),
      );
      await tester.pumpAndSettle();
      expect(settings.background, MangaReaderBackground.white);
    });

    testWidgets('the page bar can be put down the side', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-panel-tab-more')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('manga-reader-switch-vertical-bar')),
      );
      await tester.pumpAndSettle();

      expect(settings.verticalPageBar, isTrue);
    });
  });
}
