#if os(iOS)
import PlanBaseCore
import SwiftUI

struct MobileTemplateLibrarySheet: View {
    var selectedDate: Date
    var existingTasks: [TodoTask]
    var onApplied: (String) -> Void

    var body: some View {
        TemplateLibraryView(selectedDate: selectedDate, currentBoardTasks: existingTasks, onApplied: onApplied)
    }
}
#endif
