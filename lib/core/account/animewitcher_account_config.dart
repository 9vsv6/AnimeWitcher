import 'package:flutter/foundation.dart';

/// Public Firebase client configuration used by the official AnimeWitcher
/// application.
///
/// Firebase API keys identify a client project; they are not server secrets.
/// Every value can still be replaced at build time so forks can point the
/// account feature at their own Firebase project.
class AnimeWitcherAccountConfig {
  const AnimeWitcherAccountConfig._();

  static const Set<String> trustedRegistrationEmailDomains = <String>{
    'gmail.com',
    'outlook.com',
    'yahoo.com',
  };

  static const String projectId = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_PROJECT_ID',
    defaultValue: 'animewitcher-1c66d',
  );

  static const String apiKey = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_API_KEY',
    defaultValue: 'AIzaSyAcbWRwfFNnCpoydDXlEALWnM_TYVcJOMU',
  );

  /// OAuth web/server client used to request a Google ID token which Firebase
  /// can exchange for an AnimeWitcher session.
  static const String googleServerClientId = String.fromEnvironment(
    'ANIMEWITCHER_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '861470152250-pfkag6v2dvos8v2sl1faftic0ckcr114.apps.googleusercontent.com',
  );

  /// iOS requires its own OAuth client and reversed URL scheme. This is left
  /// build-configurable because it must be registered for SkyStream's bundle
  /// identifier; copying AnimeWitcher's Android client would not work.
  static const String googleIosClientId = String.fromEnvironment(
    'ANIMEWITCHER_GOOGLE_IOS_CLIENT_ID',
  );

  static bool get firebaseConfigured =>
      projectId.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// The official AnimeWitcher registration screen accepts these three mail
  /// providers. Sign-in itself remains open to existing legacy accounts.
  static bool isTrustedRegistrationEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final separator = normalized.lastIndexOf('@');
    if (separator <= 0 || separator == normalized.length - 1) return false;
    return trustedRegistrationEmailDomains.contains(
      normalized.substring(separator + 1),
    );
  }

  static bool get googleConfigured {
    if (kIsWeb) return googleServerClientId.trim().isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS =>
        googleIosClientId.trim().isNotEmpty &&
            googleServerClientId.trim().isNotEmpty,
      TargetPlatform.android => googleServerClientId.trim().isNotEmpty,
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.fuchsia => false,
    };
  }
}
