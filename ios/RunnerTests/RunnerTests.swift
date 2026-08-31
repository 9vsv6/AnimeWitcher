import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  override func tearDown() {
    DownloadNativeWaitingQueue.resetForTests()
    super.tearDown()
  }

  func testPersistRequiresFullWaiterPayload() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: [
      "maxConcurrent": 1,
      "transferringTaskIds": ["ep1"],
      "pausedTaskIds": [],
      "waiters": [[
        "taskId": "ep2",
        "taskJson": "",
        "url": "https://cdn.test/ep2.mp4",
        "filename": "ep2.mp4",
      ]],
    ])
    XCTAssertTrue(DownloadNativeWaitingQueue.load().waiters.isEmpty)
  }

  func testPersistStoresUrlHeadersFilenameAndTaskJson() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: ep1TransferringEp2Waiting())
    let state = DownloadNativeWaitingQueue.load()
    XCTAssertEqual(state.maxConcurrent, 1)
    XCTAssertEqual(state.transferringTaskIds, ["ep1"])
    XCTAssertEqual(state.waiters.map(\.taskId), ["ep2"])
    XCTAssertEqual(state.waiters[0].url, "https://127.0.0.1:1/ep2.mp4")
    XCTAssertEqual(state.waiters[0].filename, "الحلقة 2.mp4")
    XCTAssertEqual(state.waiters[0].headers["Authorization"], "Bearer x")
    XCTAssertTrue(state.waiters[0].taskJson.contains("ep2"))
  }

  func testUserPausedWaiterIsNotPromoted() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: [
      "maxConcurrent": 1,
      "transferringTaskIds": ["ep1"],
      "pausedTaskIds": ["ep2"],
      "waiters": [ep2Waiter()],
    ])
    XCTAssertTrue(DownloadNativeWaitingQueue.load().waiters.isEmpty)

    let session = URLSession(configuration: .ephemeral)
    let ep1 = session.downloadTask(with: URL(string: "https://127.0.0.1:1/ep1.mp4")!)
    ep1.taskDescription = "{\"taskId\":\"ep1\"}"
    DownloadNativeWaitingQueue.handlePluginTaskCompleted(
      session: session,
      task: ep1,
      error: nil
    )
    let state = DownloadNativeWaitingQueue.load()
    XCTAssertFalse(state.transferringTaskIds.contains("ep2"))
    XCTAssertEqual(state.pausedTaskIds, ["ep2"])
  }

  func testNativeCompletionStartsNextWaiterBeforeDartWakes() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: ep1TransferringEp2Waiting())

    let session = URLSession(configuration: .ephemeral)
    let ep1 = session.downloadTask(with: URL(string: "https://127.0.0.1:1/ep1.mp4")!)
    ep1.taskDescription = "{\"taskId\":\"ep1\"}"
    DownloadNativeWaitingQueue.handlePluginTaskCompleted(
      session: session,
      task: ep1,
      error: nil
    )

    let state = DownloadNativeWaitingQueue.load()
    XCTAssertEqual(state.transferringTaskIds, ["ep2"])
    XCTAssertTrue(state.waiters.isEmpty)
    XCTAssertTrue(state.completedTaskIds.contains("ep1"))
  }

  func testStaleDartSnapshotCannotUnstartANativePromotion() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: ep1TransferringEp2Waiting())

    let session = URLSession(configuration: .ephemeral)
    let ep1 = session.downloadTask(with: URL(string: "https://127.0.0.1:1/ep1.mp4")!)
    ep1.taskDescription = "{\"taskId\":\"ep1\"}"
    DownloadNativeWaitingQueue.handlePluginTaskCompleted(
      session: session,
      task: ep1,
      error: nil
    )

    DownloadNativeWaitingQueue.persist(from: [
      "maxConcurrent": 1,
      "transferringTaskIds": [],
      "pausedTaskIds": [],
      "waiters": [ep2Waiter()],
    ])

    let state = DownloadNativeWaitingQueue.load()
    XCTAssertEqual(state.transferringTaskIds, ["ep2"])
    XCTAssertTrue(state.waiters.isEmpty)
  }

  private func ep1TransferringEp2Waiting() -> [String: Any] {
    [
      "maxConcurrent": 1,
      "transferringTaskIds": ["ep1"],
      "pausedTaskIds": [],
      "waiters": [ep2Waiter()],
    ]
  }

  func testPersistRewritesWaiterOrderFromDart() {
    DownloadNativeWaitingQueue.resetForTests()
    DownloadNativeWaitingQueue.persist(from: [
      "maxConcurrent": 1,
      "transferringTaskIds": ["ep1"],
      "pausedTaskIds": [],
      "waiters": [ep2Waiter(), ep3Waiter()],
      "sessionTaskIds": ["ep1", "ep2", "ep3"],
    ])
    XCTAssertEqual(
      DownloadNativeWaitingQueue.load().waiters.map(\.taskId),
      ["ep2", "ep3"]
    )

    DownloadNativeWaitingQueue.persist(from: [
      "maxConcurrent": 1,
      "transferringTaskIds": ["ep1"],
      "pausedTaskIds": [],
      "waiters": [ep3Waiter(), ep2Waiter()],
      "sessionTaskIds": ["ep3", "ep1", "ep2"],
      "sessionCurrentIndex": 2,
    ])
    let state = DownloadNativeWaitingQueue.load()
    XCTAssertEqual(state.waiters.map(\.taskId), ["ep3", "ep2"])
    XCTAssertEqual(state.sessionTaskIds.first, "ep3")
    XCTAssertEqual(state.overlayCurrentIndex(runningTaskId: "ep1"), 2)
  }

  private func ep3Waiter() -> [String: Any] {
    [
      "taskId": "ep3",
      "taskJson": "{\"taskId\":\"ep3\",\"url\":\"https://127.0.0.1:1/ep3.mp4\",\"filename\":\"الحلقة 3.mp4\"}",
      "url": "https://127.0.0.1:1/ep3.mp4",
      "filename": "الحلقة 3.mp4",
      "displayName": "الحلقة 3.mp4",
      "headers": ["Authorization": "Bearer x"],
      "directory": "AnimeWitcher/Downloads/Show",
      "httpRequestMethod": "GET",
      "group": "downloads",
    ]
  }
    [
      "taskId": "ep2",
      "taskJson": "{\"taskId\":\"ep2\",\"url\":\"https://127.0.0.1:1/ep2.mp4\",\"filename\":\"الحلقة 2.mp4\"}",
      "url": "https://127.0.0.1:1/ep2.mp4",
      "filename": "الحلقة 2.mp4",
      "displayName": "الحلقة 2.mp4",
      "headers": ["Authorization": "Bearer x"],
      "directory": "AnimeWitcher/Downloads/Show",
      "httpRequestMethod": "GET",
      "group": "downloads",
    ]
  }
}
