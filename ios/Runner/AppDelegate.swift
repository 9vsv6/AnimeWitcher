import Flutter
import UIKit
import UserNotifications

private let liquidGlassTabBarViewType =
  "dev.akash.skystream/liquid_glass_tab_bar"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var downloadContinuedProcessingChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
          print("[AppDelegate] Notification permission granted")
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // This is required to show notifications while the app is in the foreground
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let applicationRegistrar = engineBridge.applicationRegistrar
    applicationRegistrar.register(
      LiquidGlassTabBarFactory(messenger: applicationRegistrar.messenger()),
      withId: liquidGlassTabBarViewType
    )

    let channel = FlutterMethodChannel(
      name: "dev.akash.skystream/download_continued_processing",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
#if os(iOS)
      guard #available(iOS 26.0, *) else {
        result(false)
        return
      }

      guard let arguments = call.arguments as? [String: Any],
            let taskId = arguments["taskId"] as? String else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "taskId is required",
            details: nil
          )
        )
        return
      }

      Task { @MainActor in
        do {
          let manager = DownloadContinuedProcessingManager.shared

          switch call.method {
          case "start":
            guard let displayName = arguments["displayName"] as? String else {
              result(
                FlutterError(
                  code: "INVALID_ARGUMENTS",
                  message: "displayName is required",
                  details: nil
                )
              )
              return
            }

            let progress =
              (arguments["progress"] as? NSNumber)?.doubleValue ?? 0.0
            let totalBytes =
              (arguments["totalBytes"] as? NSNumber)?.int64Value ?? -1

            let identifier = try manager.start(
              taskId: taskId,
              displayName: displayName,
              progress: progress,
              totalBytes: totalBytes
            )
            if let identifier {
              result(identifier)
            } else {
              result(false)
            }

          case "update":
            let progress =
              (arguments["progress"] as? NSNumber)?.doubleValue ?? 0.0
            let totalBytes =
              (arguments["totalBytes"] as? NSNumber)?.int64Value ?? -1
            manager.update(
              taskId: taskId,
              progress: progress,
              totalBytes: totalBytes
            )
            result(true)

          case "finish":
            let success = arguments["success"] as? Bool ?? false
            let status = arguments["status"] as? String ?? "failed"
            manager.finish(
              taskId: taskId,
              success: success,
              status: status
            )
            result(true)

          case "stop":
            manager.stop(taskId: taskId)
            result(true)

          default:
            result(FlutterMethodNotImplemented)
          }
        } catch {
          result(
            FlutterError(
              code: "CONTINUED_PROCESSING_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
#else
      result(false)
#endif
    }

#if os(iOS)
    if #available(iOS 26.0, *) {
      DownloadContinuedProcessingManager.shared.cancellationHandler = {
        [weak channel] taskId in
        channel?.invokeMethod(
          "cancel",
          arguments: ["taskId": taskId]
        )
      }
    }
#endif

    downloadContinuedProcessingChannel = channel
  }
}

private final class LiquidGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class LiquidGlassTabBarPlatformView: NSObject, FlutterPlatformView {
  private let tabBarView: LiquidGlassTabBarView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    tabBarView = LiquidGlassTabBarView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(liquidGlassTabBarViewType)_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    tabBarView.apply(arguments: arguments as? [String: Any] ?? [:])
    tabBarView.onSelected = { [weak self] index in
      self?.channel.invokeMethod("onTap", arguments: index)
    }

