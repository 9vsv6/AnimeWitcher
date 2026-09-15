import Foundation

/// 9.6.1 emits supported status synchronously inside the delegate invocation.
/// Task.taskId is NOT an execution ID; no observation survives that invocation.
final class DownloadTerminalObservation {
  private final class Frame {
    let execution: AnyObject
    let taskId: String
    var succeeded: Bool?
    init(execution: AnyObject, taskId: String) {
      self.execution = execution
      self.taskId = taskId
    }
  }
  private let key = "animewitcher.download.terminal.\(UUID().uuidString)"

  func capture(execution: AnyObject, taskId: String, body: () -> Void) -> Bool? {
    let dictionary = Thread.current.threadDictionary
    let previous = dictionary[key]
    let frame = Frame(execution: execution, taskId: taskId)
    dictionary[key] = frame
    defer {
      if let previous { dictionary[key] = previous }
      else { dictionary.removeObject(forKey: key) }
    }
    body()
    return frame.succeeded
  }

  func record(taskId: String, succeeded: Bool) {
    guard let frame = Thread.current.threadDictionary[key] as? Frame,
          frame.taskId == taskId else { return }
    frame.succeeded = succeeded
  }
}

/// Attached to the concrete URLSessionTask, never the reusable plugin taskId.
final class DownloadExecutionCallbacks {
  private let lock = NSLock()
  private var retired = false
  private var finished = false
  private var completed = false

  func retire() {
    lock.lock()
    defer { lock.unlock() }
    retired = true
  }

  func beginFinish() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !retired, !finished, !completed else { return false }
    finished = true
    return true
  }

  func beginComplete() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !retired, !completed else { return false }
    completed = true
    return true
  }
}

/// Callers serialize installation. A failed preflight changes no IMP and
/// remains retryable; success cannot wrap its own implementations.
final class DownloadHookInstallation {
  private(set) var isInstalled = false

  func install(version: String?, available: [Bool], apply: () -> Void) -> Bool {
    if isInstalled { return true }
    guard version == "9.6.1", available.count == 3,
          available.allSatisfy({ $0 }) else { return false }
    apply()
    isInstalled = true
    return true
  }
}
