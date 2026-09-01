#if os(iOS)
import Combine
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

enum PlanBaseLaunchEnvironment {
    static var isUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        false
#endif
    }

    static var usesReminderCompletionFixtures: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reminder-fixtures")
#else
        false
#endif
    }

    static var usesEmptyBoardFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-board")
#else
        false
#endif
    }

    static var usesEventHistoryFixtures: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-event-history-fixtures"
        )
#else
        false
#endif
    }

    static var usesAccessibilityTextSizeFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-accessibility-text-size"
        )
#else
        false
#endif
    }

    static var usesLiveActivityDurationFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-live-activity-duration"
        )
#else
        false
#endif
    }

    static var usesLiveActivityTwoDoingFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-live-activity-two-doing"
        )
#else
        false
#endif
    }

    static var themeFixtureID: String? {
#if DEBUG
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--ui-testing-theme=")
        }) else { return nil }
        let themeID = String(argument.dropFirst("--ui-testing-theme=".count))
        return ThemePreferenceRules.isKnownThemeID(themeID) ? themeID : nil
#else
        nil
#endif
    }
}

@main
struct PlanBaseMobileApp: App {
    @UIApplicationDelegateAdaptor(PlanBaseAppDelegate.self) private var appDelegate
    @State private var persistenceState: PersistenceState

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
    }

    var body: some Scene {
        WindowGroup {
            switch persistenceState {
            case .ready(let modelContainer):
                Group {
#if DEBUG
                    if Self.isCloudKitProbeRequested {
                        Color.clear
                    } else {
                        MobileAppRootView()
                    }
#else
                    MobileAppRootView()
#endif
                }
                .planBaseAccessibilityTextSizeFixture()
                .modelContainer(modelContainer)
            case .failed(let details):
                PersistenceRecoveryView(details: details) {
                    persistenceState = Self.makePersistenceState()
                }
            }
        }
    }

    @MainActor
    private static func makePersistenceState() -> PersistenceState {
#if DEBUG
        if PlanBaseLaunchEnvironment.isUITesting {
            do {
                let modelContainer = try PlanBaseContainerFactory.makeInMemory()
                PlanBaseTaskIntentRuntime.install(modelContainer: modelContainer)
                return .ready(modelContainer)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
#endif

        if let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            try? FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }

        do {
#if DEBUG
            _ = try PlanBaseContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested()
#endif
            let modelContainer = try PlanBaseContainerFactory.makeAppPersistent()
            PlanBaseTaskIntentRuntime.install(modelContainer: modelContainer)
#if DEBUG
            startCloudKitProbeIfRequested(modelContainer: modelContainer)
#endif
            return .ready(modelContainer)
        } catch {
            print("PlanBase 저장소를 열 수 없습니다: \(error.localizedDescription)")
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

private extension View {
    @ViewBuilder
    func planBaseAccessibilityTextSizeFixture() -> some View {
#if DEBUG
        if PlanBaseLaunchEnvironment.usesAccessibilityTextSizeFixture {
            dynamicTypeSize(.accessibility5)
        } else {
            self
        }
#else
        self
#endif
    }
}

private enum PersistenceState {
    case ready(ModelContainer)
    case failed(String)
}

#else
@main
struct PlanBaseMobilePlaceholder {
    static func main() {
        print("PlanBaseMobile builds only for iOS.")
    }
}
#endif
