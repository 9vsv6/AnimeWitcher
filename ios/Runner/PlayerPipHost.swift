import AVFoundation
import AVKit
import Flutter
import UIKit

/// Official iOS Picture-in-Picture host.
///
/// Apple requires `AVPictureInPictureController` plus an `AVPlayerLayer` in the
/// view hierarchy, the Audio background mode, and an `.playback` audio session.
/// https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller
final class PlayerPipHost: NSObject, AVPictureInPictureControllerDelegate {
    static let playerDidChange = Notification.Name("com.animewitcher.app.pipPlayer")

    private let channel: FlutterMethodChannel
    private let hostViewProvider: () -> UIView?
    private let playerView = PlayerPipLayerView()
    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var fallbackPlayer: AVPlayer?
    private var sessionActive = false
    private var sessionEnabled = true
    private var isPlaying = false
    private var pendingStart = false
    private weak var attachedHost: UIView?

    init(messenger: FlutterBinaryMessenger, hostViewProvider: @escaping () -> UIView?) {
        channel = FlutterMethodChannel(
            name: "com.animewitcher.app.player/pip",
            binaryMessenger: messenger
        )
        self.hostViewProvider = hostViewProvider
        super.init()

        playerView.isUserInteractionEnabled = false
        playerView.isOpaque = false
        playerView.backgroundColor = .clear
        playerView.isHidden = false
        // Keep a real, non-zero layer in the window. Flutter's texture sits
        // above it, so this copy is not visible but PiP can snapshot it.
        playerView.alpha = 0.02
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.playerLayer.opacity = 1

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidChange(_:)),
            name: Self.playerDidChange,
            object: nil
        )

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        possibleObservation = nil
        channel.setMethodCallHandler(nil)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enterPip":
            apply(arguments: call.arguments)
            result(enterPip(arguments: call.arguments))
        case "updatePip", "setPipState":
            apply(arguments: call.arguments)
            refreshAutoEnter()
            result(nil)
        case "isPipAvailable":
            result(isPipAvailable)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var isPipAvailable: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    private func apply(arguments: Any?) {
        let args = arguments as? [String: Any] ?? [:]
        if let playing = args["isPlaying"] as? Bool { isPlaying = playing }
        if let active = args["active"] as? Bool {
            sessionActive = active
            if !active { stopPictureInPictureIfNeeded() }
        }
        if let enabled = args["enabled"] as? Bool {
            sessionEnabled = enabled
            if !enabled { stopPictureInPictureIfNeeded() }
        }
    }

    private func stopPictureInPictureIfNeeded() {
        pendingStart = false
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
    }

    private var shouldAutoEnter: Bool {
        sessionActive && sessionEnabled && isPlaying && isPipAvailable
    }

    @objc
    private func playerDidChange(_ notification: Notification) {
        let player = notification.object as? AVPlayer
        if player == nil, pipController?.isPictureInPictureActive == true {
            return
        }
        attach(player: player, isFallback: false)
        tryStartIfPending()
    }

    private func attach(player: AVPlayer?, isFallback: Bool) {
        if !isFallback, fallbackPlayer != nil, fallbackPlayer !== player {
            fallbackPlayer?.pause()
            fallbackPlayer = nil
        }
        attachLayerIfNeeded()
        let previous = playerView.playerLayer.player
        playerView.playerLayer.player = player
        if #available(iOS 15.0, *), let player {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        if previous === player, pipController != nil {
            refreshAutoEnter()
            return
        }
        if pipController?.isPictureInPictureActive == true {
            refreshAutoEnter()
            return
        }
        recreatePipController()
        refreshAutoEnter()
    }

    private func attachLayerIfNeeded() {
        guard let host = hostViewProvider() ?? keyWindowRootView() else { return }
        if attachedHost !== host || playerView.superview !== host {
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = false
            host.insertSubview(playerView, at: 0)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: host.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
            attachedHost = host
        }
        host.sendSubviewToBack(playerView)
    }

    private func keyWindowRootView() -> UIView? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow)?.rootViewController?.view
            ?? scene?.windows.first?.rootViewController?.view
    }

    private func recreatePipController() {
        possibleObservation = nil
        pipController = nil
        guard isPipAvailable, playerView.playerLayer.player != nil else { return }
        // The playerLayer initializer is failable on some SDKs and non-optional
        // on others. Assigning through AVPictureInPictureController? covers both.
        let controller: AVPictureInPictureController? =
            AVPictureInPictureController(playerLayer: playerView.playerLayer)
        guard let controller else { return }
        controller.delegate = self
        pipController = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            [weak self] _, _ in
            self?.tryStartIfPending()
        }
        refreshAutoEnter()
    }

    private func refreshAutoEnter() {
        if #available(iOS 14.2, *) {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = shouldAutoEnter
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            NSLog("[PlayerPip] audio session: \(error.localizedDescription)")
        }
    }

    private func enterPip(arguments: Any?) -> Bool {
        guard isPipAvailable else { return false }
        activateAudioSession()
        sessionActive = true
        attachLayerIfNeeded()
        pendingStart = true
        if playerView.playerLayer.player == nil {
            // video_view publishes the AVPlayer asynchronously. Give it a beat
            // before opening a second AVPlayer for the same URL.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.pendingStart else { return }
                if self.playerView.playerLayer.player == nil {
                    self.startFallbackPlayer(arguments: arguments)
                }
                self.recreatePipController()
                self.tryStartIfPending()
            }
        } else {
            recreatePipController()
            tryStartIfPending()
        }
        if pipController?.isPictureInPictureActive == true {
            pendingStart = false
            return true
        }
        return true
    }

    private func stringHeaders(_ value: Any?) -> [String: String]? {
        if let typed = value as? [String: String], !typed.isEmpty {
            return typed
        }
        guard let raw = value as? [String: Any] else { return nil }
        var headers: [String: String] = [:]
        for (key, item) in raw {
            if let string = item as? String {
                headers[key] = string
            }
        }
        return headers.isEmpty ? nil : headers
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private func startFallbackPlayer(arguments: Any?) {
        let args = arguments as? [String: Any] ?? [:]
        guard let urlString = args["url"] as? String, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        let headers = stringHeaders(args["headers"])
        let asset: AVURLAsset
        if let headers, !headers.isEmpty {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        if let positionMs = intValue(args["positionMs"]), positionMs > 0 {
            let time = CMTime(milliseconds: positionMs)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        fallbackPlayer = player
        attach(player: player, isFallback: true)
        if args["isPlaying"] as? Bool ?? true {
            player.play()
        }
    }

    private func tryStartIfPending() {
        guard pendingStart, let pipController else { return }
        if pipController.isPictureInPictureActive {
            pendingStart = false
            return
        }
        guard pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
        pendingStart = false
    }

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        channel.invokeMethod("pipModeChanged", arguments: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        channel.invokeMethod("pipModeChanged", arguments: true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        pendingStart = false
        channel.invokeMethod("pipModeChanged", arguments: false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pendingStart = false
        channel.invokeMethod("pipModeChanged", arguments: false)
        if let fallbackPlayer {
            fallbackPlayer.pause()
            self.fallbackPlayer = nil
            if playerView.playerLayer.player === fallbackPlayer {
                playerView.playerLayer.player = nil
            }
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

private final class PlayerPipLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private extension CMTime {
    init(milliseconds: Int) {
        self.init(value: CMTimeValue(milliseconds), timescale: 1000)
    }
}
