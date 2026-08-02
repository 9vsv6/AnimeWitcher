import Flutter
import UIKit
import UserNotifications

private let nativeAppleTabBarViewType =
  "dev.akash.skystream/native_apple_tab_bar"

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
      NativeAppleTabBarFactory(messenger: applicationRegistrar.messenger()),
      withId: nativeAppleTabBarViewType
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

private final class NativeAppleTabBarFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeAppleTabBarPlatformView(
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

private final class NativeAppleTabBarPlatformView: NSObject, FlutterPlatformView {
  private let tabBarView: NativeAppleTabBarView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    tabBarView = NativeAppleTabBarView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(nativeAppleTabBarViewType)_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    tabBarView.apply(arguments: arguments as? [String: Any] ?? [:])
    tabBarView.onSelected = { [weak self] index in
      self?.channel.invokeMethod("onTap", arguments: index)
    }

    channel.setMethodCallHandler {
      [weak tabBarView = self.tabBarView] call, result in
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

private final class NativeAppleTabBarView: UIView, UITabBarDelegate {
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

  // UITabBar owns its material, selection lens, motion, and interactions.
  // Deliberately do not install a custom effect, background, or indicator.
  private let tabBar = UITabBar()
  private var labels = NativeAppleTabBarView.defaultLabels
  private var selectedIndex = 0
  private var accentColor = UIColor.systemBlue

  var onSelected: ((Int) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false

    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.delegate = self
    addSubview(tabBar)

    NSLayoutConstraint.activate([
      tabBar.topAnchor.constraint(equalTo: topAnchor),
      tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      tabBar.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    rebuildItems()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(arguments: [String: Any]) {
    if let suppliedLabels = arguments["labels"] as? [String],
       suppliedLabels.count == NativeAppleTabBarView.symbols.count {
      labels = suppliedLabels
      rebuildItems()
    }

    if let colorNumber = arguments["accentColor"] as? NSNumber {
      accentColor = UIColor(argb: colorNumber.uint32Value)
    }
    tabBar.tintColor = accentColor
    tabBar.unselectedItemTintColor = .secondaryLabel

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
    tabBar.semanticContentAttribute = semanticDirection

    let index = (arguments["selectedIndex"] as? NSNumber)?.intValue ?? 0
    setSelectedIndex(index, notifyFlutter: false)
  }

  func setSelectedIndex(_ index: Int, notifyFlutter: Bool) {
    guard let items = tabBar.items, !items.isEmpty else { return }
    let nextIndex = min(max(index, 0), items.count - 1)
    selectedIndex = nextIndex
    tabBar.selectedItem = items[nextIndex]

    if notifyFlutter {
      onSelected?(nextIndex)
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let items = tabBar.items,
          items.indices.contains(item.tag) else { return }
    selectedIndex = item.tag
    onSelected?(selectedIndex)
  }

  private func rebuildItems() {
    let items = NativeAppleTabBarView.symbols.enumerated().map {
      index, symbolName in
      let item = UITabBarItem(
        title: labels[index],
        image: UIImage(systemName: symbolName),
        selectedImage: UIImage(
          systemName: NativeAppleTabBarView.selectedSymbols[index]
        )
      )
      item.tag = index
      item.accessibilityIdentifier = "main-tab-\(index)"
      return item
    }

    tabBar.setItems(items, animated: false)
    setSelectedIndex(selectedIndex, notifyFlutter: false)
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
