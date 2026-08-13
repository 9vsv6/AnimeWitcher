import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;

import 'animewitcher_account_config.dart';
import 'animewitcher_account_models.dart';
import '../firebase/animewitcher_firebase.dart';

class FirebaseAuthRestClient {
  FirebaseAuthRestClient({Dio? dio})
    : _dio = dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              headers: const <String, String>{
                'Accept': 'application/json',
              },
            ),
          );

  final Dio _dio;

  bool get _nativeReady => AnimeWitcherFirebase.isInitialized;

  String get _identityBase =>
      'https://identitytoolkit.googleapis.com/v1';
  String get _tokenBase => 'https://securetoken.googleapis.com/v1';

  Future<AnimeWitcherSession> signInWithEmail({
    required String email,
    required String password,
    bool requireVerified = true,
  }) async {
    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    if (!_nativeReady) {
      return _signInWithEmailRest(
        email: email,
        password: password,
        requireVerified: requireVerified,
      );
    }
    try {
      final credential = await _sdk.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AnimeWitcherAccountException(
          'account-not-found',
          'The account could not be found.',
        );
      }
      await user.reload();
      final refreshed = _sdk.currentUser ?? user;
      if (requireVerified && !refreshed.emailVerified) {
        throw const AnimeWitcherAccountException(
          'email-not-verified',
          'Email address has not been verified yet.',
        );
      }
      return _sessionFromSdkUser(
        refreshed,
        AnimeWitcherSignInMethod.email,
        forceRefresh: true,
      );
    } on fa.FirebaseAuthException catch (error) {
      throw _authException(error);
    }
  }

  Future<AnimeWitcherSession> createEmailAccount({
    required String email,
    required String password,
  }) async {
    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    if (!_nativeReady) {
      return _createEmailAccountRest(email: email, password: password);
    }
    try {
      final credential = await _sdk.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AnimeWitcherAccountException(
          'account-not-found',
          'Firebase did not create a user account.',
        );
      }
      return _sessionFromSdkUser(
        user,
        AnimeWitcherSignInMethod.email,
        forceRefresh: true,
      );
    } on fa.FirebaseAuthException catch (error) {
      throw _authException(error);
    }
  }

  Future<AnimeWitcherSession> signInWithGoogleIdToken(String idToken) async {
    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    if (!_nativeReady) return _signInWithGoogleIdTokenRest(idToken);
    try {
      final credential = fa.GoogleAuthProvider.credential(idToken: idToken);
      final result = await _sdk.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        throw const AnimeWitcherAccountException(
          'account-not-found',
          'Firebase did not return a Google account.',
        );
      }
      return _sessionFromSdkUser(
        user,
        AnimeWitcherSignInMethod.google,
        forceRefresh: true,
      );
    } on fa.FirebaseAuthException catch (error) {
      throw _authException(error);
    }
  }

  Future<void> sendEmailVerification(String idToken) async {
    final user = _nativeReady ? _sdk.currentUser : null;
    if (user != null) {
      try {
        await user.sendEmailVerification();
        return;
      } on fa.FirebaseAuthException catch (error) {
        throw _authException(error);
      }
    }

    await _identityPost('/accounts:sendOobCode', <String, dynamic>{
      'requestType': 'VERIFY_EMAIL',
      'idToken': idToken,
    });
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    if (!_nativeReady) {
      await _identityPost('/accounts:sendOobCode', <String, dynamic>{
        'requestType': 'PASSWORD_RESET',
        'email': email.trim(),
      });
      return;
    }
    try {
      await _sdk.sendPasswordResetEmail(email: email.trim());
    } on fa.FirebaseAuthException catch (error) {
      throw _authException(error);
    }
  }

  Future<void> deleteAccount(String idToken) async {
    final user = _nativeReady ? _sdk.currentUser : null;
    if (user != null) {
      try {
        await user.delete();
        return;
      } on fa.FirebaseAuthException catch (error) {
        throw _authException(error);
      }
    }

    await _identityPost('/accounts:delete', <String, dynamic>{
      'idToken': idToken,
    });
  }

  Future<Map<String, dynamic>> lookup(String idToken) async {
    final user = _nativeReady ? _sdk.currentUser : null;
    if (user != null) {
      try {
        await user.reload();
        final refreshed = _sdk.currentUser ?? user;
        return _sdkUserMap(refreshed);
      } on fa.FirebaseAuthException catch (error) {
        throw _authException(error);
      }
    }

    final payload = await _identityPost(
      '/accounts:lookup',
      <String, dynamic>{'idToken': idToken},
    );
    final users = payload['users'];
    if (users is! List || users.isEmpty || users.first is! Map) {
      throw const AnimeWitcherAccountException(
        'account-not-found',
        'The account could not be found.',
      );
    }
    return Map<String, dynamic>.from(users.first as Map);
  }

  Future<AnimeWitcherSession> refresh(
    AnimeWitcherSession previous,
  ) async {
    final user = _nativeReady ? _sdk.currentUser : null;
    if (user != null && user.uid == previous.uid) {
      try {
        return _sessionFromSdkUser(
          user,
          previous.signInMethod,
          forceRefresh: true,
          fallbackRefreshToken: previous.refreshToken,
        );
      } on fa.FirebaseAuthException catch (error) {
        throw _authException(error);
      }
    }
    // No native FirebaseAuth session means this user signed in before the SDK
    // migration. Keep the existing secure-token REST refresh below until they
    // next sign in, after which FirebaseAuth persistence owns the session.

    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    try {
      final response = await _dio.post<dynamic>(
        '$_tokenBase/token',
        queryParameters: <String, dynamic>{
          'key': AnimeWitcherAccountConfig.apiKey,
        },
        data: <String, dynamic>{
          'grant_type': 'refresh_token',
          'refresh_token': previous.refreshToken,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final payload = _asMap(response.data);
      final refreshed = previous.copyWith(
        uid: (payload['user_id'] ?? previous.uid).toString(),
        idToken: (payload['id_token'] ?? '').toString(),
        refreshToken:
            (payload['refresh_token'] ?? previous.refreshToken).toString(),
        expiresAt: DateTime.now().add(
          Duration(seconds: _intValue(payload['expires_in'], 3600)),
        ),
      );
      if (refreshed.idToken.isEmpty) {
        throw const AnimeWitcherAccountException(
          'invalid-session',
          'The saved account session is invalid.',
        );
      }
      return refreshed;
    } on DioException catch (error) {
      throw _firebaseException(error);
    }
  }

  Future<void> signOut() async {
    if (_nativeReady) await _sdk.signOut();
  }

  fa.FirebaseAuth get _sdk => fa.FirebaseAuth.instance;

  Future<AnimeWitcherSession> _signInWithEmailRest({
    required String email,
    required String password,
    required bool requireVerified,
  }) async {
    final payload = await _identityPost(
      '/accounts:signInWithPassword',
      <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    final session = _sessionFromIdentityPayload(
      payload,
      AnimeWitcherSignInMethod.email,
    );
    final user = await lookup(session.idToken);
    if (requireVerified && user['emailVerified'] != true) {
      throw const AnimeWitcherAccountException(
        'email-not-verified',
        'Email address has not been verified yet.',
      );
    }
    return _mergeUser(session, user);
  }

  Future<AnimeWitcherSession> _createEmailAccountRest({
    required String email,
    required String password,
  }) async {
    final payload = await _identityPost(
      '/accounts:signUp',
      <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    return _sessionFromIdentityPayload(
      payload,
      AnimeWitcherSignInMethod.email,
    );
  }

  Future<AnimeWitcherSession> _signInWithGoogleIdTokenRest(String idToken) async {
    final postBody = Uri(
      queryParameters: <String, String>{
        'id_token': idToken,
        'providerId': 'google.com',
      },
    ).query;
    final payload = await _identityPost(
      '/accounts:signInWithIdp',
      <String, dynamic>{
        'postBody': postBody,
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      },
    );
    return _sessionFromIdentityPayload(
      payload,
      AnimeWitcherSignInMethod.google,
    );
  }

  Future<AnimeWitcherSession> _sessionFromSdkUser(
    fa.User user,
    AnimeWitcherSignInMethod method, {
    bool forceRefresh = false,
    String? fallbackRefreshToken,
  }) async {
    final tokenResult = await user.getIdTokenResult(forceRefresh);
    final token = tokenResult.token ?? await user.getIdToken(forceRefresh) ?? '';
    if (token.isEmpty) {
      throw const AnimeWitcherAccountException(
        'invalid-session',
        'Firebase did not return a usable ID token.',
      );
    }
    return AnimeWitcherSession(
      uid: user.uid,
      idToken: token,
      refreshToken: user.refreshToken ?? fallbackRefreshToken ?? '',
      expiresAt: tokenResult.expirationTime ??
          DateTime.now().add(const Duration(minutes: 55)),
      signInMethod: method,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }

  Map<String, dynamic> _sdkUserMap(fa.User user) => <String, dynamic>{
        'localId': user.uid,
        'email': user.email,
        'emailVerified': user.emailVerified,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
      };

  AnimeWitcherAccountException _authException(fa.FirebaseAuthException error) {
    final code = switch (error.code) {
      'user-not-found' => 'account-not-found',
      'invalid-credential' || 'wrong-password' || 'invalid-email' =>
        'invalid-credentials',
      'email-already-in-use' || 'account-exists-with-different-credential' =>
        'email-already-in-use',
      'weak-password' => 'weak-password',
      'requires-recent-login' => 'requires-recent-login',
      'user-disabled' => 'account-disabled',
      'too-many-requests' => 'too-many-requests',
      'network-request-failed' => 'network-error',
      _ => error.code,
    };
    return AnimeWitcherAccountException(
      code,
      error.message ?? 'Firebase Authentication request failed.',
    );
  }

  Future<Map<String, dynamic>> _identityPost(
    String path,
    Map<String, dynamic> data,
  ) async {
    if (!AnimeWitcherAccountConfig.firebaseConfigured) {
      throw const AnimeWitcherAccountException(
        'not-configured',
        'AnimeWitcher account services are not configured.',
      );
    }
    try {
      final response = await _dio.post<dynamic>(
        '$_identityBase$path',
        queryParameters: <String, dynamic>{
          'key': AnimeWitcherAccountConfig.apiKey,
        },
        data: data,
        options: Options(contentType: Headers.jsonContentType),
      );
      return _asMap(response.data);
    } on DioException catch (error) {
      throw _firebaseException(error);
    }
  }

  AnimeWitcherSession _sessionFromIdentityPayload(
    Map<String, dynamic> payload,
    AnimeWitcherSignInMethod method,
  ) {
    final session = AnimeWitcherSession(
      uid: (payload['localId'] ?? '').toString(),
      idToken: (payload['idToken'] ?? '').toString(),
      refreshToken: (payload['refreshToken'] ?? '').toString(),
      expiresAt: DateTime.now().add(
        Duration(seconds: _intValue(payload['expiresIn'], 3600)),
      ),
      signInMethod: method,
      email: _optionalString(payload['email']),
      displayName: _optionalString(payload['displayName']),
      photoUrl: _optionalString(payload['photoUrl']),
    );
    if (session.uid.isEmpty ||
        session.idToken.isEmpty ||
        session.refreshToken.isEmpty) {
      throw const AnimeWitcherAccountException(
        'invalid-auth-response',
        'The account server returned an incomplete session.',
      );
    }
    return session;
  }

  AnimeWitcherSession _mergeUser(
    AnimeWitcherSession session,
    Map<String, dynamic> user,
  ) {
    return session.copyWith(
      email: _optionalString(user['email']),
      displayName: _optionalString(user['displayName']),
      photoUrl: _optionalString(user['photoUrl']),
    );
  }
}

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

String? _optionalString(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

int _intValue(dynamic raw, int fallback) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

AnimeWitcherAccountException _firebaseException(DioException error) {
  final response = _asMap(error.response?.data);
  final nested = _asMap(response['error']);
  final raw = (nested['message'] ?? error.message ?? 'NETWORK_ERROR')
      .toString();
  final code = raw.split(':').first.trim().toUpperCase();
  return switch (code) {
    'EMAIL_EXISTS' => const AnimeWitcherAccountException(
      'email-already-in-use',
      'An account already exists for this email address.',
    ),
    'EMAIL_NOT_FOUND' ||
    'INVALID_PASSWORD' ||
    'INVALID_LOGIN_CREDENTIALS' => const AnimeWitcherAccountException(
      'invalid-credentials',
      'The email address or password is incorrect.',
    ),
    'USER_DISABLED' => const AnimeWitcherAccountException(
      'user-disabled',
      'This account has been disabled.',
    ),
    'WEAK_PASSWORD' => const AnimeWitcherAccountException(
      'weak-password',
      'The password must contain at least six characters.',
    ),
    'INVALID_EMAIL' || 'MISSING_EMAIL' => const AnimeWitcherAccountException(
      'invalid-email',
      'Enter a valid email address.',
    ),
    'TOO_MANY_ATTEMPTS_TRY_LATER' => const AnimeWitcherAccountException(
      'too-many-attempts',
      'Too many attempts. Please try again later.',
    ),
    'TOKEN_EXPIRED' ||
    'INVALID_ID_TOKEN' ||
    'INVALID_REFRESH_TOKEN' ||
    'USER_NOT_FOUND' => const AnimeWitcherAccountException(
      'invalid-session',
      'The account session has expired. Please sign in again.',
    ),
    _ => AnimeWitcherAccountException(
      'network-or-server-error',
      raw.isEmpty ? 'Could not contact the account server.' : raw,
    ),
  };
}
