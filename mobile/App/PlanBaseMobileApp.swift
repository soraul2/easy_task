#if os(iOS)
import Combine
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

enum PlanBaseLaunchEnvironment {
    static var isUITesting: Bool {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("--ui-testing")
            // Xcode can relaunch an already-installed UI test target without
            // forwarding XCUIApplication launch arguments. The automation
            // socket remains present and keeps that relaunch off user data.
            || processInfo.environment["TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK"] != nil
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

    static var usesNotificationDeliveryFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-notification-delivery"
        )
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

    static var usesTaskRecordEdgeFixtures: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-task-record-edge-fixtures"
        )
#else
        false
#endif
    }

    static var usesReviewImageFixtures: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-review-image-fixtures"
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
#if DEBUG
    @MainActor private static var didSimulateRecovery = false
#endif

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
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
                    .planBaseAccessibilityTextSizeFixture()
                }
            }
            .environment(\.locale, Locale(identifier: "ko_KR"))
        }
    }

    @MainActor
    private static func makePersistenceState() -> PersistenceState {
#if DEBUG
        if PlanBaseLaunchEnvironment.isUITesting {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-recovery-once"),
               !didSimulateRecovery {
                didSimulateRecovery = true
                return .failed("UI 검증용 저장소 열기 실패입니다. 실제 사용자 저장소에는 접근하지 않았습니다. 다시 시도하면 격리된 메모리 저장소를 엽니다.")
            }
            do {
                let modelContainer: ModelContainer
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-performance") {
                    // This dedicated local database is outside the normal app store.
                    // Reopening it avoids counting fixture generation as app launch work.
                    let directory = URL.applicationSupportDirectory
                        .appendingPathComponent("ResponsivenessFixtures", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    modelContainer = try PlanBaseContainerFactory.makePersistent(
                        storeURL: directory.appendingPathComponent("v1.store"), mode: .local)
                    try ResponsivenessPreviewFixtures.seed(in: modelContainer.mainContext)
                } else {
                    modelContainer = try PlanBaseContainerFactory.makeInMemory()
                }
                try seedUITestingDemoDataIfNeeded(in: modelContainer)
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
    @MainActor
    private static func seedUITestingDemoDataIfNeeded(
        in modelContainer: ModelContainer
    ) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard PlanBaseLaunchEnvironment.isUITesting,
              !PlanBaseLaunchEnvironment.usesEmptyBoardFixture,
              !arguments.contains("--ui-testing-performance"),
              !arguments.contains("--ui-testing-daily-activity-fixtures") else {
            return
        }

        let context = modelContainer.mainContext
        try PersistenceCommandService.perform(in: context) {
            SeedService.seedIfNeeded(
                context: context,
                tasks: try context.fetch(FetchDescriptor<TodoTask>()),
                events: try context.fetch(FetchDescriptor<CalendarEvent>()),
                templates: try context.fetch(FetchDescriptor<TaskTemplate>()),
                reviews: try context.fetch(FetchDescriptor<DailyReview>()),
                policy: .demo
            )
        }
    }
#endif

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