    channel.setMethodCallHandler { [weak tabBarView = self.tabBarView] call, result in
      DispatchQueue.main.async {
        guard let tabBarView = tabBarView else {
          result(false)
          return
        }

        switch call.method {
        case "setSelectedIndex":
          guard let index = (call.arguments as? NSNumber)?.intValue else {
            result(
              FlutterError(
                code: "INVALID_INDEX",
                message: "A selected tab index is required.",
                details: nil
              )
            )
            return
          }
          tabBarView.setSelectedIndex(index, notifyFlutter: false)
          result(true)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  func view() -> UIView {
    tabBarView
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}

private final class LiquidGlassTabBarView: UIView, UIGestureRecognizerDelegate {
  private static let defaultLabels = [
    "Home",
    "Search",
    "Explore",
    "Library",
    "Settings",
  ]

  private static let symbols = [
    "house",
    "magnifyingglass",
    "safari",
    "play.rectangle.on.rectangle",
    "gearshape",
  ]

  private static let selectedSymbols = [
    "house.fill",
    "magnifyingglass",
    "safari.fill",
    "play.rectangle.on.rectangle.fill",
    "gearshape.fill",
  ]

  private let effectView: UIVisualEffectView
  private let selectionIndicatorView = UIView()
  private let stackView = UIStackView()
  private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
  private var buttons: [UIButton] = []
  private var labels = LiquidGlassTabBarView.defaultLabels
  private var selectedIndex = 0
  private var dragStartIndex: Int?
  private var accentColor = UIColor.systemBlue

  var onSelected: ((Int) -> Void)?

  override init(frame: CGRect) {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      effectView = UIVisualEffectView(effect: glassEffect)
    } else {
      effectView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
      )
    }

    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false

    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.clipsToBounds = true
    if #available(iOS 26.0, *) {
      effectView.cornerConfiguration = .corners(radius: .fixed(30))
    } else {
      effectView.layer.cornerRadius = 30
      effectView.layer.cornerCurve = .continuous
    }
    addSubview(effectView)

    selectionIndicatorView.isUserInteractionEnabled = false
    selectionIndicatorView.backgroundColor = accentColor.withAlphaComponent(0.14)
    selectionIndicatorView.layer.cornerCurve = .continuous
    effectView.contentView.addSubview(selectionIndicatorView)

    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = 2
    stackView.translatesAutoresizingMaskIntoConstraints = false
    effectView.contentView.addSubview(stackView)

    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stackView.topAnchor.constraint(
        equalTo: effectView.contentView.topAnchor,
        constant: 3
      ),
      stackView.leadingAnchor.constraint(
        equalTo: effectView.contentView.leadingAnchor,
        constant: 6
      ),
      stackView.trailingAnchor.constraint(
        equalTo: effectView.contentView.trailingAnchor,
        constant: -6
      ),
      stackView.bottomAnchor.constraint(
        equalTo: effectView.contentView.bottomAnchor,
        constant: -3
      ),
    ])

    for index in LiquidGlassTabBarView.symbols.indices {
      let button = UIButton(type: .system)
      button.tag = index
      button.addTarget(
        self,
        action: #selector(didTapButton(_:)),
        for: .touchUpInside
      )
      stackView.addArrangedSubview(button)
      buttons.append(button)
    }

