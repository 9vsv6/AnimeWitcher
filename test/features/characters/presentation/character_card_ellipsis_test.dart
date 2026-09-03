import 'package:animewitcher/core/account/animewitcher_character_models.dart';
import 'package:animewitcher/features/characters/presentation/character_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long character names keep one LTR ellipsis line', (
    tester,
  ) async {
    const name = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 280,
              child: CharacterPosterCard(
                character: AnimeWitcherCharacterHit(id: '1', name: name),
                onTap: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data == name && widget.maxLines == 1,
      ),
    );
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(label.textDirection, TextDirection.ltr);
  });
}

void _noop() {}
