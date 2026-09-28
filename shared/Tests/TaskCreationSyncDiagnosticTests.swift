#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Opt-in diagnosis of the real synchronous core paths. Uses synthetic local stores only.
/// Measures main-actor work, not CloudKit transport, SwiftUI rendering, or input-to-frame latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_TASK_SYNC_DIAGNOSTIC"] == "1"))
@MainActor
func taskCreationSyncDiagnostic() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseTaskSyncDiagnostic-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let today = DayKey.startOfDay(for: Date())
    let dayKey = DayKey.key(for: today)

    for taskCount in [100, 1_000, 3_000] {
        let container = try PlanBaseContainerFactory.makePersistent(
            storeURL: directory.appendingPathComponent("tasks-\(taskCount).store"), mode: .local)
        let context = container.mainContext
        context.autosaveEnabled = false
        try seedTaskSyncDiagnostic(taskCount: taskCount, today: today, context: context)
        // Normalize once before measuring no-op import work, as an already-running app would.
        _ = try DataIntegrityService.reconcile(context: context)
        let baselineCount = try context.fetchCount(FetchDescriptor<Task>())

        try taskSyncSamples("plain-add", taskCount: taskCount, count: 20) {
            try PersistenceCommandService.perform(in: context) {
                let order = try BoundedQueryService.nextOrder(in: context, dayKey: dayKey, status: .todo)
                context.insert(Task(title: "Diagnostic new task", plannedAt: today, order: order))
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == baselineCount + 21)

        try taskSyncSamples("empty-carryover-refresh", taskCount: taskCount, count: 10) {
            let rows = try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
            #expect(rows.isEmpty)
        }
        let boardRows = try context.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey))
        let boardIDs = Set(boardRows.map(\.id))
        taskSyncSamples("board-projection", taskCount: taskCount, count: 20) {
            let tasks = BoardQueryRules.tasksForBoard(
                boardRows.filter { $0.modelContext != nil }, selectedDayKey: dayKey)
            #expect(tasks.count == boardRows.count)
        }
        let quickEntry = SavedTaskQuickEntryController()
        taskSyncSamples("plain-title-controller-update", taskCount: taskCount, count: 20) {
            quickEntry.update("일반 작업 제목", in: context)
            #expect(!context.hasChanges)
            #expect(quickEntry.entries.isEmpty)
        }
        try taskSyncSamples("board-progress-refetch", taskCount: taskCount, count: 10) {
            _ = try TaskProgressEventService.events(forTaskIDs: boardIDs, in: context)
        }
        let summary = CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true)
        try taskSyncSamples("successful-import-core", taskCount: taskCount, count: 5) {
            try CloudKitSyncService.reconcileIfNeeded(after: summary, context: context)
            #expect(!context.hasChanges)
        }
        try taskSyncSamples("activity-integrity-only", taskCount: taskCount, count: 5) {
            let report = try TaskActivityIntegrityService.reconcile(in: context)
            #expect(!report.hasChanges)
        }
        try taskSyncSamples("progress-integrity-only", taskCount: taskCount, count: 5) {
            _ = try TaskProgressEventIntegrityService.reconcile(in: context)
            #expect(!context.hasChanges)
        }
        let allTasks = try context.fetch(FetchDescriptor<Task>())
        try taskSyncSamples("progress-compatibility-only", taskCount: taskCount, count: 5) {
            let report = try TaskProgressCompatibilityService.reconcile(tasks: allTasks, in: context)
            #expect(report.insertedBoundaries == 0)
        }
        try taskSyncSamples("delayed-activity-core", taskCount: taskCount, count: 5) {
            try PersistenceCommandService.perform(in: context) {
                let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context)
                #expect(report.insertedActivities == 0)
                _ = try TaskActivityIntegrityService.reconcile(in: context)
            }
            #expect(!context.hasChanges)
        }
        // Show that these paths run even when the dataset needs no repairs.
        let noOp = try DataIntegrityService.reconcile(context: context, saveChanges: false)
        #expect(!noOp.hasChanges)
        #expect(!context.hasChanges)

        // Convert half the synthetic archive into legitimate incomplete carryover tasks.
        // The app re-reads this inbox on each local task change and every CloudKit event.
        let carryoverCount = taskCount / 2
        for task in allTasks.filter({ $0.archivedAt != nil }).prefix(carryoverCount) {
            task.status = TaskStatus.todo.rawValue
            task.archivedAt = nil
            task.archivedDayKey = nil
            task.completedAt = nil
            task.completedDayKey = nil
        }
        try context.save()
        try taskSyncSamples("populated-carryover-refresh", taskCount: taskCount, count: 10) {
            let rows = try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
            #expect(rows.count == carryoverCount)
        }
        // A representative synchronous subscriber, matching CarryoverInboxConnection's call.
        // This is not a rendered SwiftUI view and excludes other UI subscribers.
        let refreshCarryover: @MainActor @Sendable () -> Void = {
            do {
                let rows = try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
                #expect(rows.count == carryoverCount)
            } catch {
                Issue.record(error)
            }
        }
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { notification in
            guard PersistenceCommandService.affects(.tasks, in: notification) else { return }
            MainActor.assumeIsolated {
                refreshCarryover()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try taskSyncSamples("plain-add-with-carryover-subscriber", taskCount: taskCount, count: 20) {
            try PersistenceCommandService.perform(in: context) {
                let order = try BoundedQueryService.nextOrder(in: context, dayKey: dayKey, status: .todo)
                context.insert(Task(title: "Diagnostic subscribed task", plannedAt: today, order: order))
            }
        }
    }
}

@MainActor
private func seedTaskSyncDiagnostic(taskCount: Int, today: Date, context: ModelContext) throws {
    let visibleCount = min(240, taskCount / 10)
    for index in 0..<taskCount {
        let day = index < visibleCount ? today : DayKey.addingDays(-(1 + index % 120), to: today)
        let status: TaskStatus = index < visibleCount ? .todo : .done
        let task = Task(title: "Diagnostic task \(index)", status: status, plannedAt: day, order: Double(index))
        context.insert(task)
        let start = day.addingTimeInterval(9 * 3600)
        context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
        context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: start.addingTimeInterval(1800)))
        if status == .done {
            task.completedAt = start.addingTimeInterval(1800)
            task.completedDayKey = DayKey.key(for: day)
            task.archivedAt = DayKey.addingDays(1, to: day)
            task.archivedDayKey = DayKey.key(for: task.archivedAt!)
            try TaskActivityService.recordCapturedCompletion(taskID: task.id, occurredAt: task.completedAt!, in: context)
        }
        if index % 250 == 249 { try context.save() }
    }
    try context.save()
}

@MainActor
private func taskSyncSamples(_ name: String, taskCount: Int, count: Int, operation: () throws -> Void) rethrows {
    let firstStart = DispatchTime.now().uptimeNanoseconds
    try operation()
    let first = Double(DispatchTime.now().uptimeNanoseconds - firstStart) / 1_000_000
    var samples: [Double] = []
    for _ in 0..<count {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let sorted = samples.sorted()
    print("TASK_SYNC_DIAGNOSTIC name=\(name) tasks=\(taskCount) unit=ms n=\(count) first=\(first) p50=\(sorted[count / 2]) p95=\(sorted[Int(ceil(Double(count) * 0.95)) - 1]) max=\(sorted.last!) samples=\(samples)")
}
#endif
