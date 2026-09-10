from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:140]!r}")
    write(path, text.replace(old, new, 1))


parallel = 'lib/core/services/persistent_parallel_download.dart'
service = 'lib/core/services/download_service.dart'
native = 'ios/Runner/DownloadNativeWaitingQueue.swift'
runtime_test = 'test/core/services/download_runtime_stability_review_test.dart'

# ---------------------------------------------------------------------------
# 1) Close the synchronous pause-vs-slow-start race.
# ---------------------------------------------------------------------------
# pause() can be requested while a previously scheduled slow-start pump is
# waiting on the same session serializer. Set a synchronous intent fence before
# entering the serializer so that queued pumps cannot launch 2/4/8 more native
# children after the user already tapped Pause.
replace_once(
    parallel,
    '''    final session = _sessions[task.taskId]!;\n    return session.serialize(\n      () => _pause(session, preserveLiveParts: preserveLiveParts),\n    );\n''',
    '''    final session = _sessions[task.taskId]!;\n    // This flag is deliberately set before waiting for session.serialize(). A\n    // slow-start pump may already be queued ahead of _pause; it must observe\n    // the user's pause intent synchronously and stop before another enqueue.\n    session.pauseRequested = true;\n    return session.serialize(\n      () => _pause(session, preserveLiveParts: preserveLiveParts),\n    );\n''',
)

replace_once(
    parallel,
    '''      session.cancelAggregateProgress();\n      session.generation++;\n      session.active = true;\n      session.resetRamp();\n''',
    '''      session.cancelAggregateProgress();\n      session.generation++;\n      session.pauseRequested = false;\n      session.active = true;\n      session.resetRamp();\n''',
)

replace_once(
    parallel,
    '''  Future<bool> _pumpSession(_ParallelSession session) async {\n    if (_disposed || !session.active || session.deleted) return true;\n\n    while (!_disposed && session.active && !session.deleted) {\n''',
    '''  Future<bool> _pumpSession(_ParallelSession session) async {\n    if (_disposed ||\n        !session.active ||\n        session.pauseRequested ||\n        session.deleted) {\n      return true;\n    }\n\n    while (!_disposed &&\n        session.active &&\n        !session.pauseRequested &&\n        !session.deleted) {\n''',
)

replace_once(
    parallel,
    '''      for (final part in parts) {\n        if (_disposed) return true;\n        final record = await recordForId(part.task.taskId);\n''',
    '''      for (final part in parts) {\n        if (_disposed || session.pauseRequested || !session.active) return true;\n        final record = await recordForId(part.task.taskId);\n''',
)

replace_once(
    parallel,
    '''      session.active = true;\n      for (final part in unfinished) {\n''',
    '''      session.pauseRequested = false;\n      session.active = true;\n      for (final part in unfinished) {\n''',
)

replace_once(
    parallel,
    '''  bool active = false;\n  bool deleted = false;\n''',
    '''  bool active = false;\n  // Synchronous intent fence: true from the instant pause() is requested until\n  // an explicit start/resume begins a new generation.\n  bool pauseRequested = false;\n  bool deleted = false;\n''',
)

# Background URLSession can legitimately go quiet for more than 100 seconds
# while iOS switches radios, waits for connectivity, or schedules daemon work.
# Keep Android's existing timeout but give iOS a wider idle window so a normal
# background scheduling gap is not turned into TaskStatus.failed.
replace_once(
    service,
    '''            (Config.requestTimeout, const Duration(seconds: 100)),\n''',
    '''            (\n              Config.requestTimeout,\n              Platform.isIOS\n                  ? const Duration(minutes: 10)\n                  : const Duration(seconds: 100),\n            ),\n''',
)

# ---------------------------------------------------------------------------
# 2) Native iOS background retry ownership.
# ---------------------------------------------------------------------------
# background_downloader emits .failed on any URLSession transport error and its
# Dart retry controller cannot run once Flutter is suspended. Intercept only
# transient download errors while the app is actually backgrounded. Keep the
# plugin's original completion callback pending across retries so its Holding
# Queue still owns exactly one logical slot; the final replacement completion
# is the one that settles plugin state.
replace_once(
    native,
    '''  private struct ThroughputPoint {\n    var bytes: Int64\n    var time: CFAbsoluteTime\n  }\n\n  private static let lock = NSLock()\n''',
    '''  private struct ThroughputPoint {\n    var bytes: Int64\n    var time: CFAbsoluteTime\n  }\n\n  private struct BackgroundRetryState {\n    var consecutiveFailures = 0\n    var totalRetries = 0\n    var sawProgressSinceLastFailure = false\n  }\n\n  private static let backgroundRetryMaxConsecutiveFailures = 12\n  private static let backgroundRetryMaxTotalRetries = 128\n  private static let lock = NSLock()\n''',
)

replace_once(
    native,
    '''  private static var lastTaskBridgeTimes: [String: CFAbsoluteTime] = [:]\n  private static let chunkBridgeInterval: CFTimeInterval = 1.0\n''',
    '''  private static var lastTaskBridgeTimes: [String: CFAbsoluteTime] = [:]\n  private static var backgroundRetryStates: [String: BackgroundRetryState] = [:]\n  private static let chunkBridgeInterval: CFTimeInterval = 1.0\n''',
)

