#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import UIKit
import UserNotifications

enum TaskNotificationAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied

    var canSchedule: Bool {
        self == .authorized
    }
}

@MainActor
protocol TaskNotificationCenterClient: AnyObject {
    func authorizationState() async -> TaskNotificationAuthorizationState
    func requestAlertAndSoundAuthorization() async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func deliveredNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemTaskNotificationCenterClient: TaskNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationState() async -> TaskNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAlertAndSoundAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] {
        await center.deliveredNotifications().map(\.request)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
final class TaskNotificationScheduler {
    static let shared = TaskNotificationScheduler()

    private let center: any TaskNotificationCenterClient
    private var isReconciling = false
    private var needsAnotherPass = false

    init(center: (any TaskNotificationCenterClient)? = nil) {
        self.center = center ?? SystemTaskNotificationCenterClient()
    }

    func authorizationState() async -> TaskNotificationAuthorizationState {
        await center.authorizationState()
    }

    func requestAuthorization() async -> TaskNotificationAuthorizationState {
        do {
            try await center.requestAlertAndSoundAuthorization()
        } catch {
            print("PlanBase notification authorization failed: \(error)")
        }
        return await authorizationState()
    }

    func cancelNotifications(for taskIDs: [UUID]) {
#if DEBUG
        guard !PlanBaseLaunchEnvironment.isUITesting
                || PlanBaseLaunchEnvironment.usesNotificationDeliveryFixture else { return }
#endif
        let identifiers = Set(taskIDs.flatMap(TaskReminderRules.managedIdentifiers))
            .sorted()
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func reconcile(context: ModelContext, now: Date = Date()) async {
#if DEBUG
        guard !PlanBaseLaunchEnvironment.isUITesting
                || PlanBaseLaunchEnvironment.usesNotificationDeliveryFixture else { return }
#endif

        if isReconciling {
            needsAnotherPass = true
            return
        }

        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            do {
                try await reconcileOnce(context: context, now: now)
            } catch {
                print("PlanBase notification reconciliation failed: \(error)")
            }
        } while needsAnotherPass
    }

    private func reconcileOnce(context: ModelContext, now: Date) async throws {
        let authorization = await authorizationState()
        let pendingRequests = await center.pendingNotificationRequests()
        let ownedPendingIDs = pendingRequests
            .map(\.identifier)
            .filter(TaskReminderRules.isManagedIdentifier)
        let deliveredRequests = await center.deliveredNotificationRequests()
        let ownedDeliveredIDs = deliveredRequests
            .map(\.identifier)
            .filter(TaskReminderRules.isManagedIdentifier)

        guard authorization.canSchedule else {
            if authorization == .denied, !ownedPendingIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ownedPendingIDs)
            }
            if !ownedDeliveredIDs.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ownedDeliveredIDs)
            }
            return
        }

        let tasks = try context.fetch(BoundedQueryService.activeReminderTasksDescriptor())
        let desired = TaskReminderRules.desiredSnapshots(from: tasks, now: now)
        let pending = pendingRequests.map { request in
            PendingTaskReminder(
                identifier: request.identifier,
                title: request.content.title,
                reminderAt: (request.trigger as? UNCalendarNotificationTrigger)?
                    .nextTriggerDate()
            )
        }
        let plan = TaskReminderRules.reconciliationPlan(
            desired: desired,
            pending: pending
        )

        let replacementIDs = Set(plan.remindersToSchedule.map(\.identifier))
        let staleIDs = plan.identifiersToCancel.filter {
            !replacementIDs.contains($0)
        }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: staleIDs
            )
        }
        if !ownedDeliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ownedDeliveredIDs)
        }
        for snapshot in plan.remindersToSchedule {
            do {
                // Adding the same identifier replaces the old request only after
                // the notification center accepts the new request.
                try await center.add(request(for: snapshot))
            } catch {
                print(
                    "PlanBase notification scheduling failed " +
                        "for \(snapshot.identifier): \(error)"
                )
            }
        }
    }

    private func request(for snapshot: TaskReminderSnapshot) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = snapshot.title
        content.body = "예정된 작업 시간입니다."
        content.sound = .default
        content.userInfo = [
            TaskNotificationRoute.taskIDKey: snapshot.taskID.uuidString,
            TaskNotificationRoute.plannedDayKey: snapshot.plannedDayKey
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: snapshot.reminderAt
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger: UNNotificationTrigger
#if DEBUG
        if PlanBaseLaunchEnvironment.usesNotificationDeliveryFixture {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 5,
                repeats: false
            )
        } else {
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        }
#else
        trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
#endif
        return UNNotificationRequest(
            identifier: snapshot.identifier,
            content: content,
            trigger: trigger
        )
    }
}

@MainActor
final class FocusNotificationScheduler {
    static let shared = FocusNotificationScheduler()
    nonisolated static let identifierPrefix = "planbase.focus."

    private let center: any TaskNotificationCenterClient
    private var isReconciling = false
    private var needsAnotherPass = false

