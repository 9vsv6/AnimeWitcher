/// Clears the account session first, then always clears local application data.
///
/// The session cleanup is best effort because a factory reset must still remove
/// local data if a platform sign-out integration is temporarily unavailable.
Future<void> runFactoryReset({
  required Future<void> Function() clearAccountSession,
  required Future<void> Function() clearLocalData,
}) async {
  try {
    await clearAccountSession();
  } catch (_) {
    // `clearAccountSession` already attempts local credential cleanup.
  }
  await clearLocalData();
}
