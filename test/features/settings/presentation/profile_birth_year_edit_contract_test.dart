import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'existing birth year stays editable and profile service accepts changes',
    () {
      final screen = File(
        'lib/features/settings/presentation/account_management_screens.dart',
      ).readAsStringSync();
      final service = File('lib/core/account/animewitcher_account_service.dart')
          .readAsStringSync();

      expect(screen, isNot(contains('_birthYearLocked')));
      expect(screen, isNot(contains('readOnly: _birthYearLocked')));
      expect(screen, isNot(contains('allows this to be set once')));
      expect(screen, isNot(contains('بحفظها مرة واحدة فقط')));
      expect(screen, contains("english: 'Optional · 1970–2020'"));

      expect(service, isNot(contains("'birth-year-locked'")));
      expect(service, isNot(contains('The birth year can only be set once.')));
      expect(service, contains("'birth_date'"));
    },
  );
}
