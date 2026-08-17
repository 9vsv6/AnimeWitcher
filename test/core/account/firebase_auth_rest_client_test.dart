import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/account/animewitcher_account_models.dart';
import 'package:skystream/core/account/firebase_auth_rest_client.dart';

void main() {
  test('email change uses verify-before-update request', () async {
    final dio = Dio();
    RequestOptions? captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: const <String, dynamic>{},
            ),
          );
        },
      ),
    );
    final client = FirebaseAuthRestClient(dio: dio, apiKey: 'test-key');

    await client.sendEmailChangeVerification(
      idToken: 'fresh-token',
      newEmail: ' new@example.com ',
    );

    expect(captured?.path, endsWith('/accounts:sendOobCode'));
    expect(captured?.queryParameters['key'], 'test-key');
    expect(captured?.data, <String, dynamic>{
      'requestType': 'VERIFY_AND_CHANGE_EMAIL',
      'idToken': 'fresh-token',
      'newEmail': 'new@example.com',
    });
  });

  test('Google reauthentication disables accidental account creation', () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/accounts:signInWithIdp')
                  ? const <String, dynamic>{
                      'localId': 'uid-1',
                      'idToken': 'fresh-token',
                      'refreshToken': 'fresh-refresh',
                      'expiresIn': '3600',
                    }
                  : const <String, dynamic>{
                      'users': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'localId': 'uid-1',
                          'email': 'user@example.com',
                          'providerUserInfo': <Map<String, dynamic>>[
                            <String, dynamic>{'providerId': 'google.com'},
                          ],
                        },
                      ],
                    },
            ),
          );
        },
      ),
    );
    final client = FirebaseAuthRestClient(dio: dio, apiKey: 'test-key');

    final session = await client.reauthenticateWithGoogleIdToken('google-id');

    expect(requests.first.path, endsWith('/accounts:signInWithIdp'));
    expect(requests.first.data, containsPair('autoCreate', false));
    expect(requests.first.data, containsPair('returnSecureToken', true));
    expect(session.uid, 'uid-1');
    expect(session.providerIds, <String>['google.com']);
  });

  test('password update rotates tokens and refreshes providers', () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final data = options.path.endsWith('/accounts:update')
              ? <String, dynamic>{
                  'localId': 'uid-1',
                  'idToken': 'rotated-token',
                  'refreshToken': 'rotated-refresh',
                  'expiresIn': '3600',
                  'email': 'user@example.com',
                }
              : <String, dynamic>{
                  'users': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'localId': 'uid-1',
                      'email': 'user@example.com',
                      'providerUserInfo': <Map<String, dynamic>>[
                        <String, dynamic>{'providerId': 'google.com'},
                        <String, dynamic>{'providerId': 'password'},
                      ],
                    },
                  ],
                };
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    final client = FirebaseAuthRestClient(dio: dio, apiKey: 'test-key');
    final previous = AnimeWitcherSession(
      uid: 'uid-1',
      idToken: 'old-token',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.utc(2026, 8, 17),
      signInMethod: AnimeWitcherSignInMethod.google,
      email: 'user@example.com',
      providerIds: const <String>['google.com'],
    );

    final updated = await client.updatePassword(
      previous: previous,
      newPassword: 'new-secret',
    );

    expect(requests, hasLength(2));
    expect(requests.first.path, endsWith('/accounts:update'));
    expect(requests.first.data, <String, dynamic>{
      'idToken': 'old-token',
      'password': 'new-secret',
      'returnSecureToken': true,
    });
    expect(requests.last.path, endsWith('/accounts:lookup'));
    expect(requests.last.data, <String, dynamic>{
      'idToken': 'rotated-token',
    });
    expect(updated.idToken, 'rotated-token');
    expect(updated.refreshToken, 'rotated-refresh');
    expect(updated.providerIds, containsAll(<String>['google.com', 'password']));
  });

  test('Google-only account links its first password through sign-up', () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/accounts:signUp')
                  ? const <String, dynamic>{
                      'localId': 'uid-1',
                      'idToken': 'linked-token',
                      'refreshToken': 'linked-refresh',
                      'expiresIn': '3600',
                      'email': 'user@example.com',
                    }
                  : const <String, dynamic>{
                      'users': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'localId': 'uid-1',
                          'email': 'user@example.com',
                          'providerUserInfo': <Map<String, dynamic>>[
                            <String, dynamic>{'providerId': 'google.com'},
                            <String, dynamic>{'providerId': 'password'},
                          ],
                        },
                      ],
                    },
            ),
          );
        },
      ),
    );
    final client = FirebaseAuthRestClient(dio: dio, apiKey: 'test-key');
    final previous = AnimeWitcherSession(
      uid: 'uid-1',
      idToken: 'fresh-token',
      refreshToken: 'fresh-refresh',
      expiresAt: DateTime.utc(2026, 8, 17),
      signInMethod: AnimeWitcherSignInMethod.google,
      email: 'user@example.com',
      providerIds: const <String>['google.com'],
    );

    final linked = await client.linkEmailPassword(
      previous: previous,
      email: 'user@example.com',
      newPassword: 'new-secret',
    );

    expect(requests.first.path, endsWith('/accounts:signUp'));
    expect(requests.first.data, <String, dynamic>{
      'idToken': 'fresh-token',
      'email': 'user@example.com',
      'password': 'new-secret',
      'returnSecureToken': true,
    });
    expect(linked.idToken, 'linked-token');
    expect(linked.providerIds, containsAll(<String>['google.com', 'password']));
  });
}
