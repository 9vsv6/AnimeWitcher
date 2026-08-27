import 'package:animewitcher/core/utils/factory_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears the account session then secure tokens then local data', () async {
    final calls = <String>[];

    await runFactoryReset(
      clearAccountSession: () async {
        calls.add('session');
      },
      clearSecureTokens: () async {
        calls.add('secure-tokens');
      },
      clearLocalData: () async {
        calls.add('local-data');
      },
    );

    expect(calls, <String>['session', 'secure-tokens', 'local-data']);
  });

  test('still clears secure tokens and local data if session cleanup fails',
      () async {
    final calls = <String>[];

    await runFactoryReset(
      clearAccountSession: () async {
        throw StateError('sign-out failed');
      },
      clearSecureTokens: () async {
        calls.add('secure-tokens');
      },
      clearLocalData: () async {
        calls.add('local-data');
      },
    );

    expect(calls, <String>['secure-tokens', 'local-data']);
  });

  test('still clears local data if secure token cleanup fails', () async {
    var localDataCleared = false;

    await runFactoryReset(
      clearAccountSession: () async {},
      clearSecureTokens: () async {
        throw StateError('keychain unavailable');
      },
      clearLocalData: () async {
        localDataCleared = true;
      },
    );

    expect(localDataCleared, isTrue);
  });
}
