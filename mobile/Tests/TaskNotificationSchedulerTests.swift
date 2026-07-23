import SwiftData
import XCTest
import UserNotifications
import PlanBaseCore
@testable import PlanBase

@MainActor
private final class FakeTaskNotificationCenterClient: TaskNotificationCenterClient {
    var state: TaskNotificationAuthorizationState = .authorized
    var pendingRequests: [UNNotificationRequest] = []
    var deliveredRequests: [UNNotificationRequest] = []
    var addedRequests: [UNNotificationRequest] = []
    var removedPendingIdentifierBatches: [[String]] = []
    var removedDeliveredIdentifierBatches: [[String]] = []

    func authorizationState() async -> TaskNotificationAuthorizationState {
        state
    }

    func requestAlertAndSoundAuthorization() async throws {
        state = .authorized
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingRequests
    }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] {
        deliveredRequests
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifierBatches.append(identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifierBatches.append(identifiers)
    }
}

@MainActor
final class TaskNotificationSchedulerTests: XCTestCase {
    func testImmediateCancellationRemovesCurrentAndLegacyPendingAndDeliveredIDs() {
        let taskID = UUID(uuidString: "A2CF04D6-00B1-4102-A7EB-4F54DA81D398")!
        let fake = FakeTaskNotificationCenterClient()
        let scheduler = TaskNotificationScheduler(center: fake)

        scheduler.cancelNotifications(for: [taskID, taskID])

        let expected = TaskReminderRules.managedIdentifiers(for: taskID).sorted()
        XCTAssertEqual(fake.removedPendingIdentifierBatches, [expected])
        XCTAssertEqual(fake.removedDeliveredIdentifierBatches, [expected])
    }

    func testReconcileSchedulesFutureOpenTask() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let reminderAt = now.addingTimeInterval(3_600)
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = PlanBaseCore.Task(
            title: "미래 알림",
            status: .todo,
            plannedAt: now,
            order: 100,
            reminderAt: reminderAt
        )
        context.insert(task)
        try context.save()

        let fake = FakeTaskNotificationCenterClient()
        let scheduler = TaskNotificationScheduler(center: fake)
        await scheduler.reconcile(context: context, now: now)

        XCTAssertEqual(fake.addedRequests.map(\.identifier), [
            TaskReminderRules.identifier(for: task.id)
        ])
        XCTAssertTrue(fake.removedPendingIdentifierBatches.isEmpty)
    }

    func testReconcileCancelsOnlyManagedRequestsForCompletedTask() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let taskID = UUID(uuidString: "80964E58-F1F0-4569-814F-0FDB419E0102")!
        let managedID = TaskReminderRules.identifier(for: taskID)
        let unmanagedID = "other-app.notification"
        let fake = FakeTaskNotificationCenterClient()
        fake.pendingRequests = [
            UNNotificationRequest(
                identifier: managedID,
                content: UNMutableNotificationContent(),
                trigger: nil
            ),
            UNNotificationRequest(
                identifier: unmanagedID,
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        ]
        let scheduler = TaskNotificationScheduler(center: fake)
        let container = try PlanBaseContainerFactory.makeInMemory()

        await scheduler.reconcile(context: container.mainContext, now: now)

        XCTAssertEqual(fake.removedPendingIdentifierBatches, [[managedID]])
        XCTAssertFalse(
            fake.removedPendingIdentifierBatches.flatMap { $0 }.contains(unmanagedID)
        )
        XCTAssertTrue(fake.addedRequests.isEmpty)
    }
}
