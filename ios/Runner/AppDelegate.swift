import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var downloadLiveActivityChannel: FlutterMethodChannel?
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

    let channel = FlutterMethodChannel(
      name: "dev.akash.skystream/download_live_activity",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
#if os(iOS)
      guard #available(iOS 16.1, *) else {
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

      let progress =
        (arguments["progress"] as? NSNumber)?.doubleValue ?? 0.0
      let speedMBps =
        (arguments["speedMBps"] as? NSNumber)?.doubleValue ?? 0.0
      let status = arguments["status"] as? String ?? "downloading"

      Task { @MainActor in
        do {
          switch call.method {
          case "start":
            guard let animeTitle = arguments["animeTitle"] as? String,
                  let episodeTitle = arguments["episodeTitle"] as? String else {
              result(
                FlutterError(
                  code: "INVALID_ARGUMENTS",
                  message: "animeTitle and episodeTitle are required",
                  details: nil
                )
              )
              return
            }

            let activityId = try await DownloadLiveActivityManager.shared.start(
              taskId: taskId,
              animeTitle: animeTitle,
              episodeTitle: episodeTitle
            )
            result(activityId)

          case "update":
            await DownloadLiveActivityManager.shared.update(
              taskId: taskId,
              progress: progress,
              speedMBps: speedMBps,
              status: status
            )
            result(true)

          case "end":
            await DownloadLiveActivityManager.shared.end(
              taskId: taskId,
              progress: progress,
              speedMBps: speedMBps,
              status: status
            )
            result(true)

          default:
            result(FlutterMethodNotImplemented)
          }
        } catch {
          result(
            FlutterError(
              code: "LIVE_ACTIVITY_ERROR",
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

    downloadLiveActivityChannel = channel
  }
}
