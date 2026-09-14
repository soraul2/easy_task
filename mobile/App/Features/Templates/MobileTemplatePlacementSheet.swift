#if os(iOS)
import PlanBaseCore
import SwiftUI

struct MobileTemplatePlacementSheet: View {
    var onStartPlacement: (TaskTemplate, [TemplateTaskDraft]) -> Void

    var body: some View {
        TemplateLibraryView(onChooseDates: onStartPlacement)
    }
}
#endif
