import 'package:animewitcher/shared/widgets/multimedia_card.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('announces a content card as an actionable details button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultimediaCard(
            imageUrl: null,
            title: 'عنوان تجريبي',
            heroTag: 'semantic-test-card',
            onTap: () {},
          ),
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
}
