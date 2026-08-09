enum AnimeWitcherSyncResolution {
  uploadLocal,
  applyRemote,
  deleteLocal,
}

/// Resolves a two-device conflict without relying on the current device clock
/// for remote writes (remote timestamps are assigned by Firestore).
///
/// A local value is uploaded only when it is newer than the remote value. If a
/// value that was previously acknowledged for this account disappears from
/// Firestore and has not changed locally since, the remote deletion wins.
AnimeWitcherSyncResolution resolveAnimeWitcherSyncConflict({
  required bool remoteExists,
  required int localUpdatedAt,
  required int remoteUpdatedAt,
  required String? syncedAccountUid,
  required int localSyncedAt,
  required String currentAccountUid,
}) {
  if (syncedAccountUid != null &&
      syncedAccountUid.isNotEmpty &&
      syncedAccountUid != currentAccountUid) {
    // Local boxes are shared by the app process. Never upload data that was
    // last acknowledged for account A into account B.
    return remoteExists
        ? AnimeWitcherSyncResolution.applyRemote
        : AnimeWitcherSyncResolution.deleteLocal;
  }

  final wasAcknowledgedByThisAccount =
      syncedAccountUid == currentAccountUid && localSyncedAt > 0;

  if (remoteExists) {
    // Once this exact local revision has been acknowledged, it is no longer a
    // pending edit. Prefer the server even when this device's clock is ahead
    // of Firestore's server timestamp; otherwise an unchanged stale value can
    // be uploaded again on every launch and undo a change from another device.
    if (wasAcknowledgedByThisAccount && localUpdatedAt <= localSyncedAt) {
      return AnimeWitcherSyncResolution.applyRemote;
    }
    return localUpdatedAt > 0 && localUpdatedAt > remoteUpdatedAt
        ? AnimeWitcherSyncResolution.uploadLocal
        : AnimeWitcherSyncResolution.applyRemote;
  }

  if (wasAcknowledgedByThisAccount && localUpdatedAt <= localSyncedAt) {
    return AnimeWitcherSyncResolution.deleteLocal;
  }
  return AnimeWitcherSyncResolution.uploadLocal;
}
