/// Compile-time configuration used by AnimeSkip integration.
class SyncConfig {
  static const String animeSkipClientId = String.fromEnvironment(
    'ANIMESKIP_CLIENT_ID',
  );
}
