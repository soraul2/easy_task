#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Diagnostic correctness controls, with the original 99 scanned / 5 inserted
/// contract intact. No performance interval, production store, or CloudKit.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKFILL_PENDING_REGRESSION"] == "1"))
@MainActor
func goalBackfillPendingOriginalDirtyControl() throws {
    for validationPrefetch in [false, true] {
        let fixture = try goalPendingBackfillFixture()
        let context = fixture.context
        let rawBefore = goalPendingWatchedValues(fixture)
        goalPendingTrace("dirty-before-validation", fixture, variant: "prefetch=\(validationPrefetch)")
        var beforeActivities: [TaskCompletionActivity]
        let taskValues: [String]
        if validationPrefetch {
            beforeActivities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
            goalPendingTrace("after-activity-default-fetch", fixture, variant: "prefetch=true")
            taskValues = try context.fetch(FetchDescriptor<Task>()).map(goalPendingTaskValue).sorted()
            goalPendingTrace("after-task-default-fetch", fixture, variant: "prefetch=true")
        } else {
            beforeActivities = fixture.activities.filter { !$0.isDeleted }
            taskValues = fixture.tasks.filter { !$0.isDeleted }.map(goalPendingTaskValue).sorted()
        }
        let preserved = beforeActivities.map { "\($0.instanceID)|\(goalPendingActivityValue($0))" }
        let expected = beforeActivities.map(goalPendingActivityValue)
            + [0, 1, 5, 6, 100].map { goalPendingLegacyValue(fixture.tasks[$0], createdAt: fixture.createdAt) }
        #expect(goalPendingWatchedValues(fixture) == rawBefore)
        var cancellationChecks = 0
        let report = try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context, createdAt: fixture.createdAt, isCancelled: {
                cancellationChecks += 1
                // First check is after pending capture, before saved-page fetch.
                // Second is at the first eligible row, after that fetch but before record().
                if cancellationChecks <= 2 {
                    goalPendingTrace("service-check-\(cancellationChecks)", fixture,
                                     variant: "prefetch=\(validationPrefetch)")
                }
                return false
            })
        goalPendingTrace("service-return-before-validation", fixture, variant: "prefetch=\(validationPrefetch)")
        #expect(report == TaskActivityBackfillReport(scannedTasks: 99, insertedActivities: 5))
        #expect(goalPendingWatchedValues(fixture) == rawBefore)
        let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        #expect(rows.count == 105)
        #expect(rows.map(goalPendingActivityValue).sorted() == expected.sorted())
        #expect(Set(preserved).isSubset(of: Set(rows.map { "\($0.instanceID)|\(goalPendingActivityValue($0))" })))
        #expect(try context.fetch(FetchDescriptor<Task>()).map(goalPendingTaskValue).sorted() == taskValues)
        #expect(context.hasChanges)
        withExtendedLifetime(fixture.container) {}
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKFILL_PENDING_REGRESSION"] == "1"))
@MainActor
func goalBackfillPendingTaskFetchIsolation() throws {
    for (name, includePending, processFirst) in [
        ("original-default-page", true, false),
        ("original-saved-page", false, false),
        ("original-saved-page-after-processPendingChanges", false, true),
    ] {
        let fixture = try goalPendingBackfillFixture()
        let context = fixture.context
        let expected = goalPendingWatchedValues(fixture)
        goalPendingTrace("before-process-or-page", fixture, variant: name)
        if processFirst {
            context.processPendingChanges()
            goalPendingTrace("after-process-before-page", fixture, variant: name)
            #expect(goalPendingWatchedValues(fixture) == expected)
        }
        var descriptor = goalPendingSavedTaskDescriptor()
        descriptor.includePendingChanges = includePending
        let rows = try context.fetch(descriptor)
        print("GOAL_BACKFILL_PENDING_PAGE variant=\(name) count=\(rows.count) physicalIDs=\(rows.map { $0.instanceID.uuidString }.sorted())")
        goalPendingTrace("after-page-no-backfill", fixture, variant: name)
        // These are data-preservation assertions, not an expectation that a saved
        // page has the same membership as a query that includes pending changes.
        #expect(goalPendingWatchedValues(fixture) == expected)
        #expect(context.hasChanges)
        withExtendedLifetime(fixture.container) {}
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKFILL_PENDING_REGRESSION"] == "1"))
@MainActor
func goalBackfillPendingSeparateReaderAndNormalCommandControl() throws {
    let fixture = try goalPendingBackfillFixture()
    let context = fixture.context
    let before = goalPendingWatchedValues(fixture)
    let changedIDs = Set(context.changedModelsArray.map(\.persistentModelID))
    let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
    goalPendingTrace("before-separate-reader", fixture, variant: "separate-reader")
    let reader = ModelContext(fixture.container)
    reader.autosaveEnabled = false
    let savedRows = try reader.fetch(goalPendingSavedTaskDescriptor())
    #expect(savedRows.count == 100)
    #expect(Set(savedRows.map(\.persistentModelID)) == Set(fixture.tasks.prefix(100).map(\.persistentModelID)))
    goalPendingTrace("after-separate-reader", fixture, variant: "separate-reader")
    #expect(goalPendingWatchedValues(fixture) == before)
    #expect(Set(context.changedModelsArray.map(\.persistentModelID)) == changedIDs)
    #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deletedIDs)
    #expect(context.hasChanges && !reader.hasChanges)

    // Existing command contract saves pending edits before entering backfill.
    // This is a control, not a proposed service fix or permission to save there.
    let report = try PersistenceCommandService.perform(in: context) {
        try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
    }
    goalPendingTrace("after-normal-command", fixture, variant: "separate-reader-command-control")
    #expect(report == TaskActivityBackfillReport(scannedTasks: 99, insertedActivities: 5))
    #expect(goalPendingWatchedValues(fixture) == before)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 105)
    #expect(!context.hasChanges && !reader.hasChanges)
    withExtendedLifetime(fixture.container) {}
}

private struct GoalPendingBackfillFixture {
    let container: ModelContainer
    let context: ModelContext
    let tasks: [Task]
    let activities: [TaskCompletionActivity]
    let createdAt: Date
    let labels: [PersistentIdentifier: String]
}

@MainActor
private func goalPendingBackfillFixture() throws -> GoalPendingBackfillFixture {
    let completion = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
    let createdAt = completion.addingTimeInterval(86_400)
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    var tasks = (0..<100).map { goalPendingTask($0, completion: completion) }
    var activities = tasks.enumerated().map { goalPendingCaptured($0.element, index: $0.offset) }
    for task in tasks { context.insert(task) }
    for activity in activities { context.insert(activity) }
    try context.save()
    var labels: [PersistentIdentifier: String] = [:]
    for (index, task) in tasks.enumerated() { labels[task.persistentModelID] = "task[\(index)]/\(task.instanceID)" }
    for (index, activity) in activities.enumerated() { labels[activity.persistentModelID] = "activity[\(index)]/\(activity.instanceID)" }

    context.delete(activities[0])
    tasks[1].completedAt = completion.addingTimeInterval(86_400)
    tasks[2].status = TaskStatus.todo.rawValue
    tasks[2].completedAt = nil
    context.delete(tasks[3])
    tasks[4].supersededAt = createdAt
    activities[5].supersededAt = createdAt
    activities[6].activityDayKey = TaskActivityRules.legacyDayKey(for: completion.addingTimeInterval(86_400))
    for index in [100, 101] {
        let task = goalPendingTask(index, completion: completion)
        context.insert(task)
        tasks.append(task)
        labels[task.persistentModelID] = "task[\(index)]/\(task.instanceID)"
    }
    let covered = goalPendingCaptured(tasks[101], index: 101)
    context.insert(covered)
    activities.append(covered)
    labels[covered.persistentModelID] = "activity[101]/\(covered.instanceID)"
    return GoalPendingBackfillFixture(container: container, context: context, tasks: tasks,
        activities: activities, createdAt: createdAt, labels: labels)
}

private func goalPendingTask(_ index: Int, completion: Date) -> Task {
    let occurredAt = completion.addingTimeInterval(Double(index % 5) * 60)
    let task = Task(id: goalPendingID(1, index), instanceID: goalPendingID(2, index), title: "Backfill \(index)",
        status: .done, plannedAt: completion.addingTimeInterval(-2 * 86_400), order: Double(index),
        createdAt: completion.addingTimeInterval(-30 * 86_400), updatedAt: occurredAt.addingTimeInterval(5))
    task.completedAt = occurredAt
    task.completedDayKey = "2026-09-29"
    return task
}

private func goalPendingCaptured(_ task: Task, index: Int) -> TaskCompletionActivity {
    let completion = task.completedAt!
    let day = TaskActivityRules.legacyDayKey(for: completion)
    return TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day),
        instanceID: goalPendingID(3, index), taskId: task.id, activityDayKey: day, occurredAt: completion,
        origin: .captured, createdAt: completion.addingTimeInterval(1), updatedAt: completion.addingTimeInterval(2))
}

private func goalPendingSavedTaskDescriptor() -> FetchDescriptor<Task> {
    let done = TaskStatus.done.rawValue
    var descriptor = FetchDescriptor<Task>(predicate: #Predicate {
        $0.supersededAt == nil && $0.status == done && $0.completedAt != nil
    }, sortBy: [SortDescriptor(\Task.instanceID)])
    descriptor.fetchLimit = 200
    descriptor.fetchOffset = 0
    descriptor.includePendingChanges = false
    return descriptor
}

