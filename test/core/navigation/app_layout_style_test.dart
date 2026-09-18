import 'package:animewitcher/core/navigation/app_layout_style.dart';
import 'package:animewitcher/shared/widgets/app_layout_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stored name reads back, anything else reads as no choice', () {
    for (final style in AppLayoutStyle.values) {
      expect(AppLayoutStyle.fromName(style.name), style);
    }
    expect(AppLayoutStyle.fromName(null), isNull);
    expect(AppLayoutStyle.fromName('sidebar'), isNull);
  });

  test('phones always get the bottom bar', () {
    for (final stored in <AppLayoutStyle?>[null, ...AppLayoutStyle.values]) {
      expect(
        effectiveAppLayout(stored: stored, isDesktopPlatform: false),
        AppLayoutStyle.dock,
      );
    }
  });

  test('a desktop draws its choice, and the bottom bar before one', () {
    expect(
      effectiveAppLayout(stored: null, isDesktopPlatform: true),
      AppLayoutStyle.dock,
    );
    for (final style in AppLayoutStyle.values) {
      expect(effectiveAppLayout(stored: style, isDesktopPlatform: true), style);
    }
  });

  test('only a desktop with no choice yet is asked', () {
    expect(
      shouldAskForAppLayout(stored: null, isDesktopPlatform: true),
      isTrue,
    );
    expect(
      shouldAskForAppLayout(stored: null, isDesktopPlatform: false),
      isFalse,
    );
    for (final style in AppLayoutStyle.values) {
      expect(
        shouldAskForAppLayout(stored: style, isDesktopPlatform: true),
        isFalse,
      );
    }
  });

  testWidgets('every layout preview draws without overflowing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final style in AppLayoutStyle.values)
                SizedBox(
                  width: 220,
                  child: AppLayoutOptionCard(
                    style: style,
                    arabic: true,
                    selected: style == AppLayoutStyle.dock,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('شريط جانبي'), findsOneWidget);
    expect(find.text('شريط علوي'), findsOneWidget);
    expect(find.text('الشريط السفلي'), findsOneWidget);
  });
}
