from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


native = 'ios/Runner/DownloadNativeWaitingQueue.swift'
runtime_test = 'test/core/services/download_runtime_stability_review_test.dart'

# Multipart children are real background URLSession downloads, but the previous
# bridge only forwarded their bytes to Dart. Once Flutter is suspended the
# BGContinuedProcessingTask therefore stopped receiving progress and iOS could
# classify the task as stalled/expired. Aggregate child byte samples natively
# into the logical parent and keep the system task moving without depending on
# the Dart isolate.
replace_once(
    native,
    '''  private static var backgroundRetryStates: [String: BackgroundRetryState] = [:]\n  private static let chunkBridgeInterval: CFTimeInterval = 1.0\n''',
    '''  private static var backgroundRetryStates: [String: BackgroundRetryState] = [:]\n  private static var multipartChildSamples: [String: [String: RunningSample]] = [:]\n  private static var lastMultipartOverlayTimes: [String: CFAbsoluteTime] = [:]\n  private static let chunkBridgeInterval: CFTimeInterval = 1.0\n''',
)

replace_once(
    native,
    '''    lastTaskBridgeTimes.removeAll()\n    backgroundRetryStates.removeAll()\n  }\n''',
    '''    lastTaskBridgeTimes.removeAll()\n    backgroundRetryStates.removeAll()\n    multipartChildSamples.removeAll()\n    lastMultipartOverlayTimes.removeAll()\n  }\n''',
)

# Dart remains authoritative for which logical parents occupy episode slots.
# Discard native aggregate samples as soon as a parent leaves that transferring
# set (pause/cancel/complete), so a later resume cannot inherit stale bytes.
replace_once(
    native,
    '''    let transferringSet = Set(transferring)\n    let completedSet = Set(completed)\n''',
    '''    let transferringSet = Set(transferring)\n    multipartChildSamples = multipartChildSamples.filter { transferringSet.contains($0.key) }\n    lastMultipartOverlayTimes = lastMultipartOverlayTimes.filter { transferringSet.contains($0.key) }\n    let completedSet = Set(completed)\n''',
)

old = '''  private static func postMultipartChunkUpdate(\n    _ task: URLSessionTask,\n    totalWritten: Int64,\n    totalExpected: Int64,\n    completed: Bool\n  ) {\n    guard isDownloadPart(task),\n          let childId = taskId(from: task),\n          let parentId = parentTaskId(from: task)\n    else {\n      return\n    }\n\n    let now = CFAbsoluteTimeGetCurrent()\n    lock.lock()\n    if !completed,\n       let lastBridge = lastChunkBridgeTimes[childId],\n       now - lastBridge < chunkBridgeInterval {\n      lock.unlock()\n      return\n    }\n    if completed {\n      lastChunkBridgeTimes[childId] = nil\n    } else {\n      lastChunkBridgeTimes[childId] = now\n    }\n    let speed = rollingSpeedLocked(\n      windows: &chunkSpeedWindows,\n      taskId: childId,\n      totalWritten: totalWritten,\n      now: now,\n      completed: completed\n    )\n    lock.unlock()\n\n    var values: [String: Any] = [\n      "parentTaskId": parentId,\n      "chunkTaskId": childId,\n      "completed": completed,\n    ]\n    if totalWritten >= 0 {\n      values["writtenBytes"] = totalWritten\n    }\n    if totalExpected > 0 {\n      values["expectedBytes"] = totalExpected\n      values["progress"] = completed\n        ? 1.0\n        : min(max(Double(totalWritten) / Double(totalExpected), 0), 1)\n    } else if completed {\n      values["progress"] = 1.0\n    }\n    if speed > 0 {\n      values["speedBytesPerSecond"] = speed\n    }\n\n    NotificationCenter.default.post(\n      name: Notification.Name("AnimeWitcherBackgroundDownloaderChunkUpdate"),\n      object: nil,\n      userInfo: values\n    )\n  }\n'''

