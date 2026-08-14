import SwiftUI
import WidgetKit

@main
struct PlanBaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanBaseCalendarWidget()
#if os(iOS)
        PlanBaseLockScreenWidget()
#endif
    }
}
