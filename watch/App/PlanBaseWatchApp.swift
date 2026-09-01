#if os(watchOS)
import PlanBaseCore
import SwiftData
import SwiftUI

@main
struct PlanBaseWatchApp: App {
    @State private var persistenceState: WatchPersistenceState

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
    }

    var body: some Scene {
        WindowGroup {
            switch persistenceState {
            case .ready(let modelContainer):
                WatchRootView()
                    .modelContainer(modelContainer)
            case .failed(let details):
                WatchPersistenceRecoveryView(details: details) {
                    persistenceState = Self.makePersistenceState()
                }
            }
        }
    }

    @MainActor
    private static func makePersistenceState() -> WatchPersistenceState {
        do {
            return .ready(try PlanBaseContainerFactory.makeAppPersistent())
        } catch {
            print("PlanBase Watch 저장소를 열 수 없습니다: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
}

private enum WatchPersistenceState {
    case ready(ModelContainer)
    case failed(String)
}

private struct WatchPersistenceRecoveryView: View {
    let details: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("데이터를 열지 못했어요")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("다시 시도", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8)
        }
    }
}
#endif
