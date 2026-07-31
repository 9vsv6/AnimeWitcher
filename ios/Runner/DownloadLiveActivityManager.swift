#if os(iOS)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class DownloadLiveActivityManager {
  static let shared = DownloadLiveActivityManager()

  private init() {}

  private func activities(
    for taskId: String
  ) -> [Activity<DownloadActivityAttributes>] {
    Activity<DownloadActivityAttributes>.activities.filter {
      $0.attributes.taskId == taskId
    }
  }

  func start(
    taskId: String,
    animeTitle: String,
    episodeTitle: String
  ) async throws -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return nil
    }

    // Starting the same task twice must be idempotent. Returning the
    // existing activity is enough; the Dart side sends the latest progress
    // immediately after start when resuming an existing download.
    //
    // Do not read Activity.content here. That property is iOS 16.2+, while
    // SkyStream intentionally supports Live Activities from iOS 16.1.
    if let existing = activities(for: taskId).first {
      return existing.id
    }

    let attributes = DownloadActivityAttributes(
      taskId: taskId,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle
    )
    let state = DownloadActivityAttributes.ContentState(
      progress: 0.0,
      speedMBps: 0.0,
      status: "downloading"
    )

    let activity: Activity<DownloadActivityAttributes>
    if #available(iOS 16.2, *) {
      activity = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil
      )
    } else {
      activity = try Activity.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
    }

    return activity.id
  }

  func update(
    taskId: String,
    progress: Double,
    speedMBps: Double,
    status: String
  ) async {
    let state = DownloadActivityAttributes.ContentState(
      progress: min(max(progress, 0.0), 1.0),
      speedMBps: max(speedMBps, 0.0),
      status: status
    )

    for activity in activities(for: taskId) {
      if #available(iOS 16.2, *) {
        await activity.update(
          ActivityContent(state: state, staleDate: nil)
        )
      } else {
        await activity.update(using: state)
      }
    }
  }

  func end(
    taskId: String,
    progress: Double,
    speedMBps: Double,
    status: String
  ) async {
    let state = DownloadActivityAttributes.ContentState(
      progress: min(max(progress, 0.0), 1.0),
      speedMBps: max(speedMBps, 0.0),
      status: status
    )
    let dismissalPolicy: ActivityUIDismissalPolicy =
      status == "completed"
      ? .after(Date().addingTimeInterval(8))
      : .immediate

    for activity in activities(for: taskId) {
      if #available(iOS 16.2, *) {
        await activity.end(
          ActivityContent(state: state, staleDate: nil),
          dismissalPolicy: dismissalPolicy
        )
      } else {
        await activity.end(
          using: state,
          dismissalPolicy: dismissalPolicy
        )
      }
    }
  }
}
#endif
