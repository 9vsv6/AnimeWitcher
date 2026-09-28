import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/expandable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('show more and show less animate the story height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const story =
        'A very long story that needs several lines to render. '
        'A very long story that needs several lines to render. '
        'A very long story that needs several lines to render. '
        'A very long story that needs several lines to render. '
        'A very long story that needs several lines to render.';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 220,
            child: ExpandableText(
              key: ValueKey<String>('story'),
              text: story,
              maxLines: 2,
            ),
          ),
        ),
      ),
    );

    final storyFinder = find.byKey(const ValueKey<String>('story'));
    final collapsed = tester.getSize(storyFinder).height;

    await tester.tap(find.text('Show more'));
    await tester.pump(const Duration(milliseconds: 80));
    final mid = tester.getSize(storyFinder).height;

    await tester.pumpAndSettle();
    final expanded = tester.getSize(storyFinder).height;

    expect(mid, greaterThan(collapsed));
    expect(mid, lessThan(expanded));

    await tester.tap(find.text('Show less'));
    await tester.pump(const Duration(milliseconds: 80));
    final collapsing = tester.getSize(storyFinder).height;
    expect(collapsing, lessThan(expanded));
    expect(collapsing, greaterThan(collapsed));
  });
}