replace_once(
    native,
    '''    lastChunkBridgeTimes.removeAll()\n    lastTaskBridgeTimes.removeAll()\n  }\n\n  /// Called from the plugin URLSession delegate after a native completion\n''',
    '''    lastChunkBridgeTimes.removeAll()\n    lastTaskBridgeTimes.removeAll()\n    backgroundRetryStates.removeAll()\n  }\n\n  /// URLSession transport failures that are worth retrying without waking\n  /// Flutter. -999 (cancelled) is deliberately excluded so user pause/cancel\n  /// can never be resurrected by the background recovery layer.\n  static func isRetryableBackgroundTransportErrorCode(_ code: Int) -> Bool {\n    [\n      -997,  // NSURLErrorBackgroundSessionWasDisconnected\n      -1001, // timed out\n      -1003, // cannot find host\n      -1004, // cannot connect to host\n      -1005, // network connection lost\n      -1006, // DNS lookup failed\n      -1009, // not connected to Internet\n      -1018, // international roaming off\n      -1019, // call is active\n      -1020, // data not allowed\n      -1200, // secure connection failed (transient TLS reconnects do occur)\n    ].contains(code)\n  }\n\n  static func backgroundRetryDelay(forConsecutiveFailure failure: Int) -> TimeInterval {\n    switch max(failure, 1) {\n    case 1: return 1\n    case 2: return 2\n    case 3: return 4\n    case 4: return 8\n    case 5: return 16\n    default: return 30\n    }\n  }\n\n  static func canRecreateBackgroundDownload(\n    isMultipartPart: Bool,\n    receivedBytes: Int64,\n    hasResumeData: Bool\n  ) -> Bool {\n    // Reissuing an immutable multipart Range only loses that one child's\n    // volatile prefix. For a full-file transfer, do not silently throw away\n    // already-downloaded bytes unless Apple gave us resumeData.\n    hasResumeData || isMultipartPart || receivedBytes <= 0\n  }\n\n  private static func noteBackgroundRetryProgress(_ task: URLSessionTask) {\n    guard let id = taskId(from: task) else { return }\n    lock.lock()\n    if var retry = backgroundRetryStates[id] {\n      retry.sawProgressSinceLastFailure = true\n      retry.consecutiveFailures = 0\n      backgroundRetryStates[id] = retry\n    }\n    lock.unlock()\n  }\n\n  private static func clearBackgroundRetry(_ task: URLSessionTask) {\n    guard let id = taskId(from: task) else { return }\n    lock.lock()\n    backgroundRetryStates[id] = nil\n    lock.unlock()\n  }\n\n  /// Returns true when this completion was consumed by a replacement native\n  /// URLSessionDownloadTask. The caller must then skip the plugin's original\n  /// didComplete callback; otherwise background_downloader would emit\n  /// `Task failed`, free its HoldingQueue slot, and leave the replacement as an\n  /// unowned duplicate. The eventual successful/exhausted replacement is what\n  /// settles the original plugin task.\n  static func retryBackgroundTransferIfNeeded(\n    session: URLSession,\n    task: URLSessionTask,\n    error: Error\n  ) -> Bool {\n    guard task is URLSessionDownloadTask,\n          !isAppInForeground(),\n          let taskId = taskId(from: task),\n          !taskId.isEmpty\n    else {\n      return false\n    }\n\n    let nsError = error as NSError\n    guard nsError.domain == NSURLErrorDomain,\n          isRetryableBackgroundTransportErrorCode(nsError.code)\n    else {\n      return false\n    }\n\n    let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data\n    let hasResumeData = !(resumeData?.isEmpty ?? true)\n    let multipartPart = isDownloadPart(task)\n    guard canRecreateBackgroundDownload(\n      isMultipartPart: multipartPart,\n      receivedBytes: task.countOfBytesReceived,\n      hasResumeData: hasResumeData\n    ) else {\n      return false\n    }\n\n    let request = task.currentRequest ?? task.originalRequest\n    if !hasResumeData && request == nil { return false }\n\n    let consecutive: Int\n    lock.lock()\n    var retry = backgroundRetryStates[taskId] ?? BackgroundRetryState()\n    if retry.sawProgressSinceLastFailure {\n      retry.consecutiveFailures = 0\n    }\n    retry.consecutiveFailures += 1\n    retry.totalRetries += 1\n    retry.sawProgressSinceLastFailure = false\n    consecutive = retry.consecutiveFailures\n    if retry.consecutiveFailures > backgroundRetryMaxConsecutiveFailures ||\n        retry.totalRetries > backgroundRetryMaxTotalRetries {\n      backgroundRetryStates[taskId] = nil\n      lock.unlock()\n      DownloadNativeDiagnosticLog.record(\n        "background.retry.exhausted",\n        task: task,\n        error: error\n      )\n      return false\n    }\n    backgroundRetryStates[taskId] = retry\n    lock.unlock()\n\n    let replacement: URLSessionDownloadTask\n    if let resumeData, !resumeData.isEmpty {\n      replacement = session.downloadTask(withResumeData: resumeData)\n    } else {\n      replacement = session.downloadTask(with: request!)\n    }\n    replacement.taskDescription = task.taskDescription\n    replacement.priority = task.priority\n    replacement.earliestBeginDate = Date().addingTimeInterval(\n      backgroundRetryDelay(forConsecutiveFailure: consecutive)\n    )\n\n    DownloadNativeDiagnosticLog.record(\n      hasResumeData ? "background.retry.resumeData" : "background.retry.rangeRestart",\n      task: task,\n      error: error\n    )\n    replacement.resume()\n    return true\n  }\n\n  /// Called from the plugin URLSession delegate after a native completion\n''',
)

