import SwiftUI
import WidgetKit

@main
struct PlanBaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanBaseCalendarWidget()
        PlanBaseLockScreenWidget()
    }
}
