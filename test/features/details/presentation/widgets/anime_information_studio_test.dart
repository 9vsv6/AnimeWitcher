import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/widgets/anime_information_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('studio is primary-colored and tappable', (tester) async {
    final tapped = <String>[];
    final item = MultimediaItem(
      title: 'Test',
      url: 'https://example.test/anime',
      posterUrl: '',
      syncData: const {'awStudio': 'Madhouse'},
    );
    const primary = Color(0xFFEEC60A);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: primary),
        ),
        home: Scaffold(
          body: AnimeInformationSection(item: item, onStudioTap: tapped.add),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('Madhouse')).style?.color, primary);
    await tester.tap(find.text('Madhouse'));
    expect(tapped, const ['Madhouse']);
  });
}
