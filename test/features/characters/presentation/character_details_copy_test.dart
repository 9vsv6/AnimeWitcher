import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('character details comments action uses التعليقات', () {
    final source = File(
      'lib/features/characters/presentation/character_details_screen.dart',
    ).readAsStringSync();
    expect(source, contains("isArabic ? 'التعليقات'"));
    expect(source.contains("isArabic ? 'تعليقات'"), isFalse);
  });

  test('character details moves actions into the liquid glass header', () {
    final source = File(
      'lib/features/characters/presentation/character_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains('trailingButtons: headerButtons'));
    expect(source, contains('AppleLiquidGlassActionGroup('));
    expect(source, contains('icon: Icons.chat_bubble_outline_rounded'));
    expect(source, contains('icon: Icons.more_horiz_rounded'));
    expect(source, contains('child: const SizedBox.shrink()'));
    expect(source.contains('class _CharacterActionButton'), isFalse);
  });

  test('character actions follow anime placement outside iOS', () {
    final source = File(
      'lib/features/characters/presentation/character_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final isLarge = context.isTabletOrLarger'));
    expect(
      source,
      contains('left: 8 + windowControlsLeadingInset'),
    );
    expect(
      source,
      contains('right: 8 + windowControlsTrailingInset'),
    );
    expect(
      source,
      contains('appleUsesPersistentLiquidGlassHeader || isLarge'),
    );
    expect(
      source,
      contains('!appleUsesPersistentLiquidGlassHeader && isLarge'),
    );
  });

  test('character iOS glass matches anime inset and comments can morph', () {
    final characterSource = File(
      'lib/features/characters/presentation/character_details_screen.dart',
    ).readAsStringSync();
    final commentsSource = File(
      'lib/features/comments/presentation/animewitcher_comments_screen.dart',
    ).readAsStringSync();
    final glassSource = File(
      'lib/shared/widgets/apple_liquid_glass.dart',
    ).readAsStringSync();

    expect(characterSource, contains('toolbarTrailingInset: 34'));
    expect(commentsSource, contains('allowInstantBoundaryMorph: true'));
    expect(glassSource, contains('config?.toolbarTrailingInset ??'));
    expect(glassSource, contains('hardCutInstantBoundary'));
    expect(glassSource, contains('!allowInstantBoundaryMorph'));
  });

  test('details screen hides the empty characters copy', () {
    final source = File(
      'lib/features/details/presentation/details_screen.dart',
    ).readAsStringSync();
    expect(source.contains('لم يتم اضافة الشخصيات حتي الان'), isFalse);
    expect(source.contains('No characters have been added yet'), isFalse);
  });
}
