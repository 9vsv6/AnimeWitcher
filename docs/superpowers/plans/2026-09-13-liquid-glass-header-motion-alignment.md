# Liquid Glass Header Motion and Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the comment/review sort control geometrically mirror the back button and give persistent iOS Liquid Glass header controls a smooth, system-like show/hide animation across AnimeWitcher.

**Architecture:** Keep the route-independent persistent Liquid Glass header as the single source of truth. Fix comments/reviews by making their persistent sort affordance a compact 46pt icon control with the same 8pt edge inset as the back button and derive title clearance from that geometry. Keep existing hard-cut content replacement where Details is intentionally isolated, but make visibility itself animate centrally in the native persistent header controller so all pages using that controller inherit the same motion.

**Tech Stack:** Flutter/Dart, UIKit/Swift, GitHub Actions.

**Spec:** User-approved design from the 2026-09-13 conversation: symmetric sort/back placement, proportional title shift, and gentle Liquid Glass appearance/disappearance animation matching the supplied reference video.

## Global Constraints

- Apply comment/review alignment to comments, reviews, My Comments, and My Reviews through shared code.
- Preserve the existing route-independent persistent header architecture.
- Preserve hard-cut toolbar content boundaries where morphing was intentionally disabled; only visibility becomes animated.
- Respect iOS Reduce Motion.
- Do not regress desktop caption-button clearance for the non-iOS sort control.
- Verify with Flutter analyze/tests and PR CI before declaring the PR merge-ready.

---

### Task 1: Lock comment/review header geometry with regression tests

**Files:**
- Modify: `test/features/comments/comment_sort_caption_clearance_test.dart`
- Modify: `lib/features/comments/presentation/widgets/animewitcher_comment_sort_control.dart`
- Modify: `lib/features/comments/presentation/animewitcher_comments_screen.dart`
- Modify: `lib/features/comments/presentation/animewitcher_my_comments_screen.dart`

**Interfaces:**
- Produces: `AnimeWitcherCommentSortControl.persistentTrailingInset`, `persistentTitleClearance`, and compact persistent button geometry used by both comment screens.

- [ ] **Step 1: Write failing tests**

Add assertions that the persistent sort button is exactly 46pt wide, has no visible title, uses an 8pt trailing inset, and exposes a shared title-clearance constant smaller than the old 92pt manual offset.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/comments/comment_sort_caption_clearance_test.dart`
Expected: FAIL because the compact persistent geometry constants/behavior do not exist yet.

- [ ] **Step 3: Implement the minimal shared geometry**

Make the persistent button icon-only, set its width to 46pt, add an 8pt trailing inset constant, and replace both 92pt title offsets with one shared clearance constant. Pass the trailing inset into both persistent header registrations.

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `flutter test test/features/comments/comment_sort_caption_clearance_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `fix: align comment liquid glass header controls`

### Task 2: Add global persistent Liquid Glass visibility motion

**Files:**
- Create: `test/shared/widgets/apple_liquid_glass_motion_contract_test.dart`
- Modify: `lib/shared/widgets/apple_liquid_glass.dart`
- Modify: `ios/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: existing `instantRouteBoundary`/`hardCutToolbar` contract.
- Produces: centrally animated persistent back/toolbar visibility while preserving hard-cut toolbar content replacement.

- [ ] **Step 1: Write failing regression tests**

Add a repository-source contract test that verifies persistent visibility is not forced instant at Details boundaries, native show/hide motion uses a non-trivial spring/scale transition, Reduce Motion is honored, and the old 35ms fade is gone.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/apple_liquid_glass_motion_contract_test.dart`
Expected: FAIL against the current immediate-show/35ms-hide implementation.

- [ ] **Step 3: Implement central UIKit motion**

Keep `hardCutToolbar` for content replacement, but send animated visibility for every boundary. Replace the immediate show and 35ms fade with one shared native helper: spring fade+scale on appearance, short ease-out fade+scale on disappearance, and alpha-only motion when Reduce Motion is enabled.

- [ ] **Step 4: Run focused motion test**

Run: `flutter test test/shared/widgets/apple_liquid_glass_motion_contract_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: animate persistent liquid glass visibility`

### Task 3: Full verification and PR readiness

**Files:**
- No new production files unless verification finds a regression.

**Interfaces:**
- Produces: merge-ready PR with green required CI.

- [ ] **Step 1: Run analyzer**

Run: `flutter analyze --no-fatal-warnings --no-fatal-infos`
Expected: exit 0.

- [ ] **Step 2: Run full tests**

Run: `flutter test --dart-define=ANIMEWITCHER_FIREBASE_API_KEY=test-api-key`
Expected: 0 failures.

- [ ] **Step 3: Inspect diff against the approved requirements**

Confirm: symmetric comment sort/back geometry, proportional title clearance, shared coverage for all four comment/review screens, animated show and hide, Reduce Motion support, and hard-cut content boundaries preserved.

- [ ] **Step 4: Wait for PR CI**

Verify every required check on the PR head commit is green. If anything fails, inspect logs, fix the root cause, and repeat verification.
