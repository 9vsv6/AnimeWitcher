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
        locale: const Locale('ar'),
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

    final reveal = find.byKey(
      const ValueKey<String>('expandable-text-size-transition'),
    );
    expect(reveal, findsOneWidget);
    final collapsed = tester.getSize(reveal).height;

    await tester.tap(find.text('عرض المزيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = tester.getSize(reveal).height;

    await tester.pumpAndSettle();
    final expanded = tester.getSize(reveal).height;

    expect(mid, greaterThan(collapsed));
    expect(mid, lessThan(expanded));

    await tester.tap(find.text('عرض أقل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final collapsing = tester.getSize(reveal).height;
    expect(collapsing, lessThan(expanded));
    expect(collapsing, greaterThan(collapsed));
  });
}
