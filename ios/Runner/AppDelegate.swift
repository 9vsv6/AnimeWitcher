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

private final class AppleNativeToolbarPlatformView: NSObject, FlutterPlatformView {
  private let rootView: UIView
  private let channel: FlutterMethodChannel
  private var legacyToolbar: UIToolbar?
  private var glassContainerView: UIVisualEffectView?
  private var glassSlots: [UIVisualEffectView] = []
  private var actionButtons: [UIButton] = []
  private var currentActionCount = 0
  private var didApplyInitialState = false
  private var itemExtent: CGFloat = 46
  private var hostWidth: CGFloat = 170

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments args: Any?
  ) {
    rootView = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "dev.akash.skystream/native_toolbar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    rootView.backgroundColor = .clear
    rootView.isOpaque = false

    if #available(iOS 26.0, *) {
      setUpGlassContainer()
    } else {
      setUpLegacyToolbar()
    }
    apply(arguments: args, animated: false)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "update":
        self.apply(arguments: call.arguments, animated: true)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { rootView }

  @available(iOS 26.0, *)
  private func setUpGlassContainer() {
    let containerEffect = UIGlassContainerEffect()
    // Apple's container spacing controls when neighboring droplets begin to
    // interact. Keeping this smaller than the icon extent gives the three
    // controls one continuous capsule at rest and a fluid merge to one circle.
    containerEffect.spacing = 10
    let container = UIVisualEffectView(effect: containerEffect)
    container.translatesAutoresizingMaskIntoConstraints = false
    container.backgroundColor = .clear
    container.isUserInteractionEnabled = true
    rootView.addSubview(container)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      container.topAnchor.constraint(equalTo: rootView.topAnchor),
      container.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    glassContainerView = container
  }

  private func setUpLegacyToolbar() {
    let toolbar = UIToolbar()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbar.isTranslucent = true
    rootView.addSubview(toolbar)
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: rootView.topAnchor),
      toolbar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
    legacyToolbar = toolbar
  }

  @available(iOS 26.0, *)
  private func makeGlassEffect() -> UIGlassEffect {
    let effect = UIGlassEffect(style: .regular)
    effect.isInteractive = true
    return effect
  }

  @available(iOS 26.0, *)
  private func ensureGlassSlotCount(_ count: Int) {
    guard let container = glassContainerView else { return }
    while glassSlots.count < count {
      let slot = UIVisualEffectView(effect: nil)
      slot.backgroundColor = .clear
      slot.isOpaque = false
      slot.isUserInteractionEnabled = true
      slot.cornerConfiguration = .capsule()

      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.backgroundColor = .clear
      button.addTarget(self, action: #selector(glassButtonPressed(_:)), for: .touchUpInside)
      slot.contentView.addSubview(button)
      NSLayoutConstraint.activate([
        button.leadingAnchor.constraint(equalTo: slot.contentView.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: slot.contentView.trailingAnchor),
        button.topAnchor.constraint(equalTo: slot.contentView.topAnchor),
        button.bottomAnchor.constraint(equalTo: slot.contentView.bottomAnchor),
      ])

      container.contentView.addSubview(slot)
      glassSlots.append(slot)
      actionButtons.append(button)
    }
  }

  private func frameForAction(index: Int, count: Int, extent: CGFloat) -> CGRect {
    let rightInset: CGFloat = 8
    let step = max(1, extent - 2)
    let availableWidth = max(rootView.bounds.width, hostWidth)
    let anchorX = max(0, availableWidth - rightInset - extent)
    let x = anchorX - CGFloat(max(0, count - 1 - index)) * step
    let y = max(0, (rootView.bounds.height - extent) / 2)
    return CGRect(x: x, y: y, width: extent, height: extent)
  }

  @available(iOS 26.0, *)
  private func configureGlassButton(
    slot: Int,
    actionIndex: Int,
    action: [String: Any],
    crossfadeImage: Bool
  ) {
    guard slot < actionButtons.count else { return }
    let button = actionButtons[slot]
    button.tag = actionIndex
    button.isUserInteractionEnabled = true
    button.isEnabled = action["enabled"] as? Bool ?? true
    button.accessibilityLabel = action["accessibilityLabel"] as? String
    button.accessibilityTraits = .button

    let systemName = action["systemName"] as? String ?? "circle"
    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
    let image = UIImage(systemName: systemName, withConfiguration: symbolConfiguration)
    let foreground = skyStreamUIColor(action["color"], fallback: .label)

    let applyImage = {
      button.setImage(image, for: .normal)
      button.tintColor = foreground
    }
    if crossfadeImage {
      UIView.transition(
        with: button,
        duration: 0.18,
        options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent],
        animations: applyImage
      )
    } else {
      applyImage()
    }

    let selectedValue = action["selectedValue"] as? String
    let menuTint = skyStreamUIColor(
      action["menuTintColor"],
      fallback: foreground
    )
    let menuItems = action["menuItems"] as? [[String: Any]] ?? []
    let menuActions: [UIAction] = menuItems.compactMap { menuItem in
      guard let value = menuItem["value"] as? String,
            let label = menuItem["label"] as? String else { return nil }
      let isDestructive = menuItem["destructive"] as? Bool == true
      let menuImage = (menuItem["systemImage"] as? String).flatMap { name -> UIImage? in
        if isDestructive { return UIImage(systemName: name) }
        return skyStreamMenuImage(named: name, tintColor: menuTint)
      }
      var attributes: UIMenuElement.Attributes = []
      if isDestructive { attributes.insert(.destructive) }
      return UIAction(
        title: label,
        image: menuImage,
        attributes: attributes,
        state: value == selectedValue ? .on : .off
      ) { [weak self] _ in
        self?.channel.invokeMethod(
          "selected",
          arguments: ["index": actionIndex, "value": value]
        )
      }
    }
    button.menu = menuActions.isEmpty ? nil : UIMenu(children: menuActions)
    button.showsMenuAsPrimaryAction = !menuActions.isEmpty
    if #available(iOS 16.0, *) {
      button.preferredMenuElementOrder = .fixed
    }
  }

  @available(iOS 26.0, *)
  private func setGlassEffect(_ slot: Int, enabled: Bool, animated: Bool) {
    guard slot < glassSlots.count else { return }
    let update = {
      self.glassSlots[slot].effect = enabled ? self.makeGlassEffect() : nil
    }
    if animated {
      UIView.animate(
        withDuration: 0.18,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction],
        animations: update
      )
    } else {
      update()
    }
  }

  @available(iOS 26.0, *)
  private func applyGlass(actions: [[String: Any]], animated: Bool) {
    let newCount = actions.count
    let oldCount = currentActionCount
    let slotCount = max(max(oldCount, newCount), 1)
    ensureGlassSlotCount(slotCount)

    let anchorFrame = frameForAction(index: 0, count: 1, extent: itemExtent)
    let structuralChange = didApplyInitialState && oldCount != newCount

    if !didApplyInitialState {
      for index in 0..<glassSlots.count {
        if index < newCount {
          configureGlassButton(
            slot: index,
            actionIndex: index,
            action: actions[index],
            crossfadeImage: false
          )
          glassSlots[index].frame = frameForAction(
            index: index,
            count: newCount,
            extent: itemExtent
          )
          actionButtons[index].alpha = 1
          setGlassEffect(index, enabled: true, animated: false)
        } else {
          actionButtons[index].alpha = 0
          setGlassEffect(index, enabled: false, animated: false)
        }
      }
      currentActionCount = newCount
      didApplyInitialState = true
      return
    }

    if oldCount > 1 && newCount == 1 {
      // Keep slot 0 alive and turn its content into the destination action.
      // The other droplets move into the same frame. UIGlassContainerEffect
      // performs the actual Liquid Glass merge while the content fades.
      configureGlassButton(
        slot: 0,
        actionIndex: 0,
        action: actions[0],
        crossfadeImage: true
      )
      setGlassEffect(0, enabled: true, animated: false)
      for index in 1..<oldCount where index < actionButtons.count {
        actionButtons[index].isUserInteractionEnabled = false
      }

      let animations = {
        for index in 0..<oldCount where index < self.glassSlots.count {
          self.glassSlots[index].frame = anchorFrame
          if index > 0 { self.actionButtons[index].alpha = 0 }
        }
      }
      let completion: (Bool) -> Void = { _ in
        for index in 1..<oldCount where index < self.glassSlots.count {
          self.setGlassEffect(index, enabled: false, animated: true)
        }
      }
      UIView.animate(
        springDuration: animated ? 0.46 : 0.0,
        bounce: 0.06,
        initialSpringVelocity: 0.0,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction],
        animations: animations,
        completion: completion
      )
    } else if oldCount == 1 && newCount > 1 {
      // Apple's guidance for splitting glass is to first place the new droplets
      // at the same position, then animate them apart together.
      for index in 0..<newCount {
        glassSlots[index].frame = anchorFrame
        configureGlassButton(
          slot: index,
          actionIndex: index,
          action: actions[index],
          crossfadeImage: index == 0
        )
        setGlassEffect(index, enabled: true, animated: false)
        actionButtons[index].alpha = index == 0 ? 1 : 0
      }
      rootView.layoutIfNeeded()
      UIView.animate(
        springDuration: animated ? 0.46 : 0.0,
        bounce: 0.06,
        initialSpringVelocity: 0.0,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        for index in 0..<newCount {
          self.glassSlots[index].frame = self.frameForAction(
            index: index,
            count: newCount,
            extent: self.itemExtent
          )
          self.actionButtons[index].alpha = 1
        }
      }
    } else {
      // Same-count updates keep the native views intact. Generic count changes
      // still animate geometry and materialization without replacing the host.
      let maxCount = max(oldCount, newCount)
      for index in 0..<newCount {
        configureGlassButton(
          slot: index,
          actionIndex: index,
          action: actions[index],
          crossfadeImage: structuralChange
        )
        setGlassEffect(index, enabled: true, animated: structuralChange && animated)
      }
      UIView.animate(
        springDuration: structuralChange && animated ? 0.42 : 0.0,
        bounce: 0.04,
        initialSpringVelocity: 0.0,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        for index in 0..<maxCount where index < self.glassSlots.count {
          if index < newCount {
            self.glassSlots[index].frame = self.frameForAction(
              index: index,
              count: newCount,
              extent: self.itemExtent
            )
            self.actionButtons[index].alpha = 1
          } else {
            self.glassSlots[index].frame = anchorFrame
            self.actionButtons[index].alpha = 0
          }
        }
      } completion: { _ in
        if newCount < maxCount {
          for index in newCount..<maxCount where index < self.glassSlots.count {
            self.setGlassEffect(index, enabled: false, animated: animated)
          }
        }
      }
    }

    currentActionCount = newCount
  }

  private func makeLegacyItems(actions: [[String: Any]]) -> [UIBarButtonItem] {
    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
    return actions.enumerated().map { index, action in
      let systemName = action["systemName"] as? String ?? "circle"
      let image = UIImage(systemName: systemName, withConfiguration: symbolConfiguration)
      let selectedValue = action["selectedValue"] as? String
      let menuItems = action["menuItems"] as? [[String: Any]] ?? []
      let item: UIBarButtonItem
      if #available(iOS 14.0, *), !menuItems.isEmpty {
        let menuActions: [UIAction] = menuItems.compactMap { menuItem in
          guard let value = menuItem["value"] as? String,
                let label = menuItem["label"] as? String else { return nil }
          let menuTint = skyStreamUIColor(
            action["menuTintColor"],
            fallback: skyStreamUIColor(action["color"], fallback: .label)
          )
          let isDestructive = menuItem["destructive"] as? Bool == true
          let menuImage = (menuItem["systemImage"] as? String).flatMap { name -> UIImage? in
            guard let image = UIImage(systemName: name) else { return nil }
            return isDestructive ? image : image.withTintColor(menuTint, renderingMode: .alwaysOriginal)
          }
          var attributes: UIMenuElement.Attributes = []
          if isDestructive { attributes.insert(.destructive) }
          return UIAction(
            title: label,
            image: menuImage,
            attributes: attributes,
            state: value == selectedValue ? .on : .off
          ) { [weak self] _ in
            self?.channel.invokeMethod("selected", arguments: ["index": index, "value": value])
          }
        }
        item = UIBarButtonItem(image: image, primaryAction: nil, menu: UIMenu(children: menuActions))
      } else {
        item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(legacyItemPressed(_:)))
      }
      item.tag = index
      item.isEnabled = action["enabled"] as? Bool ?? true
      item.tintColor = skyStreamUIColor(action["color"], fallback: .label)
      item.accessibilityLabel = action["accessibilityLabel"] as? String
      return item
    }
  }

  private func apply(arguments: Any?, animated: Bool) {
    guard let values = arguments as? [String: Any] else { return }
    let actions = values["actions"] as? [[String: Any]] ?? []
    itemExtent = CGFloat((values["itemExtent"] as? NSNumber)?.doubleValue ?? 46)
    hostWidth = CGFloat((values["hostWidth"] as? NSNumber)?.doubleValue ?? max(46, rootView.bounds.width))

    if #available(iOS 26.0, *) {
      applyGlass(actions: actions, animated: animated)
    } else {
      legacyToolbar?.setItems(makeLegacyItems(actions: actions), animated: animated)
      currentActionCount = actions.count
      didApplyInitialState = true
    }
  }

  @objc private func glassButtonPressed(_ sender: UIButton) {
    guard sender.isEnabled else { return }
    channel.invokeMethod("pressed", arguments: sender.tag)
  }

  @objc private func legacyItemPressed(_ sender: UIBarButtonItem) {
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
