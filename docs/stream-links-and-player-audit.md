# Stream links and the player — what this branch ships

Scope: AnimeWitcher stream-URL extraction (`animewitcher_native_provider.dart`)
and mid-playback recovery (`player_controller.dart`).

The first commits on this branch were additive helpers only. The player now
**uses** those helpers, and the bugs the audit described are fixed in the
controller instead of being left as follow-ups.

## Extraction (AnimeWitcher)

- Marker cuts, unescape, and `amp;` cleanup live in
  `server_extraction_utils.dart` and are called from the provider, with tests
  against escaped fixtures (not live pages).
- GF pages that fail the generic marker-in-slice cut fall back to the plain
  word slice before giving up.
- Extracted values are rejected unless they look like `http(s)` URLs, so a
  drifted marker cannot hand HTML to the player.
- Every resolved server carries `StreamResult.refreshUrl`
  (`animewitcher-source://…`) so the player can mint a **new** signed CDN
  link without going back to the picker.
- GF still ships **without** a page `Referer`. Playback and downloads both
  take headers from that same `StreamResult`.

## Player recovery

- Mid-playback errors, connectivity restore, and foreground-return all go
  through one gate: `PlaybackRecoveryPolicy.canReconnect`. Listeners no
  longer increment the retry counter themselves.
- After a failed reconnect the in-flight flag is cleared **before** the
  backoff timer fires, so attempts 2 and 3 actually run (they previously
  no-op’d).
- HTTP 401/403/404 skip the 2 s / 4 s ladder and fail over immediately.
- The buffer watchdog cancels itself on the 45 s failover so the next
  source does not inherit a dead stage-3 timer.
- Pause longer than 10 minutes on an AnimeWitcher link re-extracts on
  play, instead of waiting for a stale-token 403.
- `AppLifecycleState.inactive` no longer pauses playback (Control Center /
  permission dialogs). Real backgrounding is `paused` / `hidden`.
- `hls-bitrate=max` stays. Auto-selecting a lower HLS variant is how some
  AnimeWitcher masters lock onto an audio-only rendition.

Downloads already use l10n + a confirm dialog; that finding was stale and
was not changed.
