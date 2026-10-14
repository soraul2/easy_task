import AppKit
import SwiftData
import SwiftUI
import PlanBaseCore
import UserNotifications

#if DEBUG
enum PlanBaseDesktopLaunchEnvironment {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var usesEventHistoryFixtures: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-event-history-fixtures"
        )
    }
}
#endif

@main
@MainActor
struct PlanBaseDesktopApp: App {
    @NSApplicationDelegateAdaptor(PlanBaseDesktopAppDelegate.self) private var appDelegate
    @State private var startup = PlanBaseStartupSession()

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup.state {
                case .opening:
                    ProgressView("PlanBase 준비 중…")
                        .accessibilityIdentifier("planbase-startup-loading")
                case .ready(let modelContainer, let context):
                    Group {
#if DEBUG
                        if Self.isCloudKitProbeRequested {
                            Color.clear
                        } else {
                            AppRootView(
                                hasCompletedBootstrap: true,
                                bootstrapImageMigrationReport: startup.legacyImageMigrationReport,
                                takePendingBootstrapImport: startup.takePendingImport,
                                startupOpenURLRevision: startup.pendingOpenURLRevision,
                                takePendingStartupOpenURLs: startup.takePendingOpenURLs
                            )
                        }
#else
                        AppRootView(
                            hasCompletedBootstrap: true,
                            bootstrapImageMigrationReport: startup.legacyImageMigrationReport,
                            takePendingBootstrapImport: startup.takePendingImport,
                            startupOpenURLRevision: startup.pendingOpenURLRevision,
                            takePendingStartupOpenURLs: startup.takePendingOpenURLs
                        )
#endif
                    }
                    .modelContainer(modelContainer)
                    .environment(\.modelContext, context)
                case .failed(let details):
                    PlanBaseRecoveryView(details: details) {
                        startup.retry()
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 680)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .onOpenURL(perform: startup.recordOpenURL)
            .task(id: startup.attempt) {
                await startup.load(open: Self.openPersistentStore,
                                   performIntegrity: Self.shouldPrepareIntegrity,
                                   legacyImageMigration: PlanBaseLegacyImageMigrationConfiguration(
                                       appSupportFolder: PlanBaseCompatibility.legacyDesktopImageFolderName
                                   ),
                                   onReady: Self.completeStartup)
            }
        }

