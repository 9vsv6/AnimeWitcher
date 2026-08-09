import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/account/animewitcher_account_models.dart';

void main() {
  test('account session survives secure-storage serialization', () {
    final original = AnimeWitcherSession(
      uid: 'uid-1',
      idToken: 'id-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.utc(2026, 8, 9, 12),
      signInMethod: AnimeWitcherSignInMethod.google,
      email: 'user@example.com',
      displayName: 'Test User',
      photoUrl: 'https://example.com/photo.jpg',
    );

    final restored = AnimeWitcherSession.fromJson(original.toJson());

    expect(restored.uid, original.uid);
    expect(restored.idToken, original.idToken);
    expect(restored.refreshToken, original.refreshToken);
    expect(restored.expiresAt, original.expiresAt);
    expect(restored.signInMethod, AnimeWitcherSignInMethod.google);
    expect(restored.email, original.email);
    expect(restored.displayName, original.displayName);
    expect(restored.photoUrl, original.photoUrl);
  });
}
