# AnimeWitcher Project Cleanup Design

**Date:** 2026-09-26  
**Branch:** `refactor/project-cleanup-2026-09-26`  
**Base:** `feat/manga-manhwa@f792a6ddd5b95d3ce48946b55105f67f35aafb68`

## Intent

Perform a repository-wide cleanup and simplification pass without changing user-visible behavior. The corrected baseline is the current `feat/manga-manhwa` line so cleanup must preserve the newer interface/features that were absent from stale `main`. Delete code and repository artifacts only when non-use is demonstrated, simplify logic only when behavior remains equivalent, and improve naming/structure where it reduces comprehension cost.

## Success criteria

- No intentional feature or API behavior changes.
- No weakening of download reliability, playback behavior, manga reader behavior, account sync, platform integrations, or error handling.
- Dead code, stale compatibility paths, duplicate repository artifacts, and unused dependencies are removed when verified.
- Complex logic is simplified only after its callers, tests, and historical/platform constraints are understood.
- Existing public/internal interfaces remain stable unless an interface is provably unused.
- Generated files and vendored third-party source are not manually reformatted or rewritten as cleanup.
- Every production-code refactor is covered by existing tests or a focused regression/contract test before the change.
- CI remains green throughout the cleanup branch.

## Repository baseline

The original audit was performed on stale `main@0ec75a8` and is archived at `archive/project-cleanup-old-main-2026-09-27@8f0c1fb`. Task 1 must refresh repository metrics from the corrected base `feat/manga-manhwa@f792a6d`; old file counts and cleanup proofs are historical evidence only, not authority for deletion on this branch.

## Scope

### First-party Dart/Flutter
Audit all `lib/**` source for:
- unused files, imports, declarations, parameters, fields, providers, flags, and compatibility paths;
- duplicate helpers and repeated conditionals;
- wrappers that only delegate;
- single-use abstractions that add indirection without value;
- deep nesting and long functions where guard clauses or focused helpers improve readability;
- obsolete comments, terminology, and migration logic;
- duplicated formatting/parsing/normalization logic;
- avoidable state and lifecycle complexity.

### Tests
Audit `test/**` for:
- tests that cover removed behavior or legacy architecture;
- duplicated test helpers;
- stale source-string guards that no longer protect real contracts;
- fixtures/utilities that are no longer referenced.

Do not reduce meaningful coverage merely to shrink the suite.

### Platform/native
Audit Android, iOS, macOS, Windows, Linux, `native/**`, and FFI glue for:
- tracked backup/temp files;
- obsolete migration/patch scripts;
- duplicate configuration;
- dead bridge methods;
- stale compatibility logic.

Platform code is higher risk: remove only with direct reference/configuration evidence and relevant build/typecheck coverage.

### Dependencies
For each direct dependency in `pubspec.yaml`:
- prove runtime/build usage;
- distinguish implementation-only Flutter plugins from packages that require Dart imports;
- remove a dependency only if no source, build hook, plugin registration, or platform requirement depends on it;
- regenerate lock/plugin metadata rather than editing generated registration files manually.

### Vendored/generated code
- Generated localization, generated Riverpod/router output, Flutter generated plugin registrants, and upstream third-party headers are excluded from style cleanup.
- `packages/video_view` is treated as a vendored subproject. App-level cleanup must not delete its example/upstream assets unless they are explicitly proven unnecessary for maintaining the fork.

## Change strategy

1. Repository hygiene and fully proven dead artifacts.
2. Dependency audit.
3. Low-risk utilities/models/providers.
4. Storage/network/account layers.
5. Feature presentation/state layers.
6. Download subsystem.
7. Player subsystem.
8. Manga reader subsystem.
9. Native/platform integrations.
10. Vendored package review.
11. Final repo-wide analyzer/test/build review.

Each batch should be small enough to review independently. Prefer deletion over replacement, existing helpers over new abstractions, standard/native APIs over custom code, and explicit readable control flow over compressed cleverness.

## Verification

Primary gates:
- `flutter analyze --no-fatal-warnings --no-fatal-infos`
- `flutter test test/core/services/download_v2`
- `flutter test --dart-define=ANIMEWITCHER_FIREBASE_API_KEY=test-api-key`
- iOS debug build without codesigning through the existing CI job
- native Swift logger typecheck through the existing CI job

Subsystem-specific tests must run before the full suite when a batch touches that subsystem.

## Non-goals

- New features.
- UI redesigns.
- Changing download/player architecture solely to reduce line count.
- Replacing working dependencies with alternatives without a demonstrated benefit.
- Reformatting generated/vendor code.
- Large speculative abstractions or broad file moves with no measurable readability gain.
