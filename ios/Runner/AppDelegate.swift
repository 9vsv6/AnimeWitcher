import Flutter
import UIKit
import SwiftUI
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var downloadContinuedProcessingChannel: FlutterMethodChannel?
  private var liquidGlassPresenterChannel: FlutterMethodChannel?

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

    let messenger = engineBridge.applicationRegistrar.messenger()

    if let glassRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SkyStreamAppleLiquidGlass"
    ) {
      glassRegistrar.register(
        AppleLiquidGlassViewFactory(),
        withId: "dev.akash.skystream/liquid_glass"
      )
      glassRegistrar.register(
        AppleSearchGlassActionsViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/search_glass_actions"
      )
      glassRegistrar.register(
        AppleNativeTabBarViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/native_tab_bar"
      )
      glassRegistrar.register(
        AppleNativeGlassButtonViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/native_glass_button"
      )
      glassRegistrar.register(
        AppleNativeToolbarViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/native_toolbar"
      )
      glassRegistrar.register(
        AppleNativeSearchFieldViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/native_search_field"
      )
      glassRegistrar.register(
        AppleNativeMenuButtonViewFactory(messenger: messenger),
        withId: "dev.akash.skystream/native_menu_button"
      )
    }

    let glassPresenter = FlutterMethodChannel(
      name: "dev.akash.skystream/liquid_glass_presenter",
      binaryMessenger: messenger
    )
    glassPresenter.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        if #available(iOS 26.0, *) {
          result(true)
        } else {
          result(false)
        }

      case "showSearchSort":
        guard #available(iOS 26.0, *) else {
          result(FlutterError(
            code: "LIQUID_GLASS_UNAVAILABLE",
            message: "Native Liquid Glass requires iOS 26 or later.",
            details: nil
          ))
          return
        }
        guard let arguments = call.arguments as? [String: Any],
              let presenter = skyStreamTopViewController() else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Unable to present the native sort interface.",
            details: nil
          ))
          return
        }
        presentAppleSearchSort(from: presenter, arguments: arguments, result: result)

      case "showSearchFilters":
        guard #available(iOS 26.0, *) else {
          result(FlutterError(
            code: "LIQUID_GLASS_UNAVAILABLE",
            message: "Native Liquid Glass requires iOS 26 or later.",
            details: nil
          ))
          return
        }
        guard let arguments = call.arguments as? [String: Any],
              let presenter = skyStreamTopViewController() else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Unable to present the native filter interface.",
            details: nil
          ))
          return
        }
        presentAppleSearchFilters(from: presenter, arguments: arguments, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    liquidGlassPresenterChannel = glassPresenter

    let channel = FlutterMethodChannel(
      name: "dev.akash.skystream/download_continued_processing",
      binaryMessenger: messenger
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

private func skyStreamUIColor(_ value: Any?, fallback: UIColor = .label) -> UIColor {
  guard let number = value as? NSNumber else { return fallback }
  let argb = number.uint32Value
  let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
  let red = CGFloat((argb >> 16) & 0xFF) / 255.0
  let green = CGFloat((argb >> 8) & 0xFF) / 255.0
  let blue = CGFloat(argb & 0xFF) / 255.0
  return UIColor(red: red, green: green, blue: blue, alpha: alpha)
}

private final class AppleNativeTabBarViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleNativeTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class AppleNativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let rootView: UIView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel
  private var itemIds: [String] = []

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    rootView.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: rootView.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    apply(arguments: args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { rootView }

  private func apply(arguments: Any?) {
    guard let values = arguments as? [String: Any] else { return }
    let items = values["items"] as? [[String: Any]] ?? []
    let selectedId = values["selectedId"] as? String
    itemIds = items.compactMap { $0["id"] as? String }

    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    tabBar.items = items.map { item in
      let title = item["label"] as? String
      let symbol = item["symbol"] as? String ?? "circle"
      let selectedSymbol = item["selectedSymbol"] as? String ?? symbol
      return UITabBarItem(
        title: title,
        image: UIImage(systemName: symbol, withConfiguration: symbolConfiguration),
        selectedImage: UIImage(systemName: selectedSymbol, withConfiguration: symbolConfiguration)
      )
    }

    if let tint = values["tintColor"] {
      tabBar.tintColor = skyStreamUIColor(tint, fallback: .systemBlue)
    }
    if let selectedId,
       let index = itemIds.firstIndex(of: selectedId),
       let items = tabBar.items,
       index < items.count {
      tabBar.selectedItem = items[index]
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let items = tabBar.items,
          let index = items.firstIndex(of: item),
          index < itemIds.count else { return }
    channel.invokeMethod("selected", arguments: itemIds[index])
  }
}

private func skyStreamMenuImage(
  named name: String,
  tintColor: UIColor,
  pointSize: CGFloat = 18
) -> UIImage? {
  if name == "skystream.zyx" {
    let font = UIFont.systemFont(ofSize: 15, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: tintColor,
    ]
    let text = "ZYX" as NSString
    let measured = text.size(withAttributes: attributes)
    let size = CGSize(width: ceil(measured.width), height: ceil(max(measured.height, 18)))
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      let y = (size.height - measured.height) / 2
      text.draw(at: CGPoint(x: 0, y: y), withAttributes: attributes)
    }.withRenderingMode(.alwaysOriginal)
  }

  return UIImage(
    systemName: name,
    withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
  )?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
}

private func skyStreamConfigureGlassButton(
  _ button: UIButton,
  image: UIImage?,
  foreground: UIColor = .label
) {
  if #available(iOS 26.0, *) {
    var configuration = UIButton.Configuration.glass()
    configuration.image = image
    configuration.baseForegroundColor = foreground
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.cornerConfiguration = .capsule()
  } else if #available(iOS 15.0, *) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = image
    configuration.baseForegroundColor = foreground
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.backgroundColor = .secondarySystemBackground
  } else {
    button.setImage(image, for: .normal)
    button.tintColor = foreground
    button.backgroundColor = .secondarySystemBackground
  }
}

private final class AppleNativeGlassButtonViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleNativeGlassButtonPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class AppleNativeGlassButtonPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_glass_button/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    button.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    button.addTarget(self, action: #selector(pressed), for: .touchUpInside)
    apply(arguments: args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  private func apply(arguments: Any?) {
    guard let values = arguments as? [String: Any] else { return }
    let systemName = values["systemName"] as? String ?? "circle"
    let image = UIImage(
      systemName: systemName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
    )
    let foreground = skyStreamUIColor(values["color"], fallback: .label)
    skyStreamConfigureGlassButton(button, image: image, foreground: foreground)
    button.isEnabled = values["enabled"] as? Bool ?? true
    button.accessibilityLabel = values["accessibilityLabel"] as? String
    button.accessibilityTraits = .button
  }

  @objc private func pressed() {
    guard button.isEnabled else { return }
    channel.invokeMethod("pressed", arguments: nil)
  }
}


private final class AppleNativeSearchFieldViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleNativeSearchFieldPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class AppleNativeSearchFieldPlatformView: NSObject, FlutterPlatformView, UITextFieldDelegate {
  private let rootView: UIView
  private let effectView: UIVisualEffectView
  private let searchField = UISearchTextField(frame: .zero)
  private let channel: FlutterMethodChannel
  private var loadingIndicator: UIActivityIndicatorView?

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular)
      glass.isInteractive = true
      effectView = UIVisualEffectView(effect: glass)
    } else {
      effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    }
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_search_field/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    rootView.clipsToBounds = false

    effectView.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 26.0, *) {
      effectView.cornerConfiguration = .capsule()
    } else {
      effectView.layer.cornerRadius = 21
      effectView.layer.cornerCurve = .continuous
      effectView.clipsToBounds = true
    }
    rootView.addSubview(effectView)

    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.backgroundColor = .clear
    searchField.borderStyle = .none
    searchField.clearButtonMode = .whileEditing
    searchField.returnKeyType = .search
    searchField.autocorrectionType = .no
    searchField.autocapitalizationType = .none
    searchField.delegate = self
    searchField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

    effectView.contentView.addSubview(searchField)
    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      effectView.topAnchor.constraint(equalTo: rootView.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      searchField.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 14),
      searchField.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -12),
      searchField.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
      searchField.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
    ])

    apply(arguments: args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments)
        result(true)
      case "focus":
        self.searchField.becomeFirstResponder()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  private func apply(arguments: Any?) {
    guard let values = arguments as? [String: Any] else { return }
    let text = values["text"] as? String ?? ""
    let placeholder = values["placeholder"] as? String ?? ""
    let tint = skyStreamUIColor(values["tintColor"], fallback: .systemBlue)
    let textColor = skyStreamUIColor(values["textColor"], fallback: .label)
    let placeholderColor = skyStreamUIColor(
      values["placeholderColor"],
      fallback: .secondaryLabel
    )
    let rtl = values["rtl"] as? Bool ?? false
    let loading = values["loading"] as? Bool ?? false
    let height = (values["height"] as? NSNumber)?.doubleValue ?? 42

    if searchField.text != text { searchField.text = text }
    searchField.textColor = textColor
    searchField.tintColor = tint
    if let searchImageView = searchField.leftView as? UIImageView {
      searchImageView.tintColor = tint
    }
    searchField.attributedPlaceholder = NSAttributedString(
      string: placeholder,
      attributes: [.foregroundColor: placeholderColor]
    )
    searchField.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
    searchField.textAlignment = rtl ? .right : .left
    if #unavailable(iOS 26.0) {
      effectView.layer.cornerRadius = CGFloat(height / 2)
    }
    updateLoading(loading, tint: tint)
  }

  private func updateLoading(_ loading: Bool, tint: UIColor) {
    if loading {
      let indicator = loadingIndicator ?? UIActivityIndicatorView(style: .medium)
      indicator.color = tint
      indicator.startAnimating()
      loadingIndicator = indicator
      searchField.rightView = indicator
      searchField.rightViewMode = .always
      searchField.clearButtonMode = .never
    } else {
      loadingIndicator?.stopAnimating()
      searchField.rightView = nil
      searchField.rightViewMode = .never
      searchField.clearButtonMode = .whileEditing
    }
  }

  @objc private func textChanged() {
    channel.invokeMethod("changed", arguments: searchField.text ?? "")
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    channel.invokeMethod("submitted", arguments: textField.text ?? "")
    return true
  }
}

