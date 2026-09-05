#if os(watchOS)
import PlanBaseCore
import SwiftData
import SwiftUI
import UserNotifications
import WatchKit

@main
struct PlanBaseWatchApp: App {
    @WKExtensionDelegateAdaptor(PlanBaseWatchExtensionDelegate.self)
    private var extensionDelegate
    @State private var persistenceState: WatchPersistenceState

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .environment(\.locale, Locale(identifier: "ko_KR"))
        }
    }

    @MainActor
    private static func makePersistenceState() -> WatchPersistenceState {
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let container = try PlanBaseContainerFactory.makeInMemory()
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-board") {
                    SeedService.seedIfNeeded(context: container.mainContext,
                        tasks: [], events: [], templates: [], reviews: [], policy: .demo)
                }
                return .ready(container)
            }
#endif
            return .ready(try PlanBaseContainerFactory.makeAppPersistent())
        } catch {
            print("PlanBase Watch 저장소를 열 수 없습니다: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
}

final class PlanBaseWatchExtensionDelegate: NSObject, WKExtensionDelegate,
    UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        WatchFocusNotificationScheduler.registerCategories(center: center)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let sessionValue = userInfo[FocusNotificationRules.sessionIDKey] as? String,
           let sessionID = UUID(uuidString: sessionValue),
           FocusPresentationVisibilityStore.shared.isVisible(sessionID: sessionID) {
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = WatchFocusNotificationRoute(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        ) else { return }
        await WatchFocusNotificationRouteStore.shared.enqueue(route)
    }
}

struct WatchFocusNotificationRoute: Equatable, Sendable {
    var action: FocusNotificationAction
    var tokenID: UUID
    var sessionID: UUID
    var revision: Int
    var phase: FocusTimerPhase
    var deadline: Date
    var requestIdentifier: String

    init?(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        requestIdentifier: String
    ) {
        guard userInfo[FocusNotificationRules.routeKindKey] as? String
                == FocusNotificationRules.routeKindValue,
              let tokenValue = userInfo[FocusNotificationRules.tokenIDKey] as? String,
              let tokenID = UUID(uuidString: tokenValue),
              let sessionValue = userInfo[FocusNotificationRules.sessionIDKey] as? String,
              let sessionID = UUID(uuidString: sessionValue),
              let revision = userInfo[FocusNotificationRules.revisionKey] as? Int,
              let phaseValue = userInfo[FocusNotificationRules.phaseKey] as? String,
              let phase = FocusTimerPhase(rawValue: phaseValue),
              let deadlineValue = userInfo[FocusNotificationRules.deadlineKey] as? TimeInterval else {
            return nil
        }

        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            action = .open
        } else if actionIdentifier == UNNotificationDismissActionIdentifier {
            action = .dismiss
        } else if let mapped = FocusNotificationRules.action(for: actionIdentifier) {
            action = mapped
        } else {
            return nil
        }
        self.tokenID = tokenID
        self.sessionID = sessionID
        self.revision = revision
        self.phase = phase
        deadline = Date(timeIntervalSince1970: deadlineValue)
        self.requestIdentifier = requestIdentifier
    }
}

@MainActor
final class WatchFocusNotificationRouteStore {
    static let shared = WatchFocusNotificationRouteStore()
    static let didReceiveRoute = Notification.Name("PlanBaseWatchFocusNotificationRoute")
    private var pendingRoutes: [WatchFocusNotificationRoute] = []

    func enqueue(_ route: WatchFocusNotificationRoute) {
        pendingRoutes.append(route)
        NotificationCenter.default.post(name: Self.didReceiveRoute, object: nil)
    }

    func consumeAll() -> [WatchFocusNotificationRoute] {
        defer { pendingRoutes.removeAll() }
        return pendingRoutes
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
        PlanBaseRecoveryView(details: details, retry: retry)
    }
}
#endif
