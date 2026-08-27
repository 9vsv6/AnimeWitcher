import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clears the account session first, then always clears local application data.
///
/// Session and secure-token cleanup are best effort because a factory reset
/// must still remove local data if a platform sign-out integration is
/// temporarily unavailable. Keychain/Keystore tokens are wiped separately
/// because Hive `deleteAllData` does not touch them.
Future<void> runFactoryReset({
  required Future<void> Function() clearAccountSession,
  required Future<void> Function() clearLocalData,
  Future<void> Function()? clearSecureTokens,
}) async {
  try {
    await clearAccountSession();
  } catch (_) {
    // `clearAccountSession` already attempts local credential cleanup.
  }
  try {
    await (clearSecureTokens ?? wipePlatformSecureTokens)();
  } catch (_) {}
  await clearLocalData();
}

Future<void> wipePlatformSecureTokens() async {
  await const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  ).deleteAll();
}
