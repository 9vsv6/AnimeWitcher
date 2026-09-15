from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    raw = p.read_bytes()
    newline = '\r\n' if b'\r\n' in raw else '\n'
    text = raw.decode('utf-8').replace('\r\n', '\n')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, got {count}')
    updated = text.replace(old, new, 1)
    if newline == '\r\n':
        updated = updated.replace('\n', '\r\n')
    p.write_bytes(updated.encode('utf-8'))


# Continued-processing update acknowledgements: an expired iOS 26 system task
# must invalidate Dart's cached overlay state so start() can recreate it.
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    'typedef SystemDownloadCancellation = Future<void> Function(String taskId);\n',
    'typedef SystemDownloadCancellation = Future<void> Function(String taskId);\n'
    'typedef SystemDownloadSessionLost = void Function();\n',
)
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    '''  final SystemDownloadCancellation onSystemCancel;
  final SystemDownloadTaskUpdate? onTaskUpdate;
''',
    '''  final SystemDownloadCancellation onSystemCancel;
  final SystemDownloadSessionLost? onSessionLost;
  final SystemDownloadTaskUpdate? onTaskUpdate;
''',
)
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    '''  DownloadContinuedProcessingService({
    required this.onSystemCancel,
    this.onTaskUpdate,
''',
    '''  DownloadContinuedProcessingService({
    required this.onSystemCancel,
    this.onSessionLost,
    this.onTaskUpdate,
''',
)
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    '''      _lastUpdateAt = now;
      if (pending != null) await _invoke('update', pending);
      return;
''',
    '''      _lastUpdateAt = now;
      if (pending != null) await _sendUpdate(pending);
      return;
''',
)
replace_once(
    'lib/core/services/download_continued_processing_service.dart',
    '''      _lastUpdateAt = DateTime.now();
      await _invoke('update', pending);
    });
  }

  void _cancelPendingUpdate() {
''',
    '''      _lastUpdateAt = DateTime.now();
      await _sendUpdate(pending);
    });
  }

  Future<void> _sendUpdate(Map<String, Object> arguments) async {
    final accepted = await _invokeForResult<Object?>('update', arguments);
    if (accepted is bool && !accepted && !_disposed) {
      onSessionLost?.call();
    }
  }

  void _cancelPendingUpdate() {
''',
)

# Native Swift returns whether a continued-processing session still exists.
replace_once(
    'ios/Runner/DownloadContinuedProcessingManager.swift',
    '''    currentIndex: Int = -1
  ) {
''',
    '''    currentIndex: Int = -1
  ) -> Bool {
''',
)
replace_once(
    'ios/Runner/DownloadContinuedProcessingManager.swift',
    '''    guard var snapshot = snapshot else { return }
''',
    '''    guard var snapshot = snapshot else { return false }
''',
)
replace_once(
    'ios/Runner/DownloadContinuedProcessingManager.swift',
    '''    if let task = activeTask {
      apply(snapshot, to: task)
    }
  }

  func finish''',
    '''    if let task = activeTask {
      apply(snapshot, to: task)
    }
    return activeTask != nil || identifier != nil
  }

  func finish''',
)
replace_once(
    'ios/Runner/AppDelegate.swift',
    '''            manager.update(
              taskId: taskId,
''',
    '''            let active = manager.update(
              taskId: taskId,
''',
)
replace_once(
    'ios/Runner/AppDelegate.swift',
    '''              currentIndex: (arguments["currentIndex"] as? NSNumber)?.intValue ?? -1
            )
            result(true)

          case "finish":
''',
    '''              currentIndex: (arguments["currentIndex"] as? NSNumber)?.intValue ?? -1
            )
            result(active)

          case "finish":
''',
)

