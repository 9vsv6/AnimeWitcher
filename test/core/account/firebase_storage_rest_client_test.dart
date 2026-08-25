import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/account/animewitcher_account_models.dart';
import 'package:animewitcher/core/account/firebase_storage_rest_client.dart';

void main() {
  test('profile image upload uses Firebase Storage multipart REST', () async {
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
              data: const <String, dynamic>{'downloadTokens': 'download-token'},
            ),
          );
        },
      ),
    );
    final client = FirebaseStorageRestClient(
      dio: dio,
      storageBucket: 'test-bucket.appspot.com',
    );

    final url = await client.uploadAccountImage(
      idToken: 'id-token',
      documentId: 'profile-1',
      kind: AnimeWitcherProfileImageKind.avatar,
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

    expect(
      captured?.path,
      'https://firebasestorage.googleapis.com/v0/b/'
      'test-bucket.appspot.com/o',
    );
    expect(
      captured?.queryParameters['name'],
      startsWith('users_ver2/profile-1/profile_image_'),
    );
    expect(captured?.queryParameters['name'], endsWith('.jpg'));
    expect(captured?.headers['Authorization'], 'Firebase id-token');
    expect(captured?.headers['X-Goog-Upload-Protocol'], 'multipart');
    expect(captured?.contentType, startsWith('multipart/related; boundary='));
    expect(captured?.data, isA<Uint8List>());
    expect(
      url,
      allOf(
        startsWith(
          'https://firebasestorage.googleapis.com/v0/b/'
          'test-bucket.appspot.com/o/'
          'users_ver2%2Fprofile-1%2Fprofile_image_',
        ),
        endsWith('.jpg?alt=media&token=download-token'),
      ),
    );
  });
}