private final class AppleNativeToolbarViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleNativeToolbarPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class SkyStreamPassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

private final class SkyStreamPassthroughToolbar: UIToolbar {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hit = super.hitTest(point, with: event) else { return nil }

    // The persistent toolbar intentionally has a wider transparent host so a
    // long library-category item can morph into the 3-action details group
    // without recreating the platform view. Only actual controls should claim
    // touches; the empty flexible-space region must pass taps through to Flutter.
    var candidate: UIView? = hit
    while let view = candidate, view !== self {
      if view is UIControl { return hit }
      candidate = view.superview
    }
    return nil
  }
}

private final class AppleNativeToolbarPlatformView: NSObject, FlutterPlatformView {
  private let rootView: SkyStreamPassthroughView
  private let channel: FlutterMethodChannel
  private let toolbar: SkyStreamPassthroughToolbar
  private var didApplyInitialState = false
  private var currentActionItems: [UIBarButtonItem] = []
  private var currentActionKinds: [Int] = []
  private var pendingArguments: Any?
  private var pendingAnimated = false
  private var updateScheduled = false

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = SkyStreamPassthroughView(frame: frame)
    toolbar = SkyStreamPassthroughToolbar(frame: .zero)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_toolbar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    rootView.clipsToBounds = false

    // Use UIKit's real toolbar instead of drawing individual UIGlassEffect
    // droplets ourselves. On iOS 26 adjacent image bar-button items are grouped
    // by the system into one Liquid Glass capsule, and setItems(_:animated:)
    // provides the system transition when the group changes (for example,
    // details' three actions -> comments' single sort action).
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbar.isTranslucent = true
    toolbar.clipsToBounds = false
    rootView.addSubview(toolbar)
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: rootView.topAnchor),
      toolbar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])

    if #unavailable(iOS 26.0) {
      // Older iOS versions don't have the new floating toolbar treatment.
      // Keep the host visually transparent there; iOS 26 deliberately receives
      // no custom appearance so UIKit can render native Liquid Glass.
      toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
      toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
      toolbar.backgroundColor = .clear
    }

    apply(arguments: args, animated: false)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.scheduleApply(arguments: call.arguments, animated: true)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  private func scheduleApply(arguments: Any?, animated: Bool) {
    pendingArguments = arguments
    pendingAnimated = pendingAnimated || animated
    guard !updateScheduled else { return }
    updateScheduled = true

    // Flutter can publish several header states in the same frame while a route
    // is pushing and async detail state is settling. Applying each one makes
    // UIToolbar start overlapping Liquid Glass transitions. Coalesce them to the
    // latest state for this run-loop turn, then let UIKit animate only once.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.updateScheduled = false
      let arguments = self.pendingArguments
      let animated = self.pendingAnimated
      self.pendingArguments = nil
      self.pendingAnimated = false
      self.apply(arguments: arguments, animated: animated)
    }
  }

  private func makeMenu(
    actionIndex: Int,
    action: [String: Any]
  ) -> UIMenu? {
    guard #available(iOS 14.0, *) else { return nil }
    let selectedValue = action["selectedValue"] as? String
    let menuTint = skyStreamUIColor(
      action["menuTintColor"],
      fallback: skyStreamUIColor(action["color"], fallback: .label)
    )
    let rawItems = action["menuItems"] as? [[String: Any]] ?? []
    guard !rawItems.isEmpty else { return nil }

    let children: [UIAction] = rawItems.compactMap { [weak self] menuItem in
      guard let value = menuItem["value"] as? String,
            let label = menuItem["label"] as? String else { return nil }
      let isDestructive = menuItem["destructive"] as? Bool == true
      let image = (menuItem["systemImage"] as? String).flatMap { name -> UIImage? in
        guard let image = UIImage(systemName: name) else { return nil }
        return isDestructive
          ? image
          : image.withTintColor(menuTint, renderingMode: .alwaysOriginal)
      }
      var attributes: UIMenuElement.Attributes = []
      if isDestructive { attributes.insert(.destructive) }
      return UIAction(
        title: label,
        image: image,
        attributes: attributes,
        state: value == selectedValue ? .on : .off
      ) { _ in
        self?.channel.invokeMethod(
          "selected",
          arguments: ["index": actionIndex, "value": value]
        )
      }
    }
    return UIMenu(children: children)
  }

  private func actionHasMenu(_ action: [String: Any]) -> Bool {
    let menuItems = action["menuItems"] as? [[String: Any]] ?? []
    return !menuItems.isEmpty
  }

  private func actionTitle(_ action: [String: Any]) -> String? {
    guard let raw = action["title"] as? String else { return nil }
    let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
  }

  private func actionKind(_ action: [String: Any]) -> Int {
    (actionHasMenu(action) ? 1 : 0) | (actionTitle(action) != nil ? 2 : 0)
  }

  private func configureActionItem(
    _ item: UIBarButtonItem,
    actionIndex: Int,
    action: [String: Any],
    actionCount: Int
  ) {
    let systemName = action["systemName"] as? String ?? "circle"
    item.image = UIImage(
      systemName: systemName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
    )
    item.title = actionTitle(action)
    item.tag = actionIndex
    item.isEnabled = action["enabled"] as? Bool ?? true
    item.tintColor = skyStreamUIColor(action["color"], fallback: .label)
    item.accessibilityLabel = action["accessibilityLabel"] as? String
    if actionHasMenu(action), #available(iOS 14.0, *) {
      item.menu = makeMenu(actionIndex: actionIndex, action: action)
    }
    if #available(iOS 26.0, *) {
      item.sharesBackground = true
      item.hidesSharedBackground = false
      item.identifier = actionIndex == actionCount - 1
        ? "skystream.trailing.anchor"
        : "skystream.trailing.item.\(actionIndex)"
    }
  }

  private func makeActionItems(actions: [[String: Any]]) -> [UIBarButtonItem] {
    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)

    let actionItems: [UIBarButtonItem] = actions.enumerated().map { index, action in
      let systemName = action["systemName"] as? String ?? "circle"
      let image = UIImage(systemName: systemName, withConfiguration: symbolConfiguration)
      let item: UIBarButtonItem

      if #available(iOS 14.0, *), let menu = makeMenu(actionIndex: index, action: action) {
        // A UIBarButtonItem-owned UIMenu is the native tap-to-open menu path.
        // A library category can also carry a title while remaining the same
        // system toolbar item that morphs into the details action group.
        item = UIBarButtonItem(
          title: actionTitle(action),
          image: image,
          primaryAction: nil,
          menu: menu
        )
      } else {
        item = UIBarButtonItem(
          image: image,
          style: .plain,
          target: self,
          action: #selector(itemPressed(_:))
        )
      }

      configureActionItem(
        item,
        actionIndex: index,
        action: action,
        actionCount: actions.count
      )
      return item
    }

    guard !actionItems.isEmpty else { return [] }
    // A single flexible spacer keeps both the 3-item capsule and the 1-item
    // sort button pinned to the same trailing edge. The image items remain
    // adjacent, so UIKit groups them into one Liquid Glass background.
    return [UIBarButtonItem(systemItem: .flexibleSpace)] + actionItems
  }

  private func apply(arguments: Any?, animated: Bool) {
    guard let values = arguments as? [String: Any] else { return }
    let actions = values["actions"] as? [[String: Any]] ?? []
    let actionKinds = actions.map(actionKind)

    // A favorite/bookmark state change only changes an item's image/tint/menu
    // state. Replacing the entire toolbar in that case makes UIKit run its
    // setItems transition again, which causes the Liquid Glass capsule to
    // dissolve/stretch even though its geometry never changed. Keep the same
    // UIBarButtonItem instances and update them in place instead.
    if didApplyInitialState,
       currentActionItems.count == actions.count,
       currentActionKinds == actionKinds {
      UIView.performWithoutAnimation {
        for (index, action) in actions.enumerated() {
          configureActionItem(
            currentActionItems[index],
            actionIndex: index,
            action: action,
            actionCount: actions.count
          )
        }
        toolbar.layoutIfNeeded()
      }
      return
    }

    let items = makeActionItems(actions: actions)
    currentActionItems = items.dropFirst().map { $0 }
    currentActionKinds = actionKinds
    let shouldAnimate = didApplyInitialState && animated

    // Reserve setItems(animated:) for real structural transitions such as the
    // details 3-button group morphing into the single comments-sort control.
    toolbar.setItems(items, animated: shouldAnimate)
    didApplyInitialState = true
  }

  @objc private func itemPressed(_ sender: UIBarButtonItem) {
    guard sender.isEnabled else { return }
    channel.invokeMethod("pressed", arguments: sender.tag)
  }
}

private final class AppleNativeMenuButtonViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleNativeMenuButtonPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class AppleNativeMenuButtonPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_menu_button/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    button.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      button.topAnchor.constraint(equalTo: rootView.topAnchor),
      button.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    apply(arguments: args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  private func apply(arguments: Any?) {
    guard let values = arguments as? [String: Any] else { return }
    let systemName = values["systemImage"] as? String ?? "arrow.up.arrow.down"
    let tintColor = skyStreamUIColor(values["tintColor"], fallback: .label)
    let image = UIImage(
      systemName: systemName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    )?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
    let title = (values["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    skyStreamConfigureGlassButton(button, image: image, foreground: tintColor)
    button.tintColor = tintColor
    if #available(iOS 15.0, *), var configuration = button.configuration {
      configuration.title = (title?.isEmpty == false) ? title : nil
      configuration.imagePadding = (title?.isEmpty == false) ? 8 : 0
      configuration.contentInsets = (title?.isEmpty == false)
        ? NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        : .zero
      button.configuration = configuration
    } else {
      button.setTitle((title?.isEmpty == false) ? title : nil, for: .normal)
    }
    button.semanticContentAttribute = (values["isRtl"] as? Bool == true)
      ? .forceRightToLeft
      : .forceLeftToRight
    button.isEnabled = values["enabled"] as? Bool ?? true
    button.accessibilityLabel = values["accessibilityLabel"] as? String
    button.accessibilityTraits = .button

    let selectedValue = values["selectedValue"] as? String
    let items = values["items"] as? [[String: Any]] ?? []
    let actions: [UIAction] = items.compactMap { item in
      guard let value = item["value"] as? String,
            let label = item["label"] as? String else { return nil }
      let systemImage = item["systemImage"] as? String
      let isDestructive = item["destructive"] as? Bool == true
      let actionImage = systemImage.flatMap { name -> UIImage? in
        if isDestructive {
          return UIImage(systemName: name)
        }
        return skyStreamMenuImage(named: name, tintColor: tintColor)
      }
      var attributes: UIMenuElement.Attributes = []
      if isDestructive {
        attributes.insert(.destructive)
      }
      return UIAction(
        title: label,
        image: actionImage,
        attributes: attributes,
        state: value == selectedValue ? .on : .off
      ) { [weak self] _ in
        self?.channel.invokeMethod("selected", arguments: value)
      }
    }
    button.menu = UIMenu(children: actions)
    button.showsMenuAsPrimaryAction = !actions.isEmpty
    if #available(iOS 16.0, *) {
      button.preferredMenuElementOrder = .fixed
    }
  }
}

