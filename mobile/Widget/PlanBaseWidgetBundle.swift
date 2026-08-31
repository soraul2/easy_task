import SwiftUI
import WidgetKit

@main
struct PlanBaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanBaseCalendarWidget()
        PlanBasePlannerWidget()
#if os(iOS)
        PlanBaseLockScreenWidget()
        PlanBaseTaskLiveActivity()
#endif
    }
}
