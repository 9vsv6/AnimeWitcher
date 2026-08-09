import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/account/animewitcher_sync_conflict.dart';

void main() {
  group('resolveAnimeWitcherSyncConflict', () {
    test('newer remote value replaces stale local value', () {
      expect(
        resolveAnimeWitcherSyncConflict(
          remoteExists: true,
          localUpdatedAt: 100,
          remoteUpdatedAt: 200,
          syncedAccountUid: 'user-a',
          localSyncedAt: 100,
          currentAccountUid: 'user-a',
        ),
        AnimeWitcherSyncResolution.applyRemote,
      );
    });

    test('unsynchronized local edit is uploaded', () {
      expect(
        resolveAnimeWitcherSyncConflict(
          remoteExists: true,
          localUpdatedAt: 300,
          remoteUpdatedAt: 200,
          syncedAccountUid: 'user-a',
          localSyncedAt: 100,
          currentAccountUid: 'user-a',
        ),
        AnimeWitcherSyncResolution.uploadLocal,
      );
    });

    test('acknowledged local value cannot overwrite another device', () {
      expect(
        resolveAnimeWitcherSyncConflict(
          remoteExists: true,
          // Simulate a client clock that is far ahead of Firestore's clock.
          localUpdatedAt: 900,
          remoteUpdatedAt: 200,
          syncedAccountUid: 'user-a',
          localSyncedAt: 900,
          currentAccountUid: 'user-a',
        ),
        AnimeWitcherSyncResolution.applyRemote,
      );
    });

    test('remote deletion removes unchanged synchronized local value', () {
      expect(
        resolveAnimeWitcherSyncConflict(
          remoteExists: false,
          localUpdatedAt: 100,
          remoteUpdatedAt: 0,
          syncedAccountUid: 'user-a',
          localSyncedAt: 100,
          currentAccountUid: 'user-a',
        ),
        AnimeWitcherSyncResolution.deleteLocal,
      );
    });

    test('data from another account is removed instead of uploaded', () {
      expect(
        resolveAnimeWitcherSyncConflict(
          remoteExists: false,
          localUpdatedAt: 100,
          remoteUpdatedAt: 0,
          syncedAccountUid: 'user-a',
          localSyncedAt: 100,
          currentAccountUid: 'user-b',
        ),
        AnimeWitcherSyncResolution.deleteLocal,
      );
    });
  });
}
