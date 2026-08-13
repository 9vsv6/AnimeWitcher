import 'package:flutter/foundation.dart';

/// Build-time client configuration for AnimeWitcher account synchronization.
///
/// Firebase client keys are identifiers rather than authorization secrets, but
/// they must not be committed as an unrestricted shared credential. Release
/// builds receive these values through `--dart-define-from-file` and GitHub
/// Actions secrets.
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
  );

  /// Firebase Android app id recovered from the original AnimeWitcher client.
  /// This must never be passed to the Apple Firebase SDK.
  static const String appId = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_APP_ID',
    defaultValue: '1:861470152250:android:bd3e0dd41508f61b094703',
  );

  /// A real Apple Firebase app id, if the AnimeWitcher project ever registers
  /// SkyStream's Apple bundle. Keep empty by default: inventing/reusing the
  /// Android app id can terminate FirebaseInstallations during iOS startup.
  static const String iosAppId = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_IOS_APP_ID',
  );

  static const String iosBundleId = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.animewitcher.app',
  );

  static const String messagingSenderId = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '861470152250',
  );

  static const String storageBucket = String.fromEnvironment(
    'ANIMEWITCHER_FIREBASE_STORAGE_BUCKET',
    defaultValue: 'animewitcher-1c66d.appspot.com',
  );

  /// OAuth web/server client used to request a Google ID token which Firebase
  /// can exchange for an AnimeWitcher session.
  static const String googleServerClientId = String.fromEnvironment(
    'ANIMEWITCHER_GOOGLE_SERVER_CLIENT_ID',
  );

  /// iOS requires an OAuth client registered for SkyStream's bundle ID.
  static const String googleIosClientId = String.fromEnvironment(
    'ANIMEWITCHER_GOOGLE_IOS_CLIENT_ID',
  );

  /// Credentials sufficient for the proven Firebase REST endpoints.
  static bool get firebaseConfigured =>
      projectId.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// Native Firebase must use an app id that belongs to the running platform.
  /// The original source only supplied an Android Firebase app registration,
  /// so Apple deliberately falls back to REST unless an iOS app id is supplied.
  static bool get nativeFirebaseConfigured {
    if (!firebaseConfigured || messagingSenderId.trim().isEmpty) return false;
    if (kIsWeb) return appId.trim().isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS =>
        iosAppId.trim().isNotEmpty && iosAppId.contains(':ios:'),
      TargetPlatform.android || TargetPlatform.windows => appId.trim().isNotEmpty,
      TargetPlatform.linux || TargetPlatform.fuchsia => false,
    };
  }

  static String get nativeAppId {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return iosAppId.trim();
    }
    return appId.trim();
  }

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
    if (!firebaseConfigured) return false;
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
