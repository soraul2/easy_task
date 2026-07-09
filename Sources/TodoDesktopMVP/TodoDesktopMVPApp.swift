import SwiftData
import SwiftUI
import EasyTaskCore

@main
struct TodoDesktopMVPApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try EasyTaskContainerFactory.makePersistent()
        } catch {
            fatalError("EasyTask 저장소를 열 수 없습니다: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .frame(minWidth: 900, minHeight: 680)
        }
        .modelContainer(modelContainer)
    }
}
