import SwiftUI
import WidgetKit

@main
struct SkyStreamDownloadActivityBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    DownloadLiveActivityWidget()
  }
}