private final class AppleLiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleLiquidGlassPlatformView(frame: frame, arguments: args)
  }
}

private final class AppleLiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView

  init(frame: CGRect, arguments args: Any?) {
    let parameters = args as? [String: Any]
    let cornerRadius = (parameters?["cornerRadius"] as? NSNumber)?.doubleValue ?? 999
    let requestedStyle = parameters?["style"] as? String ?? "regular"
    let interactive = parameters?["interactive"] as? Bool ?? false

    rootView = UIView(frame: frame)
    rootView.backgroundColor = .clear
    rootView.isUserInteractionEnabled = false

    let effectView = UIVisualEffectView(frame: rootView.bounds)
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    effectView.isUserInteractionEnabled = false

    if #available(iOS 26.0, *) {
      let style: UIGlassEffect.Style = requestedStyle == "clear" ? .clear : .regular
      let glassEffect = UIGlassEffect(style: style)
      // This platform view is background-only, so don't advertise native
      // interactivity that Flutter would intercept above it.
      glassEffect.isInteractive = false
      effectView.effect = glassEffect
      effectView.cornerConfiguration = cornerRadius >= 900
        ? .capsule()
        : .corners(radius: .fixed(cornerRadius))
    } else {
      rootView.clipsToBounds = true
      rootView.layer.cornerRadius = cornerRadius
      effectView.effect = UIBlurEffect(style: .systemMaterial)
    }

    rootView.addSubview(effectView)
    super.init()
  }

  func view() -> UIView {
    rootView
  }
}



private final class AppleSearchGlassActionsViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AppleSearchGlassActionsPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

private final class AppleSearchGlassActionsPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private let sortButton = UIButton(type: .system)
  private let filterButton = UIButton(type: .system)
  private let filterBadge = UILabel()
  private var filterLoading = false
  private var filterCount = 0

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/search_glass_actions/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    configureControls(arguments: args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  private func configureControls(arguments: Any?) {
    let sortImage = UIImage(
      systemName: "arrow.up.arrow.down",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    )
    let filterImage = UIImage(
      systemName: "slider.horizontal.3",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    )
    skyStreamConfigureGlassButton(sortButton, image: sortImage)
    skyStreamConfigureGlassButton(filterButton, image: filterImage)
    filterButton.addTarget(self, action: #selector(filterPressed), for: .touchUpInside)

    filterBadge.textAlignment = .center
    filterBadge.font = .systemFont(ofSize: 9, weight: .bold)
    filterBadge.textColor = .white
    filterBadge.backgroundColor = .label
    filterBadge.layer.cornerRadius = 8
    filterBadge.clipsToBounds = true
    filterBadge.isHidden = true
    filterBadge.isAccessibilityElement = false

    let stack = UIStackView(arrangedSubviews: [sortButton, filterButton])
    stack.axis = .horizontal
    stack.spacing = 8
    stack.distribution = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: rootView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      sortButton.widthAnchor.constraint(equalTo: sortButton.heightAnchor),
      filterButton.widthAnchor.constraint(equalTo: filterButton.heightAnchor),
      sortButton.heightAnchor.constraint(equalTo: rootView.heightAnchor),
      filterButton.heightAnchor.constraint(equalTo: rootView.heightAnchor),
    ])

    filterButton.addSubview(filterBadge)
    filterBadge.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      filterBadge.topAnchor.constraint(equalTo: filterButton.topAnchor, constant: 1),
      filterBadge.trailingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: -1),
      filterBadge.heightAnchor.constraint(equalToConstant: 16),
      filterBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
    ])

    apply(arguments: arguments)
  }

  private func apply(arguments: Any?) {
    guard let values = arguments as? [String: Any] else { return }
    filterCount = (values["filterCount"] as? NSNumber)?.intValue ?? 0
    filterLoading = values["filterLoading"] as? Bool ?? false
    let tintColor = skyStreamUIColor(values["tintColor"], fallback: .label)
    filterButton.isEnabled = !filterLoading
    filterBadge.text = filterCount > 99 ? "99+" : "\(filterCount)"
    filterBadge.backgroundColor = tintColor
    filterBadge.isHidden = filterCount <= 0 || filterLoading
    sortButton.accessibilityLabel = values["sortAccessibilityLabel"] as? String
    filterButton.accessibilityLabel = values["filterAccessibilityLabel"] as? String
    sortButton.tintColor = tintColor
    filterButton.tintColor = tintColor

    if #available(iOS 15.0, *) {
      if var sortConfiguration = sortButton.configuration {
        sortConfiguration.baseForegroundColor = tintColor
        sortButton.configuration = sortConfiguration
      }
      if var filterConfiguration = filterButton.configuration {
        filterConfiguration.showsActivityIndicator = filterLoading
        filterConfiguration.image = filterLoading
          ? nil
          : UIImage(
              systemName: "slider.horizontal.3",
              withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            )
        filterConfiguration.baseForegroundColor = tintColor
        filterButton.configuration = filterConfiguration
      }
    }

    let selectedValue = values["sortValue"] as? String
    let items = values["sortItems"] as? [[String: Any]] ?? []
    let actions: [UIAction] = items.compactMap { item in
      guard let value = item["value"] as? String,
            let label = item["label"] as? String else { return nil }
      let symbolName = item["systemImage"] as? String
      let image = symbolName.flatMap { name in
        skyStreamMenuImage(named: name, tintColor: tintColor)
      }
      return UIAction(
        title: label,
        image: image,
        state: value == selectedValue ? .on : .off
      ) { [weak self] _ in
        self?.channel.invokeMethod("sortSelected", arguments: value)
      }
    }
    sortButton.menu = UIMenu(children: actions)
    sortButton.showsMenuAsPrimaryAction = !actions.isEmpty
    if #available(iOS 16.0, *) {
      sortButton.preferredMenuElementOrder = .fixed
    }
  }

  @objc private func filterPressed() {
    guard !filterLoading else { return }
    channel.invokeMethod("filterPressed", arguments: nil)
  }
}

private func skyStreamTopViewController() -> UIViewController? {
  let scene = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .first { $0.activationState == .foregroundActive }
  let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    ?? scene?.windows.first?.rootViewController

  func top(_ controller: UIViewController?) -> UIViewController? {
    guard let controller else { return nil }
    if let presented = controller.presentedViewController { return top(presented) }
    if let navigation = controller as? UINavigationController { return top(navigation.visibleViewController) }
    if let tab = controller as? UITabBarController { return top(tab.selectedViewController) }
    return controller
  }
  return top(root)
}

@available(iOS 26.0, *)
private struct AppleSearchSortItem: Identifiable {
  let id: String
  let label: String
}

@available(iOS 26.0, *)
private struct AppleSearchSortOverlay: View {
  let items: [AppleSearchSortItem]
  let isArabic: Bool
  let tintColor: Color
  let onCancel: () -> Void
  let onApply: (String) -> Void
  @State private var selected: String

