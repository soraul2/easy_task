import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func archiveMaintenanceDoesNotPublishAnEmptyNavigationCheck() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let notifications = MaintenanceNotifications(context: context)
    for _ in 0..<40 {
        let count = try ArchiveMaintenanceService.archiveCompletedTasks(in: context)
        #expect(count == 0)
    }
    #expect(notifications.count == 0)
    #expect(!context.hasChanges)
}

@Test @MainActor
func archiveMaintenancePreservesPendingEditsAndPublishesTheirSave() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = Task(title: "화면에서 작성 중인 작업", plannedAt: Date(), order: 100)
    context.insert(task)
    let notifications = MaintenanceNotifications(context: context)
    let count = try ArchiveMaintenanceService.archiveCompletedTasks(in: context)
    #expect(count == 0)
    #expect(notifications.count == 1)
    #expect(!context.hasChanges)
    let persisted = try ModelContext(container).fetch(FetchDescriptor<Task>())
    #expect(persisted.map(\.title) == [task.title])
}

@Test @MainActor
func archiveMaintenanceArchivesOnlyEligibleCompletionsOnce() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = DayKey.date(from: "2026-09-04")!
    let yesterday = DayKey.addingDays(-1, to: today)
    let old = Task(title: "지난 완료", status: .done, plannedAt: yesterday, order: 1)
    old.completedAt = yesterday
    old.completedDayKey = DayKey.key(for: yesterday)
    let current = Task(title: "오늘 완료", status: .done, plannedAt: today, order: 2)
    current.completedAt = today
    current.completedDayKey = DayKey.key(for: today)
    let open = Task(title: "지난 미완료", plannedAt: yesterday, order: 3)
    let missingEvidence = Task(title: "완료일 미상", status: .done, plannedAt: yesterday, order: 4)
    let superseded = Task(title: "이전 물리 레코드", status: .done, plannedAt: yesterday, order: 5)
    superseded.completedAt = yesterday
    superseded.completedDayKey = DayKey.key(for: yesterday)
    superseded.supersededAt = today
    for task in [old, current, open, missingEvidence, superseded] { context.insert(task) }
    try context.save()
    let notifications = MaintenanceNotifications(context: context)
    let first = try ArchiveMaintenanceService.archiveCompletedTasks(
        in: context, todayKey: "2026-09-04", now: today)
    let second = try ArchiveMaintenanceService.archiveCompletedTasks(
        in: context, todayKey: "2026-09-04", now: today)
    #expect(first == 1)
    #expect(second == 0)
    #expect(old.archivedAt == today)
    #expect(old.archivedDayKey == "2026-09-04")
    #expect(old.completedAt == yesterday)
    #expect([current, open, missingEvidence, superseded].allSatisfy { $0.archivedAt == nil })
    #expect(notifications.count == 1)
}

@Test @MainActor
func progressSessionReloadsSameTasksAfterReturningToTheBoard() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    context.insert(TaskProgressEvent(taskId: taskID, kind: .started, occurredAt: start))
    try context.save()
    let session = TaskProgressEventQuerySession(context: context)
    session.apply(taskIDs: [taskID])
    for _ in 0..<100 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(5))
    }
    #expect(session.projection(for: taskID).currentStartedAt == start)
    session.cancel()
    // A hidden-screen/import update need not emit a synthetic tab-change notification.
    context.insert(TaskProgressEvent(taskId: taskID, kind: .stopped,
                                     occurredAt: start.addingTimeInterval(600)))
    try context.save()
    session.apply(taskIDs: [taskID])
    for _ in 0..<100 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(5))
    }
    #expect(!session.isLoading)
    #expect(session.projection(for: taskID).currentStartedAt == nil)
    #expect(session.projection(for: taskID).recordedDuration == 600)
}

private final class MaintenanceNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var observer: (any NSObjectProtocol)?
    var count: Int { lock.withLock { value } }

    init(context: ModelContext) {
        observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.value += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