@MainActor
private func goalPendingTrace(_ stage: String, _ fixture: GoalPendingBackfillFixture, variant: String) {
    let rawBeforeArrays = goalPendingWatchedValues(fixture)
    func labels(_ models: [any PersistentModel]) -> [String] {
        models.map { "\(fixture.labels[$0.persistentModelID] ?? String(reflecting: type(of: $0))) pid=\($0.persistentModelID)" }.sorted()
    }
    let inserted = labels(fixture.context.insertedModelsArray)
    let changed = labels(fixture.context.changedModelsArray)
    let deleted = labels(fixture.context.deletedModelsArray)
    let rawAfterArrays = goalPendingWatchedValues(fixture)
    print("GOAL_BACKFILL_PENDING_STAGE variant=\(variant) stage=\(stage) hasChanges=\(fixture.context.hasChanges) insertedModelsArrayIDs=\(inserted) changedModelsArrayIDs=\(changed) deletedModelsArrayIDs=\(deleted) rawBeforeArrays=\(rawBeforeArrays) rawAfterArrays=\(rawAfterArrays)")
}

private func goalPendingWatchedValues(_ fixture: GoalPendingBackfillFixture) -> [String] {
    // Deleted task[3]/activity[0] are traced by captured IDs, not by reading
    // potentially detached stored properties after the normal command saves.
    [1, 2, 4, 100, 101].map { "task[\($0)]:\(goalPendingTaskValue(fixture.tasks[$0]))" }
        + [5, 6, 100].map { "activity-slot[\($0)]:\(goalPendingActivityValue(fixture.activities[$0]))" }
}