  init(
    items: [AppleSearchSortItem],
    initialValue: String,
    isArabic: Bool,
    tintColor: Color,
    onCancel: @escaping () -> Void,
    onApply: @escaping (String) -> Void
  ) {
    self.items = items
    self.isArabic = isArabic
    self.tintColor = tintColor
    self.onCancel = onCancel
    self.onApply = onApply
    let defaultValue = items.first?.id ?? ""
    _selected = State(initialValue: items.contains(where: { $0.id == initialValue }) ? initialValue : defaultValue)
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.16).ignoresSafeArea()
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.tint)
          Text(isArabic ? "الترتيب حسب" : "Sort by")
            .font(.title2.weight(.bold))
          Spacer()
          Button(action: onCancel) {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)

        Divider()

        ScrollView {
          VStack(spacing: 4) {
            ForEach(items) { item in
              Button {
                selected = item.id
              } label: {
                HStack(spacing: 14) {
                  Text(item.label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Spacer()
                  Image(systemName: selected == item.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected == item.id ? tintColor : Color.secondary)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 8)
        }
        .frame(maxHeight: 390)

        Divider()

        HStack(spacing: 12) {
          Button(isArabic ? "إلغاء" : "Cancel", action: onCancel)
            .buttonStyle(.plain)
          Spacer()
          Button(isArabic ? "تطبيق" : "Apply") {
            onApply(selected)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
        .padding(16)
      }
      .frame(maxWidth: 520)
      .glassEffect(.regular, in: .rect(cornerRadius: 30))
      .padding(.horizontal, 18)
    }
    .tint(tintColor)
    .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
  }
}

@available(iOS 26.0, *)
private enum AppleSearchFilterTab: String, CaseIterable, Identifiable {
  case genres, year, age, type, status
  var id: String { rawValue }
}

private func skyStreamStrings(_ value: Any?) -> [String] {
  if let strings = value as? [String] { return strings }
  if let values = value as? [Any] { return values.compactMap { $0 as? String } }
  return []
}

@available(iOS 26.0, *)
private struct AppleSearchFilterOverlay: View {
  let statuses: [String]
  let types: [String]
  let ageRatings: [String]
  let years: [String]
  let seasons: [String]
  let genres: [String]
  let isArabic: Bool
  let tintColor: Color
  let onCancel: () -> Void
  let onApply: ([String: Any]) -> Void

  @State private var tab: AppleSearchFilterTab = .genres
  @State private var selectedStatuses: Set<String>
  @State private var selectedTypes: Set<String>
  @State private var selectedAgeRatings: Set<String>
  @State private var selectedYears: Set<String>
  @State private var selectedSeasons: Set<String>
  @State private var selectedGenres: Set<String>

  init(
    options: [String: Any],
    initialValue: [String: Any],
    isArabic: Bool,
    tintColor: Color,
    onCancel: @escaping () -> Void,
    onApply: @escaping ([String: Any]) -> Void
  ) {
    statuses = skyStreamStrings(options["statuses"])
    types = skyStreamStrings(options["types"])
    ageRatings = skyStreamStrings(options["ageRatings"])
    years = skyStreamStrings(options["years"])
    seasons = skyStreamStrings(options["seasons"])
    genres = skyStreamStrings(options["genres"])
    self.isArabic = isArabic
    self.tintColor = tintColor
    self.onCancel = onCancel
    self.onApply = onApply
    _selectedStatuses = State(initialValue: Set(skyStreamStrings(initialValue["statuses"])))
    _selectedTypes = State(initialValue: Set(skyStreamStrings(initialValue["types"])))
    _selectedAgeRatings = State(initialValue: Set(skyStreamStrings(initialValue["ageRatings"])))
    _selectedYears = State(initialValue: Set(skyStreamStrings(initialValue["years"])))
    _selectedSeasons = State(initialValue: Set(skyStreamStrings(initialValue["seasons"])))
    _selectedGenres = State(initialValue: Set(skyStreamStrings(initialValue["genres"])))
  }

  private var seasonRequiresYear: Bool {
    !selectedSeasons.isEmpty && selectedYears.isEmpty
  }

  private var selectedCount: Int {
    selectedStatuses.count + selectedTypes.count + selectedAgeRatings.count +
      selectedYears.count + selectedSeasons.count + selectedGenres.count
  }

  private func tabLabel(_ value: AppleSearchFilterTab) -> String {
    switch value {
    case .genres: return isArabic ? "التصنيفات" : "Genres"
    case .year: return isArabic ? "السنة" : "Year"
    case .age: return isArabic ? "العمر" : "Age"
    case .type: return isArabic ? "النوع" : "Type"
    case .status: return isArabic ? "الحالة" : "Status"
    }
  }

  private func tabIcon(_ value: AppleSearchFilterTab) -> String {
    switch value {
    case .genres: return "tag"
    case .year: return "calendar"
    case .age: return "shield"
    case .type: return "square.grid.2x2"
    case .status: return "dot.radiowaves.left.and.right"
    }
  }

  private func clearAll() {
    selectedStatuses.removeAll()
    selectedTypes.removeAll()
    selectedAgeRatings.removeAll()
    selectedYears.removeAll()
    selectedSeasons.removeAll()
    selectedGenres.removeAll()
  }

  private func payload() -> [String: Any] {
    [
      "statuses": Array(selectedStatuses),
      "types": Array(selectedTypes),
      "ageRatings": Array(selectedAgeRatings),
      "years": Array(selectedYears),
      "seasons": Array(selectedSeasons),
      "genres": Array(selectedGenres),
    ]
  }

  private func toggled(_ set: Set<String>, value: String) -> Set<String> {
    var copy = set
    if copy.contains(value) { copy.remove(value) } else { copy.insert(value) }
    return copy
  }

  @ViewBuilder
  private func choiceGrid(
    values: [String],
    selected: Set<String>,
    columns: Int,
    onToggle: @escaping (String) -> Void
  ) -> some View {
    let grid = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
    LazyVGrid(columns: grid, spacing: 10) {
      ForEach(values, id: \.self) { value in
        let isSelected = selected.contains(value)
        Button {
          onToggle(value)
        } label: {
          Text(value)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 8)
            .background(
              isSelected ? tintColor : Color.primary.opacity(0.07),
              in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private var seasonYearGrid: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !seasons.isEmpty {
        choiceGrid(
          values: seasons,
          selected: selectedSeasons,
          columns: 4,
          onToggle: { value in
            if selectedSeasons.contains(value) {
              selectedSeasons.removeAll()
            } else {
              selectedSeasons = [value]
            }
          }
        )
      }
      choiceGrid(
        values: years,
        selected: selectedYears,
        columns: 4,
        onToggle: { value in selectedYears = toggled(selectedYears, value: value) }
      )
    }
  }

  @ViewBuilder
  private var currentFilterContent: some View {
    switch tab {
    case .genres:
      choiceGrid(values: genres, selected: selectedGenres, columns: 3) {
        selectedGenres = toggled(selectedGenres, value: $0)
      }
    case .year:
      seasonYearGrid
    case .age:
      choiceGrid(values: ageRatings, selected: selectedAgeRatings, columns: 2) {
        selectedAgeRatings = toggled(selectedAgeRatings, value: $0)
      }
    case .type:
      choiceGrid(values: types, selected: selectedTypes, columns: 2) {
        selectedTypes = toggled(selectedTypes, value: $0)
      }
    case .status:
      choiceGrid(values: statuses, selected: selectedStatuses, columns: 2) {
        selectedStatuses = toggled(selectedStatuses, value: $0)
      }
    }
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black.opacity(0.16).ignoresSafeArea()
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(.tint)
            Text(isArabic ? "فلاتر البحث" : "Search filters")
              .font(.title2.weight(.bold))
            if selectedCount > 0 {
              Text("\(selectedCount)")
                .font(.caption.bold())
                .foregroundStyle(.tint)
            }
            Spacer()
            Button(action: onCancel) {
              Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 15)

          Divider()

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(AppleSearchFilterTab.allCases) { item in
                Button {
                  tab = item
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: tabIcon(item))
                    Text(tabLabel(item))
                      .font(.subheadline.weight(.semibold))
                  }
                  .foregroundStyle(tab == item ? tintColor : Color.secondary)
                  .padding(.horizontal, 10)
                  .frame(height: 44)
                  .overlay(alignment: .bottom) {
                    if tab == item {
                      Capsule().fill(tintColor).frame(height: 3)
                    }
                  }
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 14)
          }

          Divider()

          ScrollView {
            currentFilterContent
              .padding(16)
          }
          .frame(maxHeight: .infinity)

          Divider()

          VStack(spacing: 10) {
            if seasonRequiresYear {
              Label(
                isArabic ? "اختر سنة مع الموسم" : "Choose a year with the season",
                systemImage: "info.circle"
              )
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tint)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
              Button {
                clearAll()
              } label: {
                Label(isArabic ? "مسح الكل" : "Clear all", systemImage: "arrow.counterclockwise")
              }
              .buttonStyle(.plain)
              .disabled(selectedCount == 0)

              Spacer()

              Button(isArabic ? "تطبيق" : "Apply") {
                onApply(payload())
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(seasonRequiresYear)
            }
          }
          .padding(16)
        }
        .frame(
          width: min(geometry.size.width - 32, 560),
          height: min(geometry.size.height * 0.82, 720)
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .tint(tintColor)
    .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
  }
}

@available(iOS 26.0, *)
private func presentAppleSearchSort(
  from presenter: UIViewController,
  arguments: [String: Any],
  result: @escaping FlutterResult
) {
  let rawItems = arguments["items"] as? [[String: Any]] ?? []
  let items = rawItems.compactMap { raw -> AppleSearchSortItem? in
    guard let value = raw["value"] as? String,
          let label = raw["label"] as? String else { return nil }
    return AppleSearchSortItem(id: value, label: label)
  }
  let initialValue = arguments["initialValue"] as? String ?? ""
  let isArabic = arguments["isArabic"] as? Bool ?? false
  let tintColor = Color(
    uiColor: skyStreamUIColor(arguments["tintColor"], fallback: .systemBlue)
  )
  var hostingController: UIHostingController<AppleSearchSortOverlay>?
  let overlay = AppleSearchSortOverlay(
    items: items,
    initialValue: initialValue,
    isArabic: isArabic,
    tintColor: tintColor,
    onCancel: {
      hostingController?.dismiss(animated: true) { result(nil) }
    },
    onApply: { value in
      hostingController?.dismiss(animated: true) { result(value) }
    }
  )
  let host = UIHostingController(rootView: overlay)
  hostingController = host
  host.view.backgroundColor = .clear
  host.modalPresentationStyle = .overFullScreen
  host.modalTransitionStyle = .crossDissolve
  presenter.present(host, animated: true)
}

@available(iOS 26.0, *)
private func presentAppleSearchFilters(
  from presenter: UIViewController,
  arguments: [String: Any],
  result: @escaping FlutterResult
) {
  let options = arguments["options"] as? [String: Any] ?? [:]
  let initialValue = arguments["initialValue"] as? [String: Any] ?? [:]
  let isArabic = arguments["isArabic"] as? Bool ?? false
  let tintColor = Color(
    uiColor: skyStreamUIColor(arguments["tintColor"], fallback: .systemBlue)
  )
  var hostingController: UIHostingController<AppleSearchFilterOverlay>?
  let overlay = AppleSearchFilterOverlay(
    options: options,
    initialValue: initialValue,
    isArabic: isArabic,
    tintColor: tintColor,
    onCancel: {
      hostingController?.dismiss(animated: true) { result(nil) }
    },
    onApply: { value in
      hostingController?.dismiss(animated: true) { result(value) }
    }
  )
  let host = UIHostingController(rootView: overlay)
  hostingController = host
  host.view.backgroundColor = .clear
  host.modalPresentationStyle = .overFullScreen
  host.modalTransitionStyle = .crossDissolve
  presenter.present(host, animated: true)
}
