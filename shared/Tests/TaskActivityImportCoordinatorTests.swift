import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func activityImportCoordinatorCoalescesSuccessfulImports() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let completedAt = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(
        title: "CloudKit 완료 작업",
        status: .done,
        plannedAt: completedAt,
        order: 100,
        createdAt: completedAt.addingTimeInterval(-100),
        updatedAt: completedAt
    )
    task.completedAt = completedAt
    task.completedDayKey = "2026-08-14"
    context.insert(task)
    try context.save()

    let counter = ActivityNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
        forName: PersistenceCommandService.dataChangedNotification,
        object: context,
        queue: nil
    ) { _ in
        counter.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let coordinator = TaskActivityImportCoordinator(
        context: context,
        debounce: .zero
    )
    coordinator.schedule(after: successfulActivityImportSummary())
    coordinator.schedule(after: successfulActivityImportSummary())

    for _ in 0..<100 where coordinator.lastReport == nil {
        try await Swift.Task.sleep(for: .milliseconds(10))
    }
    let activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())

    #expect(coordinator.lastReport?.insertedActivities == 1)
    #expect(counter.value == 1)
    #expect(activities.filter { $0.supersededAt == nil }.count == 1)
}

@Test
@MainActor
func activityImportCoordinatorCancellationPreventsBackfill() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let completedAt = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(title: "취소 대상", status: .done, plannedAt: completedAt, order: 100)
    task.completedAt = completedAt
    task.completedDayKey = "2026-08-14"
    context.insert(task)
    try context.save()

    let coordinator = TaskActivityImportCoordinator(
        context: context,
        debounce: .milliseconds(50)
    )
    coordinator.schedule(after: successfulActivityImportSummary())
    coordinator.cancel()
    try await Swift.Task.sleep(for: .milliseconds(80))

    #expect(!coordinator.isPending)
    #expect(coordinator.lastReport == nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
}

@Test
@MainActor
func activityImportCoordinatorKeepsLateCapturedEvidence() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let completedAt = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(
        id: taskID,
        title: "혼합 버전 완료",
        status: .done,
        plannedAt: completedAt,
        order: 100,
        createdAt: completedAt.addingTimeInterval(-100),
        updatedAt: completedAt
    )
    task.completedAt = completedAt
    task.completedDayKey = "2026-08-14"
    context.insert(task)
    try context.save()

    let coordinator = TaskActivityImportCoordinator(
        context: context,
        debounce: .milliseconds(20)
    )
    coordinator.schedule(after: successfulActivityImportSummary())

    let captured = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(
            taskID: taskID,
            activityDayKey: "2026-08-15"
        ),
        taskId: taskID,
        activityDayKey: "2026-08-15",
        occurredAt: completedAt.addingTimeInterval(0.5),
        origin: .captured,
        createdAt: completedAt,
        updatedAt: completedAt.addingTimeInterval(1)
    )
    context.insert(captured)
    try context.save()

    for _ in 0..<100 where coordinator.lastReport == nil {
        try await Swift.Task.sleep(for: .milliseconds(10))
    }
    let active = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        .filter { $0.supersededAt == nil }

    #expect(active.count == 1)
    #expect(active.first?.instanceID == captured.instanceID)
    #expect(active.first?.originRawValue == TaskCompletionActivityOrigin.captured.rawValue)
}

private func successfulActivityImportSummary() -> CloudKitSyncEventSummary {
    CloudKitSyncEventSummary(
        kind: .import,
        isCompleted: true,
        succeeded: true
    )
}

private final class ActivityNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