        Window("집중 모드", id: "focus-mode") {
            Group {
                switch startup.state {
                case .opening:
                    ProgressView("PlanBase 준비 중…")
                case .ready(let modelContainer, let context):
                    FocusModeView()
                        .modelContainer(modelContainer)
                        .environment(\.modelContext, context)
                        .background(FocusFloatingWindowConfigurator())
                case .failed(let details):
                    PlanBaseRecoveryView(details: details) {
                        startup.retry()
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .task(id: startup.attempt) {
                await startup.load(open: Self.openPersistentStore,
                                   performIntegrity: Self.shouldPrepareIntegrity,
                                   legacyImageMigration: PlanBaseLegacyImageMigrationConfiguration(
                                       appSupportFolder: PlanBaseCompatibility.legacyDesktopImageFolderName
                                   ),
                                   onReady: Self.completeStartup)
            }
        }
        .defaultSize(width: 480, height: 700)
        .windowResizability(.contentMinSize)
    }

    private static func openPersistentStore() async throws -> ModelContainer {
#if DEBUG
        if PlanBaseDesktopLaunchEnvironment.isUITesting {
            let container: ModelContainer
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-performance") {
                let directory = URL.applicationSupportDirectory
                    .appendingPathComponent("PlanBaseResponsivenessFixtures", isDirectory: true)
                    .appendingPathComponent(
                        Bundle.main.bundleIdentifier ?? "com.soraul2.planbase.responsiveness-diagnostic",
                        isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                container = try await PlanBaseContainerFactory.makeAppPersistentAsync(
                    storeURL: directory.appendingPathComponent("v1.store"), mode: .local)
                try ResponsivenessPreviewFixtures.seed(in: container.mainContext)
            } else {
                container = try MemoUITestSupport.makeContainer(arguments: ProcessInfo.processInfo.arguments)
                try DiscoveryPreviewFixtures.seed(in: container.mainContext)
            }
            return container
        }
        _ = try PlanBaseContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested()
#endif
        return try await PlanBaseContainerFactory.makeAppPersistentAsync()
    }

    private static var shouldPrepareIntegrity: Bool {
#if DEBUG
        // Explicit convergence probes own their fixture setup and reconciliation.
        !isCloudKitProbeRequested
#else
        true
#endif
    }

    private static func completeStartup(container: ModelContainer, context: ModelContext) {
#if DEBUG
        startCloudKitProbeIfRequested(context: context)
#endif
    }

#if DEBUG
    private static var isCloudKitProbeRequested: Bool {
        CloudKitConvergenceProbe.isProbeInvocation(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func startCloudKitProbeIfRequested(context: ModelContext) {
        guard isCloudKitProbeRequested else { return }

        Swift.Task { @MainActor in
            _ = await CloudKitConvergenceProbe.runIfRequested(
                context: context
            )
        }
    }
#endif
}

private struct FocusFloatingWindowConfigurator: NSViewRepresentable {
    @AppStorage("planbase.focusAlwaysOnTop") private var alwaysOnTop = true
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let pinned = alwaysOnTop
        DispatchQueue.main.async { configure(view.window, pinned: pinned) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let pinned = alwaysOnTop
        DispatchQueue.main.async { configure(nsView.window, pinned: pinned) }
    }

    private func configure(_ window: NSWindow?, pinned: Bool) {
        guard let window else { return }
        window.level = pinned ? .floating : .normal
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.setFrameAutosaveName("PlanBaseFocusModeWindow")
    }
}

@MainActor
final class DesktopFocusNotificationScheduler {
    static let shared = DesktopFocusNotificationScheduler()
    private static let identifierPrefix = "planbase.focus.mac."
    private let center = UNUserNotificationCenter.current()
    private var isReconciling = false
    private var needsAnotherPass = false

    nonisolated static func registerCategories(
        center: UNUserNotificationCenter = .current()
    ) {
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: FocusNotificationRules.focusEndedCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: FocusNotificationRules.startBreakActionIdentifier,
                        title: "휴식 시작"
                    ),
                    UNNotificationAction(
                        identifier: FocusNotificationRules.continueFocusActionIdentifier,
                        title: "계속 집중"
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: FocusNotificationRules.breakEndedCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: FocusNotificationRules.startFocusActionIdentifier,
                        title: "집중 시작"
                    ),
                    UNNotificationAction(
                        identifier: FocusNotificationRules.extendBreakActionIdentifier,
                        title: "5분 더 쉬기"
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
    }

    func reconcile(
        now: Date = Date(),
        requestAuthorizationIfNeeded: Bool = false
    ) async {
#if DEBUG
        guard !PlanBaseDesktopLaunchEnvironment.isUITesting else { return }
#endif
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce(
                now: now,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        } while needsAnotherPass
    }

    func removeDeliveredNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func reconcileOnce(
        now: Date,
        requestAuthorizationIfNeeded: Bool
    ) async {
        do {
            let snapshot = try FocusSessionService.activeSnapshot()
            let settings = await center.notificationSettings()
            if snapshot != nil,
               requestAuthorizationIfNeeded,
               settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            }

            let pending = await center.pendingNotificationRequests()
            let ownedPendingIDs = pending.map(\.identifier).filter {
                $0.hasPrefix(Self.identifierPrefix)
            }
            let delivered = await center.deliveredNotifications().map(\.request)
            let ownedDeliveredIDs = delivered.map(\.identifier).filter {
                $0.hasPrefix(Self.identifierPrefix)
            }
            let storedToken = try? FocusNotificationActionTokenStore.read()
            if let storedToken, now > storedToken.expiresAt {
                try? FocusNotificationActionTokenStore.clear()
            }

            if let storedToken,
               FocusNotificationRules.isActionable(storedToken, now: now),
               snapshot.map({ FocusNotificationRules.matches(storedToken, snapshot: $0) }) != false {
                if !ownedPendingIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ownedPendingIDs)
                }
                let staleDelivered = ownedDeliveredIDs.filter {
                    $0 != storedToken.requestIdentifier
                }
                if !staleDelivered.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
                }
                return
            }

            let refreshedSettings = await center.notificationSettings()
            guard [.authorized, .provisional].contains(refreshedSettings.authorizationStatus),
                  let snapshot,
                  snapshot.runState == .running,
                  let deadline = snapshot.deadline,
                  deadline > now else {
                if !ownedPendingIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ownedPendingIDs)
                }
                if !ownedDeliveredIDs.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ownedDeliveredIDs)
                }
                try? FocusNotificationActionTokenStore.clear()
                return
            }

            let desiredID = try FocusNotificationRules.requestIdentifier(
                namespace: Self.identifierPrefix,
                snapshot: snapshot
            )
            let token: FocusNotificationActionToken
            if let storedToken,
               storedToken.requestIdentifier == desiredID,
               FocusNotificationRules.matches(storedToken, snapshot: snapshot) {
                token = storedToken
            } else {
                token = try FocusNotificationRules.makeToken(
                    snapshot: snapshot,
                    requestIdentifier: desiredID
                )
            }
            let staleIDs = ownedPendingIDs.filter { $0 != desiredID }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            let staleDelivered = ownedDeliveredIDs.filter { $0 != desiredID }
            if !staleDelivered.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
            }

            if pending.contains(where: { request in
                request.identifier == desiredID &&
                    (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                        == deadline
            }) {
                try FocusNotificationActionTokenStore.write(token)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = FocusNotificationRules.title(for: token)
            content.body = FocusNotificationRules.body(for: token)
            content.sound = .default
            content.categoryIdentifier = FocusNotificationRules.categoryIdentifier(
                for: snapshot.phase ?? .focus
            )
            content.userInfo = Self.userInfo(for: token)

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: deadline
            )
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            try FocusNotificationActionTokenStore.write(token)
            try await center.add(UNNotificationRequest(
                identifier: desiredID,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            ))
        } catch {
            print("macOS Focus notification reconciliation failed: \(error)")
        }
    }

    private nonisolated static func userInfo(
        for token: FocusNotificationActionToken
    ) -> [AnyHashable: Any] {
        [
            FocusNotificationRules.routeKindKey: FocusNotificationRules.routeKindValue,
            FocusNotificationRules.tokenIDKey: token.tokenID.uuidString,
            FocusNotificationRules.sessionIDKey: token.sessionID.uuidString,
            FocusNotificationRules.revisionKey: token.revision,
            FocusNotificationRules.phaseKey: token.phaseRawValue,
            FocusNotificationRules.deadlineKey: token.deadline.timeIntervalSince1970
        ]
    }
}

final class PlanBaseDesktopAppDelegate: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        DesktopFocusNotificationScheduler.registerCategories(center: center)
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
        guard let route = DesktopFocusNotificationRoute(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        ) else { return }
        await DesktopFocusNotificationRouteStore.shared.enqueue(route)
    }
}

struct DesktopFocusNotificationRoute: Equatable, Sendable {
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
final class DesktopFocusNotificationRouteStore {
    static let shared = DesktopFocusNotificationRouteStore()
    static let didReceiveRoute = Notification.Name("PlanBaseDesktopFocusNotificationRoute")
    private var pendingRoutes: [DesktopFocusNotificationRoute] = []

    func enqueue(_ route: DesktopFocusNotificationRoute) {
        pendingRoutes.append(route)
        NotificationCenter.default.post(name: Self.didReceiveRoute, object: nil)
    }

    func consumeAll() -> [DesktopFocusNotificationRoute] {
        defer { pendingRoutes.removeAll() }
        return pendingRoutes
    }
}
