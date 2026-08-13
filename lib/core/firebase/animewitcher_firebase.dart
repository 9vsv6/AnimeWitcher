import 'package:firebase_core/firebase_core.dart';

import '../account/animewitcher_account_config.dart';

/// Initializes the Firebase project used by the original AnimeWitcher app.
///
/// The API key stays supplied through the existing build-time secret. The
/// remaining identifiers are project/app metadata recovered from the original
/// AnimeWitcher client and can be overridden with dart-defines when needed.
class AnimeWitcherFirebase {
  const AnimeWitcherFirebase._();

  static Future<bool> initialize() async {
    if (Firebase.apps.isNotEmpty) return true;
    if (!AnimeWitcherAccountConfig.firebaseConfigured) return false;

    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: AnimeWitcherAccountConfig.apiKey,
        appId: AnimeWitcherAccountConfig.appId,
        messagingSenderId: AnimeWitcherAccountConfig.messagingSenderId,
        projectId: AnimeWitcherAccountConfig.projectId,
        storageBucket: AnimeWitcherAccountConfig.storageBucket,
        authDomain: '${AnimeWitcherAccountConfig.projectId}.firebaseapp.com',
        iosClientId: AnimeWitcherAccountConfig.googleIosClientId.trim().isEmpty
            ? null
            : AnimeWitcherAccountConfig.googleIosClientId,
      ),
    );
    return true;
  }
}
