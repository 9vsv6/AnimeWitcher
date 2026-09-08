import 'package:animewitcher/features/player/data/anime4k.dart';
import 'package:animewitcher/features/player/presentation/widgets/anime4k_player_sheet.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the sheet and returns what it was told, so a test can check the
/// panel drives the player rather than only that it draws.
class _Recorded {
  final List<Anime4kMode> modes = <Anime4kMode>[];
  final List<Anime4kQuality> qualities = <Anime4kQuality>[];
  final List<bool> compares = <bool>[];
}

Future<_Recorded> _open(
  WidgetTester tester, {
  Anime4kMode mode = Anime4kMode.a,
  Anime4kQuality quality = Anime4kQuality.l,
  String applied = 'a/Anime4K_Clamp_Highlights.glsl;a/Anime4K_Restore_CNN_L.glsl',
}) async {
  final recorded = _Recorded();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Anime4kPlayerSheet.show(
            context: context,
            currentMode: mode,
            currentQuality: quality,
            onModeSelected: recorded.modes.add,
            onQualitySelected: recorded.qualities.add,
            appliedValue: () async => applied,
            onCompareHeld: (value) async => recorded.compares.add(value),
            captureSource: () async => null,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return recorded;
}

void main() {
  testWidgets('builds without throwing', (tester) async {
    // The status line once held a regex whose lookbehind was never closed,
    // so every build threw a FormatException. In release that paints a plain
    // grey rectangle, which reads as a broken image rather than a crash — a
    // failure that survived because nothing pumped this widget.
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Anime4K'), findsOneWidget);
  });

  testWidgets('counts the shaders mpv reports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _open(tester);
    expect(find.textContaining('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when mpv is running none', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _open(tester, applied: '');
    expect(find.textContaining('لا يشغّل'), findsOneWidget);
  });

  group('the switch comes first', () {
    testWidgets('off hides the modes and everything under them', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _open(tester, mode: Anime4kMode.off);

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('النمط'), findsNothing);
      expect(find.text('الجودة'), findsNothing);
      expect(find.textContaining('للمقارنة'), findsNothing);
    });

    testWidgets('on shows them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _open(tester, mode: Anime4kMode.a);

      expect(find.text('النمط'), findsOneWidget);
      expect(find.text('الجودة'), findsOneWidget);
      expect(find.textContaining('للمقارنة'), findsOneWidget);
    });

    testWidgets('off is no longer one of the modes to choose from', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _open(tester, mode: Anime4kMode.a);
      // Switching the feature off should not look like picking a kind of
      // enhancement called "off".
      expect(find.widgetWithText(ChoiceChip, 'إيقاف'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'A'), findsOneWidget);
    });

    testWidgets('turning it on restores the mode that was chosen before', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recorded = await _open(tester, mode: Anime4kMode.ca);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(recorded.modes.last, Anime4kMode.off);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        recorded.modes.last,
        Anime4kMode.ca,
        reason: 'flicking the switch must not discard the chosen mode',
      );
    });

    testWidgets('turning it on with nothing chosen starts at A', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recorded = await _open(tester, mode: Anime4kMode.off);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(recorded.modes.last, Anime4kMode.a);
    });
  });

  testWidgets('holding compare suspends the shaders and releasing restores', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final recorded = await _open(tester);
    final bar = find.textContaining('للمقارنة');
    await tester.ensureVisible(bar);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    expect(recorded.compares, <bool>[true]);

    await gesture.up();
    await tester.pump();
    expect(recorded.compares, <bool>[true, false]);
  });

  testWidgets('choosing a mode and a quality reaches the player', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final recorded = await _open(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'C'));
    await tester.pumpAndSettle();
    expect(recorded.modes.last, Anime4kMode.c);

    await tester.tap(find.widgetWithText(ChoiceChip, 'UL'));
    await tester.pumpAndSettle();
    expect(recorded.qualities.last, Anime4kQuality.ul);
  });
}
