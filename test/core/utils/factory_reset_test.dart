import 'package:animewitcher/core/utils/factory_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears the account session before local data', () async {
    final calls = <String>[];

    await runFactoryReset(
      clearAccountSession: () async {
        calls.add('session');
      },
      clearLocalData: () async {
        calls.add('local-data');
      },
    );

    expect(calls, <String>['session', 'local-data']);
  });

  test('still clears local data if session cleanup fails', () async {
    var localDataCleared = false;

    await runFactoryReset(
      clearAccountSession: () async {
        throw StateError('sign-out failed');
      },
      clearLocalData: () async {
        localDataCleared = true;
      },
    );

    expect(localDataCleared, isTrue);
  });
}
