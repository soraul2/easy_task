import SwiftUI
import PlanBaseCore

struct TemplatePlacementSheet: View {
    var onSelect: (TaskTemplate, [TemplateTaskDraft]) -> Void

    var body: some View {
        TemplateLibraryView(onChooseDates: onSelect)
    }
}
