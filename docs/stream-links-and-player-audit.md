# Deep review — stream link acquisition & the player

Scope: how SkyStream obtains video stream URLs
(`animewitcher_native_provider.dart`, `playback_launcher.dart`,
`source_picker.dart`) and how the player consumes them
(`player_controller.dart`, `local_proxy_service.dart`, mpv / VideoView
backends).

Method: architecture walkthrough plus git-history analysis of the relevant
files (`84e3fde` reconnect/watchdog, `8fe4d27` chosen-source handoff,
`d355065` GF extraction fix, `9e8490d` picker persistence). Findings are
ordered by severity; two ship as code in this branch (§3), the rest are
concrete, small-diff follow-ups.

---

## 1. How links are obtained today (as-is)

1. Details screen → `PlaybackLauncher` resolves a `SkyStreamProvider` and
   opens the source picker.
2. The picked `StreamResult` travels through `PlayerRouteExtra.selectedSource`.
   Entries flagged `requiresResolution` keep their intermediate provider URL
   and resolve inside the player; direct entries load immediately without
   being replaced by saved-source or automatic-quality preferences.
3. Inside the player, `_resolveStreamUrl(stream)` turns a server page into a
   media URL. For AnimeWitcher this fetches the server page and cuts the URL
   out between two word markers: `GF` uses a generic marker path with one
   escaped-page retry (`d355065`), `ST` has dedicated handling, and the GF
   result deliberately drops the page `Referer` because forwarded headers
   were breaking otherwise-valid links.
4. The resolved URL goes through live-state detection and backend selection
   (`_canUseVideoViewForStream`), headers are applied, and streams ride the
   local proxy when needed (`seekable=1, icy=0, reconnect*, cache-pause`).

Resilience already shipped in the player (keep all of it): escalating buffer
watchdog 12/25/45 s, seamless 3-attempt reconnect with exponential backoff,
connectivity-restore kick, backgrounded-error suppression, source-session IDs
guarding async races.

---

## 2. Findings

### A — Stream link acquisition

**A1 · High — parallel error paths spend the reconnect budget twice.**
The VideoView error listener and the mpv error listener each increment
`_midPlaybackRetryCount` when an error surfaces, and the reconnect scheduler
increments again on failure. When both backends report the same underlying
failure (common right after a CDN drop), the 3-attempt budget burns down at
twice the intended rate and users see premature source switching. Fix:
increment in exactly one place — inside `_triggerMidPlaybackReconnect` — and
treat both listeners as triggers only.

**A2 · Medium-High — connectivity flaps bypass the retry cap.**
`_setupConnectivityListener` kicks `_triggerMidPlaybackReconnect()` on every
restore event without checking `_isReconnectingCurrentStream` or the remaining
budget (it cancels the pending backoff timer but does not gate). An
oscillating connection re-arms the ladder indefinitely. Fix: route the kick
through the same gate as the error paths
(`if (_isReconnectingCurrentStream || !_policy.canReconnect(n)) return;`).

**A3 · Medium — permanent failures are retried like transient ones.**
Dead server pages (HTTP 401/403/404) consume the full 2/4/8 s ladder — about
14 s of guaranteed dead air — before failover. Fix: classify resolver errors;
skip straight to `retryNextStream` on definitive statuses and keep the ladder
for timeouts, 5xx, and socket errors.

**A4 · Medium — marker extraction is stringly-typed and untested.**
GF extraction depends on exact marker words plus an escape-normalization
pass; any upstream HTML/JSON serialization change silently kills playback.
This branch ships pure helpers + fixture tests (§3.1) so the logic can be
adopted into the provider and covered without hitting live pages.

**A5 · Low-Medium — stale signed URLs after long pauses.**
The reconnect ladder handles expiry reactively, but nothing refreshes a token
proactively when resuming after a long pause. Optional: if the pause exceeded
a TTL threshold, re-resolve once on play instead of waiting for the 403.

**A6 · Info — header propagation must stay centralized.**
The GF `Referer` fix shows provider headers flow into both playback and
downloads. Any future per-server header decision belongs in the single
header-builder so the two consumers never drift apart.

### B — The player

**B1 · Medium — the buffer watchdog keeps ticking after its terminal stage.**
`_checkBufferWatchdog` advances `_bufferRecoveryStage` to 3 at 45 s and hands
off to the next source, but nothing cancels the periodic timer or marks the
window consumed. Until buffering clears, the callback keeps firing every 3 s,
and the freshly-selected next source inherits a hot watchdog. Fix: cancel the
timer (or reset `_bufferingSince`) when reporting the terminal stage —
trivial with §3.2.

**B2 · Low — recovery thresholds are magic numbers.**
12/25/45 s and 2/4/8 s live inline in a ~3500-line controller. §3.2
centralizes them behind named constants with a worst-case-ladder helper.

**B3 · Medium — forcing the highest-bandwidth HLS variant hurts slow links.**
mpv is pinned to the top variant "so it never downgrades". On constrained
connections that guarantees rebuffering loops, which the watchdog then
"fixes" by reopening sources — churn a mid-tier variant would avoid.
Suggestion: keep the max-variant pin as the default but honor a data-saver
toggle that lets mpv auto-select.

**B4 · Low — downloads toolbar is untranslated and bulk delete is
unconfirmed.**
`_DownloadsToolbar` labels ('Download queue', 'Pause all', 'Delete selected',
'$selectedCount selected') are hardcoded English despite the bilingual
`appText` system, and the trash button deletes the selection instantly. Use
`appText(...)` everywhere and confirm destructive bulk deletes.

**B5 · Verify — `AppLifecycleState.inactive` treated as backgrounded.**
The lifecycle handler now suppresses errors on `inactive` (right for the iOS
app switcher), but `inactive` also fires for transient system UI such as the
control center and permission dialogs. If pause/resume flickers show up
there, split real backgrounding (`hidden`/`paused`) from `inactive`.

---

## 3. Shipped in this branch (additive — zero behavior change)

1. **`lib/core/extensions/providers/server_extraction_utils.dart`** (+ tests):
   dependency-free versions of the GF marker extraction
   (`extractBetweenMarkers`, `extractServerUrlWithRetry`,
   `normalizePageEscapes`, `looksLikeStreamUrl`), ready for adoption by
   `animewitcher_native_provider.dart` (addresses A4).
2. **`lib/features/player/presentation/playback_recovery_policy.dart`**
   (+ tests): named thresholds for the watchdog stages and the reconnect
   ladder, a `watchdogStage()` classifier, and a worst-case-ladder helper
   that makes the B1 fix a one-liner for the caller (addresses A1/A2/B2).

## 4. Recommended follow-ups (need full-file edits, kept out of this PR)

- Adopt §3 helpers inside the provider/controller (small, reviewable diffs).
- Per-server fixture tests for extraction (GF/ST/others).
- Error classification for the reconnect ladder (A3).
- Data-saver / adaptive HLS switch (B3).
- i18n + confirmation for download bulk actions (B4).