# Mark forward progress so the backoff resets. A flaky but progressing server
# can therefore finish a large file instead of burning through a fixed retry
# count simply because the app remained in the background for a long time.
replace_once(
    native,
    '''      DownloadNativeWaitingQueue.handleBytesWritten(\n        downloadTask,\n        totalWritten: totalWritten,\n        totalExpected: totalExpected\n      )\n''',
    '''      DownloadNativeWaitingQueue.noteBackgroundRetryProgress(downloadTask)\n      DownloadNativeWaitingQueue.handleBytesWritten(\n        downloadTask,\n        totalWritten: totalWritten,\n        totalExpected: totalExpected\n      )\n''',
)

# Successful didFinish is the terminal point for a URLSessionDownloadTask.
replace_once(
    native,
    '''      DownloadNativeDiagnosticLog.record("file.received", task: downloadTask)\n      // Original must run first so the plugin can move the temp file.\n''',
    '''      DownloadNativeDiagnosticLog.record("file.received", task: downloadTask)\n      DownloadNativeWaitingQueue.clearBackgroundRetry(downloadTask)\n      // Original must run first so the plugin can move the temp file.\n''',
)

# The retry check MUST happen before background_downloader's original callback.
# That callback emits the user-visible Task failed notification and releases the
# HoldingQueue slot. Consuming a transient error first keeps native ownership
# coherent while Flutter is asleep.
replace_once(
    native,
    '''      DownloadNativeDiagnosticLog.record("complete", task: task, error: error)\n      // The plugin owns URLSession bookkeeping, retries, resume data and its\n      // holding queue. Let it settle the failed task before AnimeWitcher frees\n      // the logical episode slot and promotes another one.\n      if let original = DownloadUrlSessionHook.originalComplete {\n''',
    '''      DownloadNativeDiagnosticLog.record("complete", task: task, error: error)\n      if let error, DownloadNativeWaitingQueue.retryBackgroundTransferIfNeeded(\n        session: session,\n        task: task,\n        error: error\n      ) {\n        return\n      }\n\n      // Non-transient/exhausted failures and normal success still belong to\n      // background_downloader. Only those reach the original callback.\n      if let original = DownloadUrlSessionHook.originalComplete {\n''',
)

# ---------------------------------------------------------------------------
# 3) Regression lock: source-level assertions run in Flutter CI on every OS.
# ---------------------------------------------------------------------------
text = read(runtime_test)
insert = r'''

    test('iOS background transport failures retry before plugin Task failed', () {
      final swift = File('ios/Runner/DownloadNativeWaitingQueue.swift')
          .readAsStringSync();
      final hookStart = swift.indexOf('private static func hookComplete(');
      final hookEnd = swift.indexOf('private static func hookFinishDownload(', hookStart);
      expect(hookStart, greaterThanOrEqualTo(0));
      expect(hookEnd, greaterThan(hookStart));
      final hook = swift.substring(hookStart, hookEnd);
      expect(hook, contains('retryBackgroundTransferIfNeeded('));
      expect(hook, contains('return'));
      expect(
        hook.indexOf('retryBackgroundTransferIfNeeded('),
        lessThan(hook.indexOf('originalComplete')),
      );
      expect(swift, contains('background.retry.resumeData'));
      expect(swift, contains('background.retry.rangeRestart'));
      expect(swift, contains('replacement.earliestBeginDate'));
      expect(swift, contains('-1005, // network connection lost'));
      expect(swift, contains('-1009, // not connected to Internet'));
      expect(swift, isNot(contains('-999,  //')));

      final service = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      expect(service, contains('Platform.isIOS'));
      expect(service, contains('const Duration(minutes: 10)'));
    });

    test('pause intent fences a queued multipart slow-start pump', () {
      final source = File('lib/core/services/persistent_parallel_download.dart')
          .readAsStringSync();
      expect(source, contains('session.pauseRequested = true;'));
      expect(source, contains('session.pauseRequested = false;'));
      expect(source, contains('session.pauseRequested ||'));
      expect(source, contains('!session.pauseRequested &&'));
    });
'''
marker = '  });\n}\n'
pos = text.rfind(marker)
if pos < 0:
    raise SystemExit('runtime stability group closing marker not found')
text = text[:pos] + insert + text[pos:]
write(runtime_test, text)

print('Applied iOS background retry ownership, wider timeout, and pause intent fencing.')
