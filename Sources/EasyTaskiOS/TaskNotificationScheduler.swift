#if os(iOS)
import EasyTaskCore
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
final class TaskNotificationScheduler {
    static let shared = TaskNotificationScheduler()

    private let center: UNUserNotificationCenter
    private var isReconciling = false
    private var needsAnotherPass = false

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

    func requestAuthorization() async -> TaskNotificationAuthorizationState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("EasyTask notification authorization failed: \(error)")
        }
        return await authorizationState()
    }

    func reconcile(context: ModelContext, now: Date = Date()) async {
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
                print("EasyTask notification reconciliation failed: \(error)")
            }
        } while needsAnotherPass
    }

    private func reconcileOnce(context: ModelContext, now: Date) async throws {
        let authorization = await authorizationState()
        let pendingRequests = await center.pendingNotificationRequests()
        let ownedPendingIDs = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(TaskReminderRules.identifierPrefix) }
        let delivered = await center.deliveredNotifications()
        let ownedDeliveredIDs = delivered
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(TaskReminderRules.identifierPrefix) }

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
                    "EasyTask notification scheduling failed " +
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
        return UNNotificationRequest(
            identifier: snapshot.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )
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
    static let didReceiveRoute = Notification.Name("EasyTaskTaskNotificationRoute")

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

final class EasyTaskAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = TaskNotificationRoute(
            userInfo: response.notification.request.content.userInfo
        )
        guard let route else { return }
        await TaskNotificationRouteStore.shared.enqueue(route)
    }
}
#endif