private func goalPendingTaskValue(_ task: Task) -> String {
    [task.id.uuidString, task.instanceID.uuidString, task.title, task.status, task.plannedDayKey,
     goalPendingDate(task.plannedAt), String(task.order), task.completedDayKey ?? "nil",
     goalPendingDate(task.completedAt), task.archivedDayKey ?? "nil", goalPendingDate(task.archivedAt),
     goalPendingDate(task.createdAt), goalPendingDate(task.updatedAt), goalPendingDate(task.supersededAt)].joined(separator: "|")
}

private func goalPendingActivityValue(_ activity: TaskCompletionActivity) -> String {
    [activity.id.uuidString, activity.taskId.uuidString, activity.activityDayKey, goalPendingDate(activity.occurredAt),
     activity.originRawValue, goalPendingDate(activity.createdAt), goalPendingDate(activity.updatedAt),
     goalPendingDate(activity.supersededAt)].joined(separator: "|")
}

private func goalPendingLegacyValue(_ task: Task, createdAt: Date) -> String {
    let completion = task.completedAt!
    let day = TaskActivityRules.legacyDayKey(for: completion)
    return [TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day).uuidString, task.id.uuidString, day,
        goalPendingDate(completion), TaskCompletionActivityOrigin.legacyBackfill.rawValue,
        goalPendingDate(createdAt), goalPendingDate(createdAt), "nil"].joined(separator: "|")
}

private func goalPendingDate(_ value: Date?) -> String { value.map { String($0.timeIntervalSince1970) } ?? "nil" }

private func goalPendingID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "30000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
