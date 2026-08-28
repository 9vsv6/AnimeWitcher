import 'package:animewitcher/shared/widgets/multimedia_card.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _cardApp({required MultimediaCard card}) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: card),
  );
}

void main() {
  testWidgets('announces a content card as an actionable details button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardApp(
        card: MultimediaCard(
          imageUrl: null,
          title: 'عنوان تجريبي',
          heroTag: 'semantic-test-card',
          onTap: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('عنوان تجريبي')),
      matchesSemantics(
        label: 'عنوان تجريبي',
        hint: 'عرض التفاصيل',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('includes the episode badge in the announced label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardApp(
        card: MultimediaCard(
          imageUrl: null,
          title: 'عنوان تجريبي',
          episodeBadge: 'الحلقة 12',
          heroTag: 'semantic-test-card-badge',
          onTap: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('عنوان تجريبي، الحلقة 12')),
      matchesSemantics(
        label: 'عنوان تجريبي، الحلقة 12',
        hint: 'عرض التفاصيل',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('renders the content title left-to-right in an Arabic app', (
    tester,
  ) async {
    const title = 'Ore dake Level Up na Ken';
    await tester.pumpWidget(
      _cardApp(
        card: MultimediaCard(
          imageUrl: null,
          title: title,
          heroTag: 'ltr-title-card',
          onTap: () {},
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == title &&
            widget.textDirection == TextDirection.ltr,
      ),
      findsOneWidget,
    );
  });
}
