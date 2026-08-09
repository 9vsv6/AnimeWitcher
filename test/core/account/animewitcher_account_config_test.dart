import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/account/animewitcher_account_config.dart';

void main() {
  group('AnimeWitcher registration email domains', () {
    test('accepts the providers used by the official client', () {
      expect(
        AnimeWitcherAccountConfig.isTrustedRegistrationEmail(
          'person@gmail.com',
        ),
        isTrue,
      );
      expect(
        AnimeWitcherAccountConfig.isTrustedRegistrationEmail(
          'PERSON@OUTLOOK.COM',
        ),
        isTrue,
      );
      expect(
        AnimeWitcherAccountConfig.isTrustedRegistrationEmail(
          'person@yahoo.com',
        ),
        isTrue,
      );
    });

    test('does not accept a trusted domain embedded in another host', () {
      expect(
        AnimeWitcherAccountConfig.isTrustedRegistrationEmail(
          'person@gmail.com.example.org',
        ),
        isFalse,
      );
    });
  });
}
