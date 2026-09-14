# Download Link and Session Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the exact direct download URL with a copy button in the confirmation dialog, and restore a saved AnimeWitcher account immediately on app startup while remote verification/sync continues in the background.

**Architecture:** Keep the download change inside `DownloadLauncher` because `stream.url` is the exact URL passed to `startDownload`; render it LTR inside a visually-right copy row and copy the full untruncated value. Split account startup into a fast local secure-storage hydration phase and a network validation/sync phase; the Riverpod controller returns the cached profile first, then updates state after background verification completes.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter Clipboard API, flutter_test.

**Spec:** User-approved chat design on 2026-09-14: show `stream.url` in the marked confirmation-dialog space with a copy button on the visual right; do not make account startup look like a fresh sign-in every launch.

## Global Constraints

- The download URL displayed and copied must be the exact `stream.url` used by `startDownload`.
- URL text must render left-to-right even in the Arabic UI.
- The copy control must sit on the visual right of the URL row.
- Existing title/source/size/save-location text and Cancel/Download Now actions must keep working.
- A cached signed-in profile must become visible before Firebase lookup/profile resolution/full sync finishes.
- Remote validation must still run after startup and must still clear invalid/banned/deleted sessions.
- No credentials or tokens move out of secure storage.

---

### Task 1: Direct download URL row

**Files:**
- Modify: `lib/features/details/presentation/download_launcher.dart`
- Create: `test/features/details/presentation/download_confirmation_link_contract_test.dart`

**Interfaces:**
- Consumes: `StreamResult stream`, specifically `stream.url`.
- Produces: an LTR URL row with a visual-right `Icons.copy_rounded` button that calls `Clipboard.setData(ClipboardData(text: stream.url))` and confirms the copy with a SnackBar.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download confirmation exposes and copies the exact direct stream URL', () {
    final source = File(
      'lib/features/details/presentation/download_launcher.dart',
    ).readAsStringSync();

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains('ClipboardData(text: stream.url)'));
    expect(source, contains('Icons.copy_rounded'));
    expect(source, contains('TextDirection.ltr'));
    expect(source, contains('TextDirection.rtl'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/details/presentation/download_confirmation_link_contract_test.dart`
Expected: FAIL because the confirmation dialog currently contains no clipboard import/copy button/directional URL row.

- [ ] **Step 3: Write minimal implementation**

Add `package:flutter/services.dart`; insert a compact row between size and save-location text. Force the row to `TextDirection.rtl` so the first child copy button is on the visual right; wrap the URL text in `Directionality(textDirection: TextDirection.ltr)` with one-line ellipsis. On tap, copy `stream.url` and show localized `تم نسخ الرابط` / `Link copied` feedback.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/details/presentation/download_confirmation_link_contract_test.dart test/features/details/presentation/download_launcher_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/details/presentation/download_launcher.dart test/features/details/presentation/download_confirmation_link_contract_test.dart
git commit -m "feat(download): expose direct URL with copy action"
```

### Task 2: Fast cached account restore with background validation

**Files:**
- Modify: `lib/core/account/animewitcher_account_service.dart`
- Modify: `lib/core/account/account_providers.dart`
- Create: `test/core/account/account_startup_restore_test.dart`

**Interfaces:**
- Consumes: secure-storage values `animewitcher_account_session_v1` and `animewitcher_account_profile_v1`.
- Produces: `restoreCachedSession()` for local-only hydration, `refreshRestoredSession()` for the existing Firebase lookup/profile resolution/sync flow, while `restoreSession()` remains as a compatibility wrapper that performs both phases when callers explicitly await a full restore.

- [ ] **Step 1: Write the failing test**

Create a fake secure store containing a valid future-expiring session/profile plus a `FirebaseAuthRestClient` whose `lookup()` blocks. Override `animeWitcherAccountServiceProvider` in a `ProviderContainer`, read `animeWitcherAccountControllerProvider.future`, and require the cached signed-in profile to complete within 250 ms while `lookup()` is still blocked. Also assert lookup starts afterward so validation was deferred, not removed.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/account/account_startup_restore_test.dart`
Expected: FAIL with `TimeoutException`, because the current controller awaits `restoreSession()`, and that method waits for Firebase lookup plus profile resolution and `syncAll()` before returning.

- [ ] **Step 3: Write minimal implementation**

Move secure-session/profile decoding and last-sync loading into `restoreCachedSession()`. Move the current `_authorizedSession()` → `lookup()` → email verification → `_resolveProfile()` → `_persistSession()` → `syncAll()` section into `refreshRestoredSession()`, preserving the same invalid-session clearing and offline fallback catches. Keep `restoreSession()` as `await restoreCachedSession(); return refreshRestoredSession();`. Change `AnimeWitcherAccountController.build()` to await only `restoreCachedSession()`, publish/bump the cached signed-in state, then schedule `refreshRestoredSession()` unawaited and update the AsyncNotifier state when it finishes.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/account/account_startup_restore_test.dart test/core/account/comments_survive_a_bad_session_test.dart`
Expected: PASS; the startup future resolves from cache before lookup is released, and legacy full-restore behavior still works for direct service callers.

- [ ] **Step 5: Commit**

```bash
git add lib/core/account/animewitcher_account_service.dart lib/core/account/account_providers.dart test/core/account/account_startup_restore_test.dart
git commit -m "fix(account): restore cached session before remote sync"
```

### Task 3: Integrated verification and PR

**Files:**
- Verify all files changed by Tasks 1-2.

**Interfaces:**
- Consumes: both independently green changes.
- Produces: one reviewable PR from `feat/download-link-copy-session-restore` into `main`.

- [ ] **Step 1: Run formatter/analyzer/focused tests**

```bash
dart format lib/core/account/account_providers.dart lib/core/account/animewitcher_account_service.dart lib/features/details/presentation/download_launcher.dart test/core/account/account_startup_restore_test.dart test/features/details/presentation/download_confirmation_link_contract_test.dart
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test test/core/account/account_startup_restore_test.dart test/core/account/comments_survive_a_bad_session_test.dart test/features/details/presentation/download_confirmation_link_contract_test.dart test/features/details/presentation/download_launcher_test.dart
```

- [ ] **Step 2: Run the full test suite**

Run: `flutter test --dart-define=ANIMEWITCHER_FIREBASE_API_KEY=test-api-key`
Expected: PASS.

- [ ] **Step 3: Open the pull request**

Open a PR to `main` summarizing the direct-link UI, copy behavior, cached-first account restoration, background verification, and the RED→GREEN regression tests.