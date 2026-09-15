# Comments Header Morph Animation Fix

## Goal

Make the iOS persistent Liquid Glass header morph smoothly between the three Anime/Character page actions and the single Comments sort action, matching the reference animation: no geometry snap before the item morph, no sort button shifting first and morphing second, and no regression to the intentional root/details hard-cut behavior.

## Root cause

`ApplePersistentGlassHeaderNativeController` currently applies both `toolbarWidthConstraint` and `toolbarTrailingConstraint` inside `UIView.performWithoutAnimation` before calling `UIToolbar.setItems(..., animated: true)`. Comments also uses a trailing inset of 8 pt while Anime/Character use 34 pt. That makes the native toolbar jump to the destination geometry before UIKit starts morphing the bar button items.

## Implementation plan

1. Add a native regression test that defines the toolbar transition contract: structural action changes that are allowed to morph must animate geometry together with the item change; hard-cut/nonanimated transitions must not.
2. Run the iOS test and confirm the new regression test fails before production code is changed.
3. Introduce a small, testable toolbar transition policy/helper in `ios/Runner/AppDelegate.swift` that decides when width/trailing geometry should animate.
4. Refactor `ApplePersistentGlassHeaderNativeController.apply` / `applyToolbar` so target width and trailing inset are applied in one animation transaction with `UIToolbar.setItems`, using `.beginFromCurrentState`, `.curveEaseInOut`, and `.allowUserInteraction` for interruption-safe push/pop gestures.
5. Keep initial state, ordinary same-shape refreshes, and `hardCutToolbar` transitions nonanimated so Root <-> Anime Details remains unchanged.
6. Verify both directions conceptually and by tests: Anime/Character -> Comments (3 -> 1) and Comments -> Anime/Character (1 -> 3).
7. Run RunnerTests and relevant Flutter/static CI, inspect the PR diff, and only then mark the PR ready.

## Files

- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/RunnerTests/RunnerTests.swift`
- Add: `docs/plans/2026-09-13-comments-header-morph-animation.md`

## Acceptance criteria

- The single sort action does not jump horizontally before morphing on pop.
- Opening Comments does not instantly collapse the toolbar before the native item transition.
- Width, trailing position, and toolbar item morph begin together.
- Interactive/reversed transitions continue from the current visual state instead of restarting from a snapped layout.
- Root/details intentional hard cuts remain hard cuts.
- Native regression tests and repository CI pass.
