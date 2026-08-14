import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../account/animewitcher_account_config.dart';

/// Initializes the Firebase project used by the original AnimeWitcher app.
///
/// The recovered AnimeWitcher Firebase app registration is Android-specific.
/// iOS is intentionally REST-only: it never initializes or uses the native
/// Firebase SDK. Other supported platforms may still use the native SDK when
/// their platform configuration is valid, with REST remaining as fallback.
class AnimeWitcherFirebase {
  const AnimeWitcherFirebase._();

  static bool _initialized = false;

  static bool get isInitialized {
    // iOS is deliberately REST-only. Keep this false even if another Firebase
    // integration initializes a default app elsewhere in the process.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return false;
    return _initialized || Firebase.apps.isNotEmpty;
  }

  static Future<bool> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return false;
    if (isInitialized) {
      _initialized = true;
      return true;
    }
    if (!AnimeWitcherAccountConfig.nativeFirebaseConfigured) return false;

    final nativeAppId = AnimeWitcherAccountConfig.nativeAppId;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        !nativeAppId.contains(':ios:')) {
      // Never hand an Android GOOGLE_APP_ID to FirebaseCore on Apple. Native
      // Firebase exceptions can terminate the process before Flutter's first
      // frame, so this validation must happen before Firebase.initializeApp().
      return false;
    }

    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AnimeWitcherAccountConfig.apiKey,
          appId: nativeAppId,
          messagingSenderId: AnimeWitcherAccountConfig.messagingSenderId,
          projectId: AnimeWitcherAccountConfig.projectId,
          storageBucket: AnimeWitcherAccountConfig.storageBucket,
          authDomain: '${AnimeWitcherAccountConfig.projectId}.firebaseapp.com',
          iosBundleId: !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
              ? AnimeWitcherAccountConfig.iosBundleId
              : null,
          iosClientId: !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.macOS &&
                  AnimeWitcherAccountConfig.googleIosClientId.trim().isNotEmpty
              ? AnimeWitcherAccountConfig.googleIosClientId
              : null,
        ),
      );
      _initialized = true;
      return true;
    } on Object catch (error) {
      // Dart-level configuration failures must never prevent SkyStream from
      // launching. Callers transparently use the established REST path instead.
      debugPrint('AnimeWitcher Firebase SDK unavailable: $error');
      return false;
    }
  }
}
