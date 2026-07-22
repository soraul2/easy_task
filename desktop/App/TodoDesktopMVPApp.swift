import SwiftData
import SwiftUI
import EasyTaskCore

@main
@MainActor
struct TodoDesktopMVPApp: App {
    @State private var persistenceState: PersistenceState

    init() {
        _persistenceState = State(initialValue: Self.openPersistentStore())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch persistenceState {
                case .ready(let modelContainer):
                    Group {
#if DEBUG
                        if Self.isCloudKitProbeRequested {
                            Color.clear
                        } else {
                            AppRootView()
                        }
#else
                        AppRootView()
#endif
                    }
                    .modelContainer(modelContainer)
                case .failed(let details):
                    ContentUnavailableView {
                        Label(
                            "저장소를 열 수 없습니다",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    } description: {
                        VStack(spacing: 8) {
                            Text("기존 저장소는 그대로 유지됩니다. 잠시 후 다시 시도해 주세요.")
                            Text(details)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    } actions: {
                        Button {
                            persistenceState = Self.openPersistentStore()
                        } label: {
                            Label("다시 시도", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 680)
        }
    }

    private static func openPersistentStore() -> PersistenceState {
        do {
#if DEBUG
            _ = try EasyTaskContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested()
#endif
            let modelContainer = try EasyTaskContainerFactory.makeAppPersistent()
#if DEBUG
            startCloudKitProbeIfRequested(modelContainer: modelContainer)
#endif
            return .ready(modelContainer)
        } catch {
            print("EasyTask persistent store startup failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

#if DEBUG
    private static var isCloudKitProbeRequested: Bool {
        CloudKitConvergenceProbe.isProbeInvocation(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func startCloudKitProbeIfRequested(modelContainer: ModelContainer) {
        guard isCloudKitProbeRequested else { return }

        Swift.Task { @MainActor in
            _ = await CloudKitConvergenceProbe.runIfRequested(
                context: modelContainer.mainContext
            )
        }
    }
#endif
}

private enum PersistenceState {
    case ready(ModelContainer)
    case failed(String)
}
