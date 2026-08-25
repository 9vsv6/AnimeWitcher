import AVFoundation
import AVKit
import Flutter
import UIKit

/// Official iOS Picture-in-Picture host.
///
/// Apple requires `AVPictureInPictureController` plus an `AVPlayerLayer` in the
/// view hierarchy, the Audio background mode, and an `.playback` audio session.
/// https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller
///
/// The layer stays *behind* Flutter. Making Flutter's view non-opaque lets the
/// video show through the player chrome instead of covering the buttons. After
/// system PiP starts or stops, iOS often raises that view — we pin it back.
final class PlayerPipHost: NSObject, AVPictureInPictureControllerDelegate {
    static let playerDidChange = Notification.Name("dev.akash.skystream.pipPlayer")

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
    private var surfaceActive = false
    private var startRetryWorkItem: DispatchWorkItem?
    private weak var attachedHost: UIView?

    init(messenger: FlutterBinaryMessenger, hostViewProvider: @escaping () -> UIView?) {
        channel = FlutterMethodChannel(
            name: "dev.akash.skystream.player/pip",
            binaryMessenger: messenger
        )
        self.hostViewProvider = hostViewProvider
        super.init()

        playerView.isUserInteractionEnabled = false
        playerView.isOpaque = false
        playerView.backgroundColor = .clear
        playerView.isHidden = false
        playerView.alpha = 0.01
        playerView.layer.zPosition = -1
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.playerLayer.opacity = 1

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidChange(_:)),
            name: Self.playerDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    deinit {
        startRetryWorkItem?.cancel()
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
            if !active {
                stopPictureInPictureIfNeeded()
                deactivateInlineSurface()
            }
        }
        if let enabled = args["enabled"] as? Bool {
            sessionEnabled = enabled
            if !enabled {
                stopPictureInPictureIfNeeded()
                deactivateInlineSurface()
            }
        }
    }

    private func stopPictureInPictureIfNeeded() {
        pendingStart = false
        startRetryWorkItem?.cancel()
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
    }

    private var shouldAutoEnter: Bool {
        sessionActive && sessionEnabled && isPlaying && isPipAvailable
    }

    @objc
    private func applicationBecameActive() {
        pinLayerBehindFlutter()
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
        pinLayerBehindFlutter()
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
            playerView.layer.zPosition = -1
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

    private func pinLayerBehindFlutter() {
        attachLayerIfNeeded()
        playerView.layer.zPosition = -1
        playerView.isUserInteractionEnabled = false
        playerView.superview?.sendSubviewToBack(playerView)
    }

    private func setFlutterViewOpaque(_ opaque: Bool) {
        guard let host = hostViewProvider() ?? keyWindowRootView() else { return }
        applyOpacity(to: host, opaque: opaque)
    }

    private func applyOpacity(to view: UIView, opaque: Bool) {
        view.isOpaque = opaque
        view.backgroundColor = opaque ? .black : .clear
        for sub in view.subviews where sub !== playerView {
            let name = NSStringFromClass(type(of: sub))
            if name.contains("FlutterView") {
                applyOpacity(to: sub, opaque: opaque)
            }
        }
    }

    private func activateInlineSurface() {
        surfaceActive = true
        setFlutterViewOpaque(false)
        playerView.alpha = 1
        playerView.isHidden = false
        pinLayerBehindFlutter()
        channel.invokeMethod("pipSurfaceActive", arguments: true)
    }

    private func deactivateInlineSurface() {
        guard surfaceActive else {
            pinLayerBehindFlutter()
            return
        }
        surfaceActive = false
        playerView.alpha = 0.01
        pinLayerBehindFlutter()
        setFlutterViewOpaque(true)
        channel.invokeMethod("pipSurfaceActive", arguments: false)
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
        let controller: AVPictureInPictureController? =
            AVPictureInPictureController(playerLayer: playerView.playerLayer)
        guard let controller else { return }
        controller.delegate = self
        pipController = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            [weak self] _, _ in
            self?.pinLayerBehindFlutter()
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
        pendingStart = true
        activateInlineSurface()
        if playerView.playerLayer.player == nil {
            startFallbackPlayer(arguments: arguments)
        }
        recreatePipController()
        tryStartIfPending()
        scheduleStartRetries()
        return true
    }

    private func scheduleStartRetries() {
        startRetryWorkItem?.cancel()
        let delays: [TimeInterval] = [0.05, 0.15, 0.3, 0.6, 1.0, 1.6, 2.2]
        let work = DispatchWorkItem { [weak self] in
            self?.tryStartIfPending()
        }
        startRetryWorkItem = work
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pendingStart, !work.isCancelled else { return }
                self.pinLayerBehindFlutter()
                self.tryStartIfPending()
            }
        }
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
        pinLayerBehindFlutter()
        if pipController.isPictureInPictureActive {
            pendingStart = false
            startRetryWorkItem?.cancel()
            return
        }
        guard pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
    }

    private func currentPositionMs() -> Int {
        guard let time = playerView.playerLayer.player?.currentTime() else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds * 1000)
    }

    private func notifyPipMode(active: Bool) {
        channel.invokeMethod(
            "pipModeChanged",
            arguments: [
                "active": active,
                "positionMs": currentPositionMs(),
            ]
        )
    }

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pinLayerBehindFlutter()
        notifyPipMode(active: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pendingStart = false
        startRetryWorkItem?.cancel()
        // Keep the inline copy behind Flutter at near-zero alpha so a failed
        // restore animation cannot cover the player chrome.
        playerView.alpha = 0.01
        pinLayerBehindFlutter()
        notifyPipMode(active: true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        NSLog("[PlayerPip] start failed: \(error.localizedDescription)")
        pinLayerBehindFlutter()
        activateInlineSurface()
        notifyPipMode(active: false)
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pinLayerBehindFlutter()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pendingStart = false
        startRetryWorkItem?.cancel()
        pinLayerBehindFlutter()
        if let fallbackPlayer {
            fallbackPlayer.pause()
            self.fallbackPlayer = nil
            if playerView.playerLayer.player === fallbackPlayer {
                playerView.playerLayer.player = nil
            }
        }
        notifyPipMode(active: false)
        deactivateInlineSurface()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        pinLayerBehindFlutter()
        DispatchQueue.main.async { [weak self] in
            self?.pinLayerBehindFlutter()
        }
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
