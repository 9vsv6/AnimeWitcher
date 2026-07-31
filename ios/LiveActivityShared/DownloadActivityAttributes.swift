#if os(iOS)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct DownloadActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var progress: Double
    var speedMBps: Double
    var status: String
  }

  var taskId: String
  var animeTitle: String
  var episodeTitle: String
}
#endif
