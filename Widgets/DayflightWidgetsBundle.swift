import SwiftUI
import WidgetKit

@main
struct DayflightWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowWidget()
        TaskLiveActivityWidget()
    }
}
