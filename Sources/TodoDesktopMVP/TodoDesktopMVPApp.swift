import SwiftData
import SwiftUI
import EasyTaskCore

@main
struct TodoDesktopMVPApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .frame(minWidth: 900, minHeight: 680)
        }
        .modelContainer(for: [
            Task.self,
            CalendarEvent.self,
            TaskTemplate.self,
            TaskTemplateItem.self,
            DailyReview.self,
            DiaryBlock.self
        ])
    }
}
