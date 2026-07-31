import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct DownloadLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(
      for: DownloadActivityAttributes.self
    ) { context in
      DownloadLockScreenView(context: context)
        .activityBackgroundTint(
          Color(red: 0.055, green: 0.063, blue: 0.082)
        )
        .activitySystemActionForegroundColor(.blue)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: statusIcon(context.state.status))
            .font(.title2)
            .foregroundStyle(.blue)
        }

        DynamicIslandExpandedRegion(.trailing) {
          Text(percentText(context.state.progress))
            .font(.headline.monospacedDigit())
        }

        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(context.attributes.animeTitle)
              .font(.headline)
              .lineLimit(1)
            Text(context.attributes.episodeTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 6) {
            ProgressView(value: normalized(context.state.progress))
              .tint(.blue)
            HStack {
              Text(statusText(context.state))
                .font(.caption.monospacedDigit())
              Spacer()
              Text(percentText(context.state.progress))
                .font(.caption.bold().monospacedDigit())
            }
          }
        }
      } compactLeading: {
        Image(systemName: statusIcon(context.state.status))
          .foregroundStyle(.blue)
      } compactTrailing: {
        Text(percentText(context.state.progress))
          .font(.caption2.bold().monospacedDigit())
      } minimal: {
        Image(systemName: "arrow.down")
          .foregroundStyle(.blue)
      }
      .keylineTint(.blue)
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct DownloadLockScreenView: View {
  let context: ActivityViewContext<DownloadActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Image(systemName: statusIcon(context.state.status))
          .font(.title3)
          .foregroundStyle(.blue)

        Text(context.attributes.animeTitle)
          .font(.headline)
          .lineLimit(1)

        Spacer(minLength: 8)

        Text(percentText(context.state.progress))
          .font(.headline.monospacedDigit())
      }

      Text(context.attributes.episodeTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      ProgressView(value: normalized(context.state.progress))
        .tint(.blue)

      HStack {
        Text(statusText(context.state))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)

        Spacer()

        Text(percentText(context.state.progress))
          .font(.caption.bold().monospacedDigit())
      }
    }
    .padding()
  }
}

@available(iOSApplicationExtension 16.1, *)
private func normalized(_ progress: Double) -> Double {
  min(max(progress, 0.0), 1.0)
}

@available(iOSApplicationExtension 16.1, *)
private func percentText(_ progress: Double) -> String {
  "\(Int((normalized(progress) * 100.0).rounded()))%"
}

@available(iOSApplicationExtension 16.1, *)
private func speedText(_ speedMBps: Double) -> String {
  guard speedMBps > 0 else {
    return "Calculating…"
  }

  if speedMBps < 1 {
    return String(format: "%.0f KB/s", speedMBps * 1024.0)
  }

  return String(format: "%.1f MB/s", speedMBps)
}

@available(iOSApplicationExtension 16.1, *)
private func statusText(
  _ state: DownloadActivityAttributes.ContentState
) -> String {
  switch state.status {
  case "paused":
    return "Paused"
  case "completed":
    return "Download complete"
  case "failed":
    return "Download failed"
  case "canceled":
    return "Canceled"
  default:
    return speedText(state.speedMBps)
  }
}

@available(iOSApplicationExtension 16.1, *)
private func statusIcon(_ status: String) -> String {
  switch status {
  case "paused":
    return "pause.circle.fill"
  case "completed":
    return "checkmark.circle.fill"
  case "failed":
    return "exclamationmark.triangle.fill"
  case "canceled":
    return "xmark.circle.fill"
  default:
    return "arrow.down.circle.fill"
  }
}