# Native multipart offers are ownership handoff fences, not ordinary foreground
# queue metadata. Only export them while backgrounding, then withdraw unclaimed
# offers after runtime reconciliation on foreground return.
replace_once(
    'lib/core/services/persistent_parallel_download.dart',
    '''  /// Repair a child whose native resume checkpoint claimed progress but no
''',
    '''  /// Returns unclaimed native background offers to Dart after a foreground
  /// reconciliation pass has already adopted any URLSession children that
  /// actually started. Live children remain fenced by [part.launched].
  void releaseNativeBackgroundOffers() {
    if (_disposed || _nativeClaimOffers.isEmpty) return;
    _nativeClaimOffers.clear();
    _schedulePumpAll();
  }

  /// Repair a child whose native resume checkpoint claimed progress but no
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''  bool _sessionOverlayActive = false;
  int _sessionCompletedCount = 0;
''',
    '''  bool _sessionOverlayActive = false;
  bool _appInForeground = true;
  int _sessionCompletedCount = 0;
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''    _continuedProcessing = DownloadContinuedProcessingService(
      onSystemCancel: _cancelFromSystemUI,
      onTaskUpdate: _handleNativeTaskUpdate,
      onChunkUpdate: _handleNativeChunkUpdate,
    );
''',
    '''    _continuedProcessing = DownloadContinuedProcessingService(
      onSystemCancel: _cancelFromSystemUI,
      onSessionLost: () {
        if (_disposed) return;
        _sessionOverlayActive = false;
        Future<void>.delayed(Duration.zero, () {
          if (!_disposed) unawaited(_syncSessionOverlay());
        });
      },
      onTaskUpdate: _handleNativeTaskUpdate,
      onChunkUpdate: _handleNativeChunkUpdate,
    );
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''    final multipartPlans = <Map<String, Object>>[];
    if (Platform.isIOS) {
''',
    '''    final multipartPlans = <Map<String, Object>>[];
    if (Platform.isIOS && !_appInForeground) {
''',
)
replace_once(
    'lib/core/services/download_service.dart',
    '''  /// Attach UI to live native tasks. Never detach a live URLSession task.
  /// Promote leftover parked waiters only if native does not already own
  /// that episode. Never pause/re-enqueue/restart URLSession here.
  Future<void> onAppForegrounded() async {
    if (!await _awaitLifecycleReadiness('foreground')) return;
    await _serializeQueue(() async {
      await _reconcileTransferOwnership();
      await _attachUiToLiveNativeTasks();
      await _syncQueueToCapUnlocked();
    });
    await _syncSessionOverlay();
  }
''',
    '''  /// Persist the background handoff while Flutter is still alive. Native
  /// multipart plans are deliberately exported only here; ordinary foreground
  /// overlay/queue snapshots must never reserve untouched Ranges for Swift.
  Future<void> onAppBackgrounded() async {
    if (!await _awaitLifecycleReadiness('background')) return;
    _appInForeground = false;
    await _serializeQueue(() => _persistNativeWaitingSnapshot());
  }

  /// Attach UI to live native tasks. Never detach a live URLSession task.
  /// Promote leftover parked waiters only if native does not already own
  /// that episode. Never pause/re-enqueue/restart URLSession here.
  Future<void> onAppForegrounded() async {
    _appInForeground = true;
    if (!await _awaitLifecycleReadiness('foreground')) return;
    await _serializeQueue(() async {
      await _reconcileTransferOwnership();
      _parallel.releaseNativeBackgroundOffers();
      await _attachUiToLiveNativeTasks();
      await _syncQueueToCapUnlocked();
    });
    await _syncSessionOverlay();
  }
''',
)

replace_once(
    'lib/main.dart',
    '''  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(downloadServiceProvider).onAppForegrounded());
    }
    if (state != AppLifecycleState.resumed) return;
''',
    '''  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(downloadServiceProvider).onAppForegrounded());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(ref.read(downloadServiceProvider).onAppBackgrounded());
    }
    if (state != AppLifecycleState.resumed) return;
''',
)
