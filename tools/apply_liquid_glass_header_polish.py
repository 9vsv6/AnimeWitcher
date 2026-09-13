from pathlib import Path


def replace_exact(path: str, old: str, new: str, count: int = 1) -> None:
    file = Path(path)
    text = file.read_text()
    actual = text.count(old)
    if actual != count:
        raise SystemExit(f"{path}: expected {count} matches, found {actual}")
    file.write_text(text.replace(old, new, count))


replace_exact(
    "lib/features/comments/presentation/animewitcher_my_comments_screen.dart",
    """              onBack: () => Navigator.of(context).maybePop(),
              trailingButtons: usePersistentGlass
""",
    """              onBack: () => Navigator.of(context).maybePop(),
              toolbarTrailingInset: usePersistentGlass
                  ? AnimeWitcherCommentSortControl.persistentTrailingInset
                  : null,
              trailingButtons: usePersistentGlass
""",
)
replace_exact(
    "lib/features/comments/presentation/animewitcher_my_comments_screen.dart",
    """                padding: EdgeInsets.only(
                  right: usePersistentGlass && isArabic ? 92 : 0,
                  left: usePersistentGlass && !isArabic ? 92 : 0,
                ),
""",
    """                padding: EdgeInsets.only(
                  right: usePersistentGlass && isArabic
                      ? AnimeWitcherCommentSortControl.persistentTitleClearance
                      : 0,
                  left: usePersistentGlass && !isArabic
                      ? AnimeWitcherCommentSortControl.persistentTitleClearance
                      : 0,
                ),
""",
)

replace_exact(
    "lib/shared/widgets/apple_liquid_glass.dart",
    "      'instantVisibilityChanges': involvesInstantRoute,\n",
    "      'instantVisibilityChanges': false,\n",
)

replace_exact(
    "ios/Runner/AppDelegate.swift",
    """  private var toolbarVisible = false
  private var backVisible = false

  init(
""",
    """  private var toolbarVisible = false
  private var backVisible = false
  private let liquidGlassHiddenScale: CGFloat = 0.88
  private let liquidGlassShowDuration: TimeInterval = 0.34
  private let liquidGlassHideDuration: TimeInterval = 0.20

  init(
""",
)