new = '''  private static func postMultipartChunkUpdate(\n    _ task: URLSessionTask,\n    totalWritten: Int64,\n    totalExpected: Int64,\n    completed: Bool\n  ) {\n    guard isDownloadPart(task),\n          let childId = taskId(from: task),\n          let parentId = parentTaskId(from: task)\n    else {\n      return\n    }\n\n    let now = CFAbsoluteTimeGetCurrent()\n    let taskJson = task.taskDescription?\n      .components(separatedBy: "***<<<|>>>***").first ?? ""\n    let childDirectory = stringFromTaskJson(taskJson, key: "directory")\n    let partsComponent = URL(fileURLWithPath: childDirectory).lastPathComponent\n    let inferredParentName = partsComponent.hasSuffix(".parts")\n      ? String(partsComponent.dropLast(".parts".count))\n      : parentId\n\n    lock.lock()\n    if !completed,\n       let lastBridge = lastChunkBridgeTimes[childId],\n       now - lastBridge < chunkBridgeInterval {\n      lock.unlock()\n      return\n    }\n    if completed {\n      lastChunkBridgeTimes[childId] = nil\n    } else {\n      lastChunkBridgeTimes[childId] = now\n    }\n    let speed = rollingSpeedLocked(\n      windows: &chunkSpeedWindows,\n      taskId: childId,\n      totalWritten: totalWritten,\n      now: now,\n      completed: completed\n    )\n\n    var state = loadLocked()\n    var children = multipartChildSamples[parentId] ?? [:]\n    var sample = children[childId] ?? RunningSample(\n      written: 0,\n      expected: -1,\n      speed: 0,\n      displayName: inferredParentName\n    )\n    // A URLSession retry can reset its local byte counter. Keep native overlay\n    // progress monotonic while the replacement catches up; this sample is UI\n    // lease telemetry only and is never used as durable resume evidence.\n    sample.written = max(sample.written, max(totalWritten, 0))\n    if totalExpected > 0 {\n      sample.expected = max(sample.expected, totalExpected)\n      if completed { sample.written = sample.expected }\n    }\n    sample.speed = completed ? 0 : max(speed, 0)\n    if sample.displayName.isEmpty { sample.displayName = inferredParentName }\n    children[childId] = sample\n    multipartChildSamples[parentId] = children\n\n    let aggregateWritten = children.values.reduce(Int64(0)) { $0 + max($1.written, 0) }\n    let sampledExpected = children.values.reduce(Int64(0)) {\n      $0 + ($1.expected > 0 ? $1.expected : 0)\n    }\n    let knownParentTotal = state.sessionCurrentTaskId == parentId && state.sessionTotalBytes > 0\n      ? state.sessionTotalBytes\n      : -1\n    let aggregateExpected = knownParentTotal > 0 ? knownParentTotal : sampledExpected\n    let aggregateSpeed = children.values.reduce(0.0) {\n      $0 + ($1.speed.isFinite && $1.speed > 0 ? $1.speed : 0)\n    }\n    let parentName = state.sessionCurrentTaskId == parentId && !state.sessionDisplayName.isEmpty\n      ? state.sessionDisplayName\n      : inferredParentName\n\n    if state.transferringTaskIds.contains(parentId) {\n      state.runningSamples[parentId] = RunningSample(\n        written: min(aggregateWritten, aggregateExpected > 0 ? aggregateExpected : aggregateWritten),\n        expected: aggregateExpected,\n        speed: aggregateSpeed,\n        displayName: parentName\n      )\n    }\n    let presentation = overlayPresentation(\n      from: state,\n      fallbackId: parentId,\n      fallbackName: parentName\n    )\n    let lastOverlay = lastMultipartOverlayTimes[parentId] ?? 0\n    let shouldUpdateNativeOverlay = completed || now - lastOverlay >= chunkBridgeInterval\n    if shouldUpdateNativeOverlay { lastMultipartOverlayTimes[parentId] = now }\n    saveLocked(state)\n    lock.unlock()\n\n    var values: [String: Any] = [\n      "parentTaskId": parentId,\n      "chunkTaskId": childId,\n      "completed": completed,\n    ]\n    if totalWritten >= 0 {\n      values["writtenBytes"] = totalWritten\n    }\n    if totalExpected > 0 {\n      values["expectedBytes"] = totalExpected\n      values["progress"] = completed\n        ? 1.0\n        : min(max(Double(totalWritten) / Double(totalExpected), 0), 1)\n    } else if completed {\n      values["progress"] = 1.0\n    }\n    if speed > 0 {\n      values["speedBytesPerSecond"] = speed\n    }\n\n    NotificationCenter.default.post(\n      name: Notification.Name("AnimeWitcherBackgroundDownloaderChunkUpdate"),\n      object: nil,\n      userInfo: values\n    )\n\n    // Dart owns the overlay while foreground. When it is suspended, keep the\n    // same BGContinuedProcessingTask alive from URLSession's native bytes so\n    // iOS sees real progress instead of an apparently stalled long task.\n    if shouldUpdateNativeOverlay && !isAppInForeground() {\n      upsertSessionOverlay(\n        currentTaskId: presentation.currentTaskId,\n        displayName: presentation.displayName,\n        progress: presentation.progress,\n        totalBytes: presentation.totalBytes,\n        transferredBytes: presentation.transferredBytes,\n        speedBytesPerSecond: presentation.speedBytesPerSecond\n      )\n    }\n  }\n'''
replace_once(native, old, new)

text = read(runtime_test)
insert = r'''

    test('multipart native bytes keep iOS continued-processing progress alive', () {
      final swift = File('ios/Runner/DownloadNativeWaitingQueue.swift')
          .readAsStringSync();
      final start = swift.indexOf('private static func postMultipartChunkUpdate(');
      final end = swift.indexOf('static func handleBytesWritten(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final section = swift.substring(start, end);
      expect(section, contains('multipartChildSamples[parentId]'));
      expect(section, contains('state.runningSamples[parentId]'));
      expect(section, contains('overlayPresentation('));
      expect(section, contains('shouldUpdateNativeOverlay'));
      expect(section, contains('!isAppInForeground()'));
      expect(section, contains('upsertSessionOverlay('));
      expect(section, contains('UI lease telemetry only'));
    });
'''
marker = '  });\n}\n'
pos = text.rfind(marker)
if pos < 0:
    raise SystemExit('runtime stability group closing marker not found')
text = text[:pos] + insert + text[pos:]
write(runtime_test, text)

print('Applied native multipart aggregation for iOS background progress.')
