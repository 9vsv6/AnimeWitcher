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

  test('details screen hides the empty characters copy', () {
    final source = File(
      'lib/features/details/presentation/details_screen.dart',
    ).readAsStringSync();
    expect(source.contains('لم يتم اضافة الشخصيات حتي الان'), isFalse);
    expect(source.contains('No characters have been added yet'), isFalse);
  });
}