    init(center: (any TaskNotificationCenterClient)? = nil) {
        self.center = center ?? SystemTaskNotificationCenterClient()
    }

    nonisolated static func registerCategories(
        center: UNUserNotificationCenter = .current()
    ) {
        let focusEnded = UNNotificationCategory(
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
        )
        let breakEnded = UNNotificationCategory(
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
        center.setNotificationCategories([focusEnded, breakEnded])
    }

    func reconcile(now: Date = Date()) async {
#if DEBUG
        guard !PlanBaseLaunchEnvironment.isUITesting else { return }
#endif
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce(now: now)
        } while needsAnotherPass
    }

    func removeDeliveredNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func reconcileOnce(now: Date) async {
        let pending = await center.pendingNotificationRequests()
        let ownedPendingIDs = pending.map(\.identifier).filter(Self.isManaged)
        let delivered = await center.deliveredNotificationRequests()
        let ownedDeliveredIDs = delivered.map(\.identifier).filter(Self.isManaged)

        let snapshot = try? FocusSessionService.activeSnapshot()
        let storedToken = try? FocusNotificationActionTokenStore.read()
        if let storedToken,
           !FocusNotificationRules.isActionable(storedToken, now: now),
           now > storedToken.expiresAt {
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

        guard await center.authorizationState() == .authorized,
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

        let desiredID: String
        let token: FocusNotificationActionToken
        do {
            desiredID = try FocusNotificationRules.requestIdentifier(
                namespace: Self.identifierPrefix,
                snapshot: snapshot
            )
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
        } catch {
            print("PlanBase focus notification token failed: \(error)")
            return
        }

        let staleIDs = ownedPendingIDs.filter { $0 != desiredID }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
        let staleDeliveredIDs = ownedDeliveredIDs.filter { $0 != desiredID }
        if !staleDeliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIDs)
        }
        guard !pending.contains(where: { request in
            request.identifier == desiredID &&
                (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() == deadline
        }) else {
            try? FocusNotificationActionTokenStore.write(token)
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
        do {
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
            if (try? FocusNotificationActionTokenStore.read()?.tokenID) == token.tokenID {
                try? FocusNotificationActionTokenStore.clear()
            }
            print("PlanBase focus notification scheduling failed: \(error)")
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

    private static func isManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }
}

struct FocusNotificationRoute: Equatable, Sendable {
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

        let action: FocusNotificationAction
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            action = .open
        } else if actionIdentifier == UNNotificationDismissActionIdentifier {
            action = .dismiss
        } else if let mapped = FocusNotificationRules.action(for: actionIdentifier) {
            action = mapped
        } else {
            return nil
        }
        self.action = action
        self.tokenID = tokenID
        self.sessionID = sessionID
        self.revision = revision
        self.phase = phase
        deadline = Date(timeIntervalSince1970: deadlineValue)
        self.requestIdentifier = requestIdentifier
    }
}

struct TaskNotificationRoute: Equatable, Sendable {
    static let taskIDKey = "taskID"
    static let plannedDayKey = "plannedDayKey"

    var taskID: UUID
    var fallbackDayKey: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let taskIDValue = userInfo[Self.taskIDKey] as? String,
              let taskID = UUID(uuidString: taskIDValue) else { return nil }
        self.taskID = taskID
        if let dayKey = userInfo[Self.plannedDayKey] as? String,
           DayKey.date(from: dayKey) != nil {
            fallbackDayKey = dayKey
        } else {
            fallbackDayKey = nil
        }
    }
}

@MainActor
final class TaskNotificationRouteStore {
    static let shared = TaskNotificationRouteStore()
    static let didReceiveRoute = Notification.Name("PlanBaseTaskNotificationRoute")

    private var pendingRoute: TaskNotificationRoute?

    func enqueue(_ route: TaskNotificationRoute) {
        pendingRoute = route
        NotificationCenter.default.post(name: Self.didReceiveRoute, object: nil)
    }

    func consume() -> TaskNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

@MainActor
final class FocusNotificationRouteStore {
    static let shared = FocusNotificationRouteStore()
    static let didReceiveRoute = Notification.Name("PlanBaseFocusNotificationRoute")
    private var pendingRoutes: [FocusNotificationRoute] = []

    func enqueue(_ route: FocusNotificationRoute) {
        pendingRoutes.append(route)
        NotificationCenter.default.post(name: Self.didReceiveRoute, object: nil)
    }

    func consumeAll() -> [FocusNotificationRoute] {
        defer { pendingRoutes.removeAll() }
        return pendingRoutes
    }
}

final class PlanBaseAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        FocusNotificationScheduler.registerCategories(center: center)
        return true
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
        let userInfo = response.notification.request.content.userInfo
        if let route = FocusNotificationRoute(
            userInfo: userInfo,
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        ) {
            await FocusNotificationRouteStore.shared.enqueue(route)
            return
        }
        let route = TaskNotificationRoute(
            userInfo: userInfo
        )
        guard let route else { return }
        await TaskNotificationRouteStore.shared.enqueue(route)
    }
}
#endif