replace_exact(
    "ios/Runner/AppDelegate.swift",
    """  private func setBackVisible(_ visible: Bool, animated: Bool = true) {
    guard backVisible != visible else { return }
    backVisible = visible
    backButton.layer.removeAllAnimations()
    if visible {
      backButton.isHidden = false
      backButton.alpha = 1
      return
    }
    if !animated {
      UIView.performWithoutAnimation {
        backButton.alpha = 0
        backButton.isHidden = true
      }
      return
    }
    UIView.animate(
      withDuration: 0.035,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]
    ) { [weak self] in
      self?.backButton.alpha = 0
    } completion: { [weak self] _ in
      guard let self, !self.backVisible else { return }
      self.backButton.isHidden = true
    }
  }

  private func setToolbarVisible(_ visible: Bool, animated: Bool = true) {
    guard toolbarVisible != visible else { return }
    toolbarVisible = visible
    // Stop intercepting touches as soon as hiding starts, including its fade.
    toolbar.isUserInteractionEnabled = visible
    toolbar.layer.removeAllAnimations()
    if visible {
      toolbar.isHidden = false
      toolbar.alpha = 1
      return
    }
    if !animated {
      UIView.performWithoutAnimation {
        toolbar.alpha = 0
        toolbar.isHidden = true
      }
      return
    }
    UIView.animate(
      withDuration: 0.035,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]
    ) { [weak self] in
      self?.toolbar.alpha = 0
    } completion: { [weak self] _ in
      guard let self, !self.toolbarVisible else { return }
      self.toolbar.isHidden = true
    }
  }
""",
    """  private func animateLiquidGlassVisibility(
    _ view: UIView,
    visible: Bool,
    animated: Bool,
    completion: (() -> Void)? = nil
  ) {
    view.layer.removeAllAnimations()
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    let liquidGlassHiddenTransform = reduceMotion
      ? CGAffineTransform.identity
      : CGAffineTransform(
          scaleX: liquidGlassHiddenScale,
          y: liquidGlassHiddenScale
        )

    if visible {
      let beginsHidden = view.isHidden || view.alpha < 0.01
      view.isHidden = false
      if !animated {
        UIView.performWithoutAnimation {
          view.alpha = 1
          view.transform = .identity
        }
        completion?()
        return
      }

      if beginsHidden {
        view.alpha = 0
        view.transform = liquidGlassHiddenTransform
      }

      if reduceMotion {
        UIView.animate(
          withDuration: 0.18,
          delay: 0,
          options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]
        ) {
          view.alpha = 1
          view.transform = .identity
        } completion: { _ in
          completion?()
        }
        return
      }

      UIView.animate(
        withDuration: liquidGlassShowDuration,
        delay: 0,
        usingSpringWithDamping: 0.82,
        initialSpringVelocity: 0.24,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        view.alpha = 1
        view.transform = .identity
      } completion: { _ in
        completion?()
      }
      return
    }

    if !animated {
      UIView.performWithoutAnimation {
        view.alpha = 0
        view.transform = liquidGlassHiddenTransform
      }
      completion?()
      return
    }

    UIView.animate(
      withDuration: reduceMotion ? 0.15 : liquidGlassHideDuration,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
    ) {
      view.alpha = 0
      view.transform = liquidGlassHiddenTransform
    } completion: { _ in
      completion?()
    }
  }

  private func setBackVisible(_ visible: Bool, animated: Bool = true) {
    guard backVisible != visible else { return }
    backVisible = visible
    backButton.isUserInteractionEnabled = visible
    animateLiquidGlassVisibility(
      backButton,
      visible: visible,
      animated: animated
    ) { [weak self] in
      guard let self, !self.backVisible else { return }
      self.backButton.isHidden = true
    }
  }

  private func setToolbarVisible(_ visible: Bool, animated: Bool = true) {
    guard toolbarVisible != visible else { return }
    toolbarVisible = visible
    // Stop intercepting touches as soon as hiding starts, including its fade.
    toolbar.isUserInteractionEnabled = visible
    animateLiquidGlassVisibility(
      toolbar,
      visible: visible,
      animated: animated
    ) { [weak self] in
      guard let self, !self.toolbarVisible else { return }
      self.toolbar.isHidden = true
    }
  }
""",
)

replace_exact(
    "ios/Runner/AppDelegate.swift",
    """  private func desiredToolbarHostWidth(actions: [[String: Any]]) -> CGFloat {
    // The toolbar is a root-level native overlay above Flutter. Its transparent
""",
    """  private func isCompactSingleAction(_ actions: [[String: Any]]) -> Bool {
    actions.count == 1 && actionTitle(actions[0]) == nil
  }

  private func desiredToolbarHostWidth(actions: [[String: Any]]) -> CGFloat {
    if isCompactSingleAction(actions) { return 46 }
    // The toolbar is a root-level native overlay above Flutter. Its transparent
""",
)

replace_exact(
    "ios/Runner/AppDelegate.swift",
    """    guard !actionItems.isEmpty else { return [] }
    return [UIBarButtonItem(systemItem: .flexibleSpace)] + actionItems
  }

  private func applyToolbar(actions: [[String: Any]], animated: Bool) {
""",
    """    currentActionItems = actionItems
    guard !actionItems.isEmpty else { return [] }
    if isCompactSingleAction(actions) {
      return actionItems
    }
    return [UIBarButtonItem(systemItem: .flexibleSpace)] + actionItems
  }

  private func applyToolbar(actions: [[String: Any]], animated: Bool) {
""",
)

replace_exact(
    "ios/Runner/AppDelegate.swift",
    """    let items = makeActionItems(actions: actions)
    currentActionItems = items.dropFirst().map { $0 }
    currentActionKinds = actionKinds
    let shouldAnimate = didApplyInitialToolbarState && animated
""",
    """    let items = makeActionItems(actions: actions)
    currentActionKinds = actionKinds
    let shouldAnimate = didApplyInitialToolbarState && animated
""",
)
