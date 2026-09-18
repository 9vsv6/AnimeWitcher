import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/onboarding/first_run_setup_screen.dart';
import 'package:animewitcher/features/player/presentation/widgets/skip_segment_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_storage_service.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    // The window itself, not only the drawing surface: the screen decides
    // between its wide and narrow layouts from the window's size.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(MemoryStorageService()),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: FirstRunSetupScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Walks every step with Next, checking each one draws cleanly, and
  /// returns the step titles seen.
  Future<List<String>> walkSteps(WidgetTester tester) async {
    const titles = ['المظهر', 'صفحة الأنمي', 'المشغل', 'الحساب'];
    final seen = <String>[];
    for (var guard = 0; guard < 5; guard++) {
      expect(tester.takeException(), isNull);
      for (final title in titles) {
        if (find.text(title).evaluate().isNotEmpty) seen.add(title);
      }
      if (find.text('ابدأ المشاهدة').evaluate().isNotEmpty) break;
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
    }
    return seen;
  }

  testWidgets('every step draws side by side on a wide window', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    final seen = await walkSteps(tester);
    expect(seen, containsAllInOrder(['المظهر', 'صفحة الأنمي', 'المشغل']));
  });

  testWidgets('every step draws stacked on a phone-sized window', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    final seen = await walkSteps(tester);
    expect(seen, containsAllInOrder(['المظهر', 'صفحة الأنمي', 'المشغل']));
  });

  testWidgets('a desktop starts with the layout step, all three drawn', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAt(tester, const Size(1280, 800));
      expect(find.text('المظهر'), findsOneWidget);
      expect(find.text('شكل التطبيق'), findsOneWidget);
      for (final label in ['شريط جانبي', 'شريط علوي', 'الشريط السفلي']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      final seen = await walkSteps(tester);
      expect(seen, containsAllInOrder(['المظهر', 'صفحة الأنمي', 'المشغل']));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Anime4K turns on, offers its models, and fills the frame', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));
    while (find.text('المشغل').evaluate().isEmpty) {
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
    }
    // The picture fills the preview frame, on and off.
    Size pictureSize() => tester.getSize(find.byType(Image).first);
    expect(pictureSize().width, greaterThan(400));

    await tester.tap(find.text('Anime4K · تحسين الصورة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A + A'), findsOneWidget);
    expect(find.textContaining('Anime4K · A'), findsOneWidget);
    expect(pictureSize().width, greaterThan(400));

    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anime4K · C'), findsOneWidget);
  });

  testWidgets('the preview follows the choices', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    while (find.text('المشغل').evaluate().isEmpty) {
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
    }
    // Skipping is on by default: the button shows, the automatic options
    // are offered.
    expect(find.byType(SkipPill), findsOneWidget);
    expect(find.text('تخطي المقدمة تلقائيًا'), findsOneWidget);

    // Off: no button, and the automatic options go with it.
    await tester.tap(find.text('تخطي المقدمة والخاتمة'));
    await tester.pumpAndSettle();
    expect(find.byType(SkipPill), findsNothing);
    expect(find.text('تخطي المقدمة تلقائيًا'), findsNothing);

    await tester.tap(find.text('تخطي المقدمة والخاتمة'));
    await tester.pumpAndSettle();
    expect(find.byType(SkipPill), findsOneWidget);

    await tester.tap(find.text('تخطي المقدمة تلقائيًا'));
    await tester.pumpAndSettle();
    // Automatic: no button — the real player shows none — and a note
    // under the preview says why.
    expect(find.byType(SkipPill), findsNothing);
    expect(find.textContaining('مع التخطي التلقائي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