    let panGesture = UIPanGestureRecognizer(
      target: self,
      action: #selector(handleSelectionPan(_:))
    )
    panGesture.cancelsTouchesInView = true
    panGesture.delegate = self
    addGestureRecognizer(panGesture)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if dragStartIndex == nil {
      positionSelectionIndicator(animated: false)
    }
  }

  func apply(arguments: [String: Any]) {
    if let suppliedLabels = arguments["labels"] as? [String],
       suppliedLabels.count == buttons.count {
      labels = suppliedLabels
    }

    if let colorNumber = arguments["accentColor"] as? NSNumber {
      accentColor = UIColor(argb: colorNumber.uint32Value)
    }
    selectionIndicatorView.backgroundColor = accentColor.withAlphaComponent(0.14)

    switch arguments["brightness"] as? String {
    case "dark":
      overrideUserInterfaceStyle = .dark
    case "light":
      overrideUserInterfaceStyle = .light
    default:
      overrideUserInterfaceStyle = .unspecified
    }

    let semanticDirection: UISemanticContentAttribute =
      arguments["textDirection"] as? String == "rtl"
        ? .forceRightToLeft
        : .forceLeftToRight
    semanticContentAttribute = semanticDirection
    stackView.semanticContentAttribute = semanticDirection

    let index = (arguments["selectedIndex"] as? NSNumber)?.intValue ?? 0
    setSelectedIndex(index, notifyFlutter: false, animated: false)
  }

  func setSelectedIndex(
    _ index: Int,
    notifyFlutter: Bool,
    animated: Bool = true
  ) {
    guard !buttons.isEmpty else { return }
    let nextIndex = min(max(index, 0), buttons.count - 1)
    let changed = nextIndex != selectedIndex
    selectedIndex = nextIndex
    updateButtons()
    positionSelectionIndicator(animated: animated && changed)
    if notifyFlutter {
      onSelected?(selectedIndex)
    }
  }

  private func updateButtons() {
    for (index, button) in buttons.enumerated() {
      let isSelected = index == selectedIndex
      var configuration = UIButton.Configuration.plain()

      let symbolName = isSelected
        ? LiquidGlassTabBarView.selectedSymbols[index]
        : LiquidGlassTabBarView.symbols[index]
      let symbolConfiguration = UIImage.SymbolConfiguration(
        pointSize: 20,
        weight: isSelected ? .semibold : .regular
      )
      let symbolImage = UIImage(
        systemName: symbolName,
        withConfiguration: symbolConfiguration
      )

      configuration.image = isSelected
        ? symbolImage?.withTintColor(accentColor, renderingMode: .alwaysOriginal)
        : symbolImage
      configuration.title = labels[index]
      configuration.imagePlacement = .top
      configuration.imagePadding = 1
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 3,
        leading: 2,
        bottom: 3,
        trailing: 2
      )
      configuration.baseForegroundColor = isSelected
        ? accentColor
        : .secondaryLabel
      configuration.titleLineBreakMode = .byTruncatingTail
      configuration.titleTextAttributesTransformer =
        UIConfigurationTextAttributesTransformer { attributes in
          var updated = attributes
          updated.font = UIFont.systemFont(
            ofSize: 10,
            weight: isSelected ? .semibold : .medium
          )
          return updated
        }

      button.tintColor = isSelected ? accentColor : .secondaryLabel
      button.configuration = configuration
      button.accessibilityLabel = labels[index]
      button.accessibilityTraits = isSelected
        ? [.button, .selected]
        : [.button]
    }
  }

  private func selectionFrame(for index: Int) -> CGRect? {
    guard buttons.indices.contains(index) else { return nil }
    let frame = buttons[index].convert(
      buttons[index].bounds,
      to: effectView.contentView
    ).insetBy(dx: 1, dy: 0)
    guard frame.width > 0, frame.height > 0 else { return nil }
    return frame
  }

  private func positionSelectionIndicator(animated: Bool) {
    guard let targetFrame = selectionFrame(for: selectedIndex) else { return }

    let updates = {
      self.selectionIndicatorView.frame = targetFrame
      self.selectionIndicatorView.layer.cornerRadius = targetFrame.height / 2
    }

    if animated && !UIAccessibility.isReduceMotionEnabled {
      UIView.animate(
        withDuration: 0.22,
        delay: 0,
        usingSpringWithDamping: 0.82,
        initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .allowUserInteraction],
        animations: updates
      )
    } else {
      updates()
    }
  }

  private func indexForLocation(_ location: CGPoint) -> Int? {
    guard !buttons.isEmpty else { return nil }
    let pointInStack = stackView.convert(location, from: self)
    return buttons.enumerated().min { lhs, rhs in
      abs(lhs.element.frame.midX - pointInStack.x)
        < abs(rhs.element.frame.midX - pointInStack.x)
    }?.offset
  }

  private func previewSelection(at location: CGPoint) {
    guard let index = indexForLocation(location) else { return }

    if index != selectedIndex {
      selectedIndex = index
      updateButtons()
      selectionFeedbackGenerator.selectionChanged()
      selectionFeedbackGenerator.prepare()
    }

    guard var indicatorFrame = selectionFrame(for: index) else { return }
    let pointInContent = effectView.contentView.convert(location, from: self)
    let halfWidth = indicatorFrame.width / 2
    let minimumCenterX = stackView.frame.minX + halfWidth
    let maximumCenterX = stackView.frame.maxX - halfWidth
    let centerX = min(max(pointInContent.x, minimumCenterX), maximumCenterX)
    indicatorFrame.origin.x = centerX - halfWidth
    selectionIndicatorView.frame = indicatorFrame
    selectionIndicatorView.layer.cornerRadius = indicatorFrame.height / 2
  }

    override func gestureRecognizerShouldBegin(
    _ gestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
      return true
    }
    let velocity = panGesture.velocity(in: self)
    return abs(velocity.x) > abs(velocity.y)
  }

  @objc private func handleSelectionPan(_ gesture: UIPanGestureRecognizer) {
    let location = gesture.location(in: self)

    switch gesture.state {
    case .began:
      dragStartIndex = selectedIndex
      selectionFeedbackGenerator.prepare()
      previewSelection(at: location)

    case .changed:
      previewSelection(at: location)

    case .ended:
      previewSelection(at: location)
      let startingIndex = dragStartIndex
      dragStartIndex = nil
      positionSelectionIndicator(animated: true)
      if startingIndex != selectedIndex {
        onSelected?(selectedIndex)
      }

    case .cancelled, .failed:
      let startingIndex = dragStartIndex
      dragStartIndex = nil
      if let startingIndex {
        setSelectedIndex(
          startingIndex,
          notifyFlutter: false,
          animated: true
        )
      }

    default:
      break
    }
  }

  @objc private func didTapButton(_ sender: UIButton) {
    if sender.tag != selectedIndex {
      selectionFeedbackGenerator.prepare()
      selectionFeedbackGenerator.selectionChanged()
    }
    setSelectedIndex(sender.tag, notifyFlutter: true)
  }
}

private extension UIColor {
  convenience init(argb: UInt32) {
    let alpha = CGFloat((argb >> 24) & 0xff) / 255
    let red = CGFloat((argb >> 16) & 0xff) / 255
    let green = CGFloat((argb >> 8) & 0xff) / 255
    let blue = CGFloat(argb & 0xff) / 255
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }
}
