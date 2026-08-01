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

private final class LiquidGlassTabBarView: UIView {
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
  private let stackView = UIStackView()
  private var buttons: [UIButton] = []
  private var labels = LiquidGlassTabBarView.defaultLabels
  private var selectedIndex = 0
  private var accentColor = UIColor.systemBlue

  var onSelected: ((Int) -> Void)?

  override init(frame: CGRect) {
    if #available(iOS 26.0, *) {
      effectView = UIVisualEffectView(effect: UIGlassEffect())
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
    effectView.cornerConfiguration = .corners(radius: .fixed(36))
    } else {
      effectView.layer.cornerRadius = 36
      effectView.layer.cornerCurve = .continuous
    }
    addSubview(effectView)

    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = 4
    stackView.translatesAutoresizingMaskIntoConstraints = false
    effectView.contentView.addSubview(stackView)

    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stackView.topAnchor.constraint(
        equalTo: effectView.contentView.topAnchor,
        constant: 5
      ),
      stackView.leadingAnchor.constraint(
        equalTo: effectView.contentView.leadingAnchor,
        constant: 7
      ),
      stackView.trailingAnchor.constraint(
        equalTo: effectView.contentView.trailingAnchor,
        constant: -7
      ),
      stackView.bottomAnchor.constraint(
        equalTo: effectView.contentView.bottomAnchor,
        constant: -5
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
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(arguments: [String: Any]) {
    if let suppliedLabels = arguments["labels"] as? [String],
       suppliedLabels.count == buttons.count {
      labels = suppliedLabels
    }

    if let colorNumber = arguments["accentColor"] as? NSNumber {
      accentColor = UIColor(argb: colorNumber.uint32Value)
    }

    switch arguments["brightness"] as? String {
    case "dark":
      overrideUserInterfaceStyle = .dark
    case "light":
      overrideUserInterfaceStyle = .light
    default:
      overrideUserInterfaceStyle = .unspecified
    }

    semanticContentAttribute = arguments["textDirection"] as? String == "rtl"
      ? .forceRightToLeft
      : .forceLeftToRight

    let index = (arguments["selectedIndex"] as? NSNumber)?.intValue ?? 0
    setSelectedIndex(index, notifyFlutter: false)
  }

  func setSelectedIndex(_ index: Int, notifyFlutter: Bool) {
    selectedIndex = min(max(index, 0), buttons.count - 1)
    updateButtons()
    if notifyFlutter {
      onSelected?(selectedIndex)
    }
  }

  private func updateButtons() {
    for (index, button) in buttons.enumerated() {
      let isSelected = index == selectedIndex
      var configuration: UIButton.Configuration

      if #available(iOS 26.0, *) {
        configuration = isSelected ? .glass() : .plain()
      } else {
        configuration = isSelected ? .tinted() : .plain()
        if isSelected {
          configuration.baseBackgroundColor = accentColor.withAlphaComponent(
            0.18
          )
        }
      }

      let symbolName = isSelected
        ? LiquidGlassTabBarView.selectedSymbols[index]
        : LiquidGlassTabBarView.symbols[index]
      let symbolConfiguration = UIImage.SymbolConfiguration(
        pointSize: 22,
        weight: isSelected ? .semibold : .regular
      )

      configuration.image = UIImage(
        systemName: symbolName,
        withConfiguration: symbolConfiguration
      )
      configuration.title = labels[index]
      configuration.imagePlacement = .top
      configuration.imagePadding = 2
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 5,
        leading: 3,
        bottom: 5,
        trailing: 3
      )
      configuration.baseForegroundColor = isSelected
        ? accentColor
        : .secondaryLabel
      configuration.titleLineBreakMode = .byTruncatingTail
      configuration.titleTextAttributesTransformer =
        UIConfigurationTextAttributesTransformer { attributes in
          var updated = attributes
          updated.font = UIFont.systemFont(
            ofSize: 11,
            weight: isSelected ? .semibold : .medium
          )
          return updated
        }

      button.configuration = configuration
      button.accessibilityLabel = labels[index]
      button.accessibilityTraits = isSelected
        ? [.button, .selected]
        : [.button]
    }
  }

  @objc private func didTapButton(_ sender: UIButton) {
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
