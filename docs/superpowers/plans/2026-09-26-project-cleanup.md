# AnimeWitcher Project Cleanup Implementation Plan

> **For agentic workers:** Use Superpowers executing-plans/TDD plus Ponytail. Work task-by-task and keep this checklist current.

**Goal:** Audit, clean, and simplify the full AnimeWitcher repository while preserving existing behavior and the latest UI/feature baseline.

**Corrected baseline (2026-09-27):** `refactor/project-cleanup-2026-09-26` was originally created from stale `main@0ec75a8`. Preview run `36313153525` proved that this omitted the newer interface/features already merged into `feat/manga-manhwa`. The branch was therefore re-based by ref reset onto `feat/manga-manhwa@f792a6d`. The completed stale-baseline cleanup is preserved at `archive/project-cleanup-old-main-2026-09-27@8f0c1fb` for reference only. **Do not blindly cherry-pick the archived cleanup; re-prove each deletion/simplification against this baseline.**

**Spec:** `docs/superpowers/specs/2026-09-26-project-cleanup-design.md`

## Global Constraints

- Preserve current user-visible behavior, especially the UI/features present on `feat/manga-manhwa`.
- Do not weaken download recovery/background ownership, player lifecycle, manga reader behavior, account/storage compatibility, or platform-specific safeguards.
- Prove dead code before deletion.
- Prefer deletion/direct code over new abstraction.
- Do not manually clean generated or upstream/vendor code.
- Keep batches reviewable; run focused tests/analyzer after each batch and fix introduced failures before continuing.
- Long-running CI must not block independent audit work.
- Do not merge PR #253.

### Task 1 evidence — corrected baseline

- PR #253 currently targets `feat/manga-manhwa@f792a6ddd5b95d3ce48946b55105f67f35aafb68` from `refactor/project-cleanup-2026-09-26`.
- Corrected-branch repository map at `ece762ec3fc5f7611f6660e723333359fa8f404d`: 1,065 tracked files, including 357 `lib/**/*.dart` files and 306 `test/**/*.dart` files.
- Platform/native map: Android 46 files, iOS 49, macOS 30, Windows 19, `native/**` 13.
- Vendored boundary: `packages/video_view/**` contains 158 tracked files and stays outside ordinary app cleanup unless fork-local debris is proven safe to remove.
- Generated scope includes generated localization/output files and `*.g.dart`/other generated Dart; generated/plugin registration output is regenerated through project tooling rather than hand-cleaned.
- The historical Flutter Checks run `36314643667` is not evidence for the corrected baseline: its checkout log merged head `ece762e` into stale `main@0ec75a8` immediately before the PR base retarget. A fresh head commit is required to obtain CI on the corrected PR merge ref.

### Task 1: Re-establish corrected baseline and repository map
- [x] Record corrected base commit/branch and refresh tree/file/subsystem metrics.
- [x] Classify first-party, generated, vendored, and platform/native scopes.
- [ ] Capture a green CI baseline on the corrected branch.
- [ ] Verify a Build Preview from this branch contains the latest `feat/manga-manhwa` UI baseline.

### Task 2: Revalidate repository debris
- [ ] Scan tracked backup/temp/exact-duplicate artifacts.
- [ ] Delete only candidates proven unused or byte-identical.
- [ ] Verify build/config references and CI.

### Task 3: Revalidate direct dependencies
- [ ] Check every direct dependency for Dart/build-hook/plugin/native use.
- [ ] Remove only genuinely unused dependencies.
- [ ] Regenerate lock/plugin metadata rather than editing generated registrants manually.
- [ ] Run analyzer/tests/platform gates.

### Task 4: Clean low-risk core utilities/models/providers/theme
- [ ] Find unused declarations and duplicated helpers on the corrected baseline.
- [ ] Simplify equivalent guard/normalization/formatting logic.
- [ ] Use focused contract tests before behavior-adjacent changes.
- [ ] Run matching core tests and analyzer.

### Task 5: Clean storage/network/account
- [ ] Trace callers and persistence/migration contracts first.
- [ ] Remove dead wrappers/adapters/repeated parsing only with proof.
- [ ] Preserve ordering, conflict protection, retry and migration semantics.
- [ ] Run account/storage/network tests.

### Task 6: Clean extension/provider data layer
- [ ] Map provider entry points/helper ownership.
- [ ] Remove unused extraction/mapping helpers and duplicate normalization.
- [ ] Keep APIs stable unless proven unused.
- [ ] Run provider contract tests.

### Task 7: Clean feature UI/state outside player/download
- [ ] Audit home/search/details/library/settings/comments/characters/more/news.
- [ ] Preserve the latest UI behavior from `feat/manga-manhwa`.
- [ ] Remove dead branches/flags/providers and duplicated presentation helpers only with proof.
- [ ] Avoid helper extraction that merely splits cohesive declarative widget trees.
- [ ] Run feature-local widget/provider tests.

### Task 8: Clean manga reader subsystem
- [ ] Re-establish AnimeWitcher glue vs Mangayomi-derived boundary.
- [ ] Remove unused reader glue/settings/cache/navigation only after caller/state trace.
- [ ] Preserve paging/preload/offline identity semantics.
- [ ] Run all manga reader/download tests.

### Task 9: Clean Download Manager V2
- [ ] Rebuild caller/state-machine map on corrected baseline.
- [ ] Separate required persisted compatibility from stale V1-era API/terminology.
- [ ] Preserve durable/live bytes, generation fencing, retries, pause/resume, background/native ownership.
- [ ] Run focused V2 tests after every batch and full download tests.

### Task 10: Clean player subsystem
- [ ] Map controller lifecycle, ownership, stream selection, side panels and platform hooks.
- [ ] Remove dead callbacks/flags/API only after repo-wide reference proof.
- [ ] Keep exit/dispose/background-audio protections and recovery semantics unchanged.
- [ ] Prefer deleting unreachable state over splitting cohesive state-machine methods.
- [ ] Run player/navigation/lifecycle tests.

### Task 11: Clean platform/native integrations
- [ ] Audit Android/iOS/macOS/Windows/Linux/native/FFI scripts, build settings and bridge symbols.
- [ ] Prove symbol/config references before deletion.
- [ ] Keep iOS download/background and Anime4K semantics unchanged.
- [ ] Run configured native/platform gates.

### Task 12: Review vendored video_view
- [ ] Separate AnimeWitcher-required fork changes from upstream/example content.
- [ ] Remove only clearly unneeded fork-local debris.
- [ ] Verify supported platform registration/build wiring.

### Task 13: Test-suite cleanup
- [ ] Delete tests only with intentionally removed production behavior and preserved contracts.
- [ ] Consolidate duplicated test helpers where clearer.
- [ ] Replace stale source-text guards only when equivalent behavioral/integration coverage exists.
- [ ] Run the complete suite.

### Task 14: Final verification
- [ ] Format changed first-party Dart files.
- [ ] Run analyzer and inspect remaining diagnostics.
- [ ] Run focused V2 tests.
- [ ] Run complete Flutter suite with required Firebase test define.
- [ ] Run iOS debug build and native logger typecheck.
- [ ] Run a fresh Build Preview and verify it is based on the corrected UI baseline.
- [ ] Review complete diff for behavior/UI regression and generated churn.
- [ ] Perform final Ponytail audit and record intentional retained complexity.
- [ ] Leave PR #253 draft/unmerged unless the user explicitly asks to merge it.
