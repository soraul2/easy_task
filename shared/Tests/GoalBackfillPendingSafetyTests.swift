import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Ordinary production-path regressions. The opt-in SDK diagnostic continues
/// to exercise the intentionally unsafe original saved-only fetch separately.
@Test @MainActor
func goalBackfillPreservesDirtyTasksActivitiesAndPageBoundaries() throws {
    for count in [100, 240] {
        var fixture = try goalSafeBackfillFixture(count: count, captured: true)
        let context = fixture.context
        goalSafeBackfillApplyDirty(&fixture)
        let pendingTaskIDs = Set((context.insertedModelsArray + context.changedModelsArray)
            .compactMap { ($0 as? Task)?.persistentModelID })
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        let insertedTaskIDs = Set(context.insertedModelsArray.compactMap { ($0 as? Task)?.persistentModelID })
        let taskValues = fixture.tasks.filter { !$0.isDeleted }.map(goalSafeTaskValue).sorted()
        let oldActivities = fixture.activities.filter { !$0.isDeleted }
        let preserved = oldActivities.map(goalSafePhysicalActivityValue)
        let expectedActivities = oldActivities.map(goalSafeActivityValue)
            + [0, 1, 5, 6, count].map { goalSafeLegacyValue(fixture.tasks[$0], createdAt: fixture.createdAt) }

        let reader = ModelContext(fixture.container)
        reader.autosaveEnabled = false
        var savedDescriptor = FetchDescriptor<Task>()
        savedDescriptor.includePendingChanges = false
        let savedTasks = try reader.fetch(savedDescriptor)
        #expect(Set(savedTasks.map(\.persistentModelID)) == Set(fixture.tasks.prefix(count).map(\.persistentModelID)))
        #expect(fixture.tasks.filter { !$0.isDeleted }.map(goalSafeTaskValue).sorted() == taskValues)

        let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
        #expect(report == TaskActivityBackfillReport(scannedTasks: count - 1, insertedActivities: 5))
        #expect(fixture.tasks.filter { !$0.isDeleted }.map(goalSafeTaskValue).sorted() == taskValues)
        let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        #expect(rows.count == count + 5)
        #expect(rows.map(goalSafeActivityValue).sorted() == expectedActivities.sorted())
        #expect(Set(preserved).isSubset(of: Set(rows.map(goalSafePhysicalActivityValue))))
        #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deletedIDs)
        #expect(Set(context.insertedModelsArray.compactMap { ($0 as? Task)?.persistentModelID }) == insertedTaskIDs)
        #expect(pendingTaskIDs.isSubset(of: Set((context.insertedModelsArray + context.changedModelsArray)
            .compactMap { ($0 as? Task)?.persistentModelID })))
        #expect(context.hasChanges && !reader.hasChanges)
        // A read-only verification context still sees the original saved fields:
        // service did not commit the caller's dirty state or its inserted activity.
        #expect(savedTasks.first { $0.id == fixture.tasks[1].id }?.completedAt == fixture.completion.addingTimeInterval(60))
        #expect(try reader.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == count)
    }
}

@Test @MainActor
func goalBackfillExcludesPendingPhysicalTaskInsteadOfEveryLogicalCopy() throws {
    var fixture = try goalSafeBackfillFixture(count: 2, captured: true)
    let context = fixture.context
    let logicalID = fixture.tasks[0].id
    let savedCopy = goalSafeBackfillTask(10, completion: fixture.completion.addingTimeInterval(86_400), logicalID: logicalID)
    context.insert(savedCopy)
    fixture.tasks.append(savedCopy)
    try context.save()
    fixture.tasks[0].status = TaskStatus.todo.rawValue
    fixture.tasks[0].completedAt = nil
    let pendingCopy = goalSafeBackfillTask(11, completion: fixture.completion.addingTimeInterval(2 * 86_400), logicalID: logicalID)
    context.insert(pendingCopy)
    fixture.tasks.append(pendingCopy)
    let before = fixture.tasks.map(goalSafeTaskValue)
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
    #expect(report == TaskActivityBackfillReport(scannedTasks: 3, insertedActivities: 2))
    #expect(fixture.tasks.map(goalSafeTaskValue) == before)
    let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == 4)
    #expect(Set(rows.filter { $0.taskId == logicalID }.map(\.activityDayKey)) == Set([
        TaskActivityRules.legacyDayKey(for: fixture.completion),
        TaskActivityRules.legacyDayKey(for: savedCopy.completedAt!),
        TaskActivityRules.legacyDayKey(for: pendingCopy.completedAt!),
    ]))
    #expect(context.hasChanges)
}

@Test @MainActor
func goalBackfillPreservesCompletionNormalizedInsideIntegrityCommand() throws {
    let fixture = try goalSafeBackfillFixture(count: 1, captured: true)
    let task = fixture.tasks[0]
    let latest = fixture.completion.addingTimeInterval(86_400)
    task.completedAt = nil
    task.completedDayKey = nil
    task.updatedAt = latest
    _ = try DataIntegrityService.reconcile(context: fixture.context, saveChanges: false)
    #expect(task.completedAt == latest)
    let rows = try fixture.context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == 2)
    #expect(rows.contains { $0.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue
        && $0.activityDayKey == TaskActivityRules.legacyDayKey(for: latest) && $0.occurredAt == latest })
    #expect(fixture.context.hasChanges)
    let reader = ModelContext(fixture.container)
    reader.autosaveEnabled = false
    #expect(try reader.fetch(FetchDescriptor<Task>()).first?.completedAt == fixture.completion)
    #expect(try reader.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
}

@Test @MainActor
func goalBackfillDirtyCancellationDoesNotReplacePendingFieldsOrSave() throws {
    var fixture = try goalSafeBackfillFixture(count: 100, captured: true)
    goalSafeBackfillApplyDirty(&fixture)
    let context = fixture.context
    let taskValues = fixture.tasks.filter { !$0.isDeleted }.map(goalSafeTaskValue).sorted()
    let activityValues = fixture.activities.filter { !$0.isDeleted }.map(goalSafePhysicalActivityValue).sorted()
    let deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
    var checks = 0
    #expect(throws: CancellationError.self) {
        try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt, isCancelled: {
            checks += 1
            return checks >= 2
        })
    }
    #expect(checks == 2)
    #expect(fixture.tasks.filter { !$0.isDeleted }.map(goalSafeTaskValue).sorted() == taskValues)
    #expect(fixture.activities.filter { !$0.isDeleted }.map(goalSafePhysicalActivityValue).sorted() == activityValues)
    #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deleted)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 100)
    #expect(context.hasChanges)
}

@Test @MainActor
func goalBackfillCancellationAndFailureLeaveRollbackToCommandBoundary() throws {
    for cancel in [true, false] {
        let fixture = try goalSafeBackfillFixture(count: 10, captured: false)
        let context = fixture.context
        fixture.tasks[0].title = "명령 전에 보존할 제목"
        var checks = 0
        do {
            try PersistenceCommandService.perform(in: context) {
                if !cancel { fixture.tasks[1].completedAt = fixture.completion.addingTimeInterval(86_400) }
                _ = try TaskActivityBackfillService.backfillLegacyCompletions(
                    in: context, createdAt: fixture.createdAt, isCancelled: {
                        checks += 1
                        return cancel && checks >= 5
                    })
                throw GoalSafeBackfillFailure.afterMutation
            }
            Issue.record("Expected the command to throw and roll back")
        } catch is CancellationError {
            #expect(cancel && checks == 5)
        } catch GoalSafeBackfillFailure.afterMutation {
            #expect(!cancel)
        }
        #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
        #expect(fixture.tasks[0].title == "명령 전에 보존할 제목")
        #expect(fixture.tasks[1].completedAt == fixture.completion.addingTimeInterval(60))
        #expect(!context.hasChanges)
    }
}

@Test @MainActor
func goalBackfillCleanCapturedAndMissingRemainIdempotentAcrossPages() throws {
    let origins: [TaskCompletionActivityOrigin?] = [.captured, .legacyBackfill, nil]
    for existingOrigin in origins {
        let captured = existingOrigin != nil
        let fixture = try goalSafeBackfillFixture(count: 201, captured: captured)
        let context = fixture.context
        if let existingOrigin {
            for row in fixture.activities { row.originRawValue = existingOrigin.rawValue }
            try context.save()
        }
        let taskValues = fixture.tasks.map(goalSafeTaskValue)
        let physicalBefore = fixture.activities.map(goalSafePhysicalActivityValue)
        let first = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
        #expect(first == TaskActivityBackfillReport(scannedTasks: 201, insertedActivities: captured ? 0 : 201))
        #expect(fixture.tasks.map(goalSafeTaskValue) == taskValues)
        #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 201)
        #expect(context.hasChanges == !captured)
        let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        if captured { #expect(rows.map(goalSafePhysicalActivityValue).sorted() == physicalBefore.sorted()) }
        else { #expect(rows.map(goalSafeActivityValue).sorted() == fixture.tasks.map {
            goalSafeLegacyValue($0, createdAt: fixture.createdAt) }.sorted()) }
        let second = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
        #expect(second == TaskActivityBackfillReport(scannedTasks: 201, insertedActivities: 0))
        #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 201)
        #expect(fixture.tasks.map(goalSafeTaskValue) == taskValues)
    }
}

@Test @MainActor
func goalBackfillPositiveProofMissesKeepNaturalKeyRecordMeaning() throws {
    let fixture = try goalSafeBackfillFixture(count: 6, captured: true)
    let context = fixture.context
    fixture.activities[0].id = goalSafeID(9, 0) // Wrong logical activity ID, but same natural key blocks.
    fixture.activities[1].taskId = goalSafeID(9, 1) // Canonical ID for target, unrelated natural key cannot block.
    fixture.activities[2].activityDayKey = TaskActivityRules.legacyDayKey(for: fixture.completion.addingTimeInterval(86_400))
    fixture.activities[3].originRawValue = "unknown-origin" // Existing legacy record semantics still block.
    fixture.activities[4].supersededAt = fixture.createdAt
    fixture.activities[5].occurredAt = fixture.completion.addingTimeInterval(86_400) // Wrong timestamp day: fallback.
    try context.save()
    let preserved = fixture.activities.map(goalSafePhysicalActivityValue)
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
    #expect(report == TaskActivityBackfillReport(scannedTasks: 6, insertedActivities: 3))
    let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == 9)
    #expect(Set(preserved).isSubset(of: Set(rows.map(goalSafePhysicalActivityValue))))
    for index in [1, 2, 4] {
        #expect(rows.contains { goalSafeActivityValue($0) == goalSafeLegacyValue(fixture.tasks[index], createdAt: fixture.createdAt) })
    }
}

@Test @MainActor
func goalBackfillCappedDuplicatePrefixDoesNotProveMissingKeysAbsent() throws {
    let fixture = try goalSafeBackfillFixture(count: 3, captured: true)
    let context = fixture.context
    context.delete(fixture.activities[2])
    var copies: [TaskCompletionActivity] = []
    for index in 0..<205 {
        let copy = goalSafeCaptured(fixture.tasks[0], index: index)
        copy.instanceID = goalSafeID(0, index) // Sort ahead of the other canonical natural keys.
        copy.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
        context.insert(copy)
        copies.append(copy)
    }
    try context.save()
    let before = try context.fetch(FetchDescriptor<TaskCompletionActivity>()).map(goalSafePhysicalActivityValue)
    #expect(before.count == 207)
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: fixture.createdAt)
    #expect(report == TaskActivityBackfillReport(scannedTasks: 3, insertedActivities: 1))
    let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == 208 && Set(rows.map(\.instanceID)).count == 208)
    #expect(Set(before).isSubset(of: Set(rows.map(goalSafePhysicalActivityValue))))
    #expect(rows.contains { goalSafeActivityValue($0) == goalSafeLegacyValue(fixture.tasks[2], createdAt: fixture.createdAt) })
    withExtendedLifetime(copies) {}
}

@Test @MainActor
func goalBackfillIgnoresEarlierPositiveProofAfterContextBecomesDirty() throws {
    let fixture = try goalSafeBackfillFixture(count: 3, captured: true)
    let context = fixture.context
    context.delete(fixture.activities[0])
    try context.save()
    var checks = 0
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(
        in: context, createdAt: fixture.createdAt, isCancelled: {
            checks += 1
            if checks == 3 { fixture.activities[1].supersededAt = fixture.createdAt }
            return false
        })
    #expect(report == TaskActivityBackfillReport(scannedTasks: 3, insertedActivities: 2))
    #expect(fixture.activities[1].supersededAt == fixture.createdAt)
    let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == 4)
    for index in [0, 1] {
        #expect(rows.contains { goalSafeActivityValue($0) == goalSafeLegacyValue(fixture.tasks[index], createdAt: fixture.createdAt) })
    }
}

@Test @MainActor
func goalBackfillNoncanonicalFiniteDateStillUsesExistingRecordFallback() throws {
    let fixture = try goalSafeBackfillFixture(count: 1, captured: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let date = try #require(calendar.date(from: DateComponents(year: 10_000, month: 1, day: 1)))
    let day = TaskActivityRules.legacyDayKey(for: date)
    #expect(date.timeIntervalSinceReferenceDate.isFinite && DayKey.date(from: day) == nil)
    fixture.tasks[0].completedAt = date
    fixture.activities[0].occurredAt = date
    fixture.activities[0].activityDayKey = day
    fixture.activities[0].id = TaskActivityRules.logicalID(taskID: fixture.tasks[0].id, activityDayKey: day)
    try fixture.context.save()
    let preserved = goalSafePhysicalActivityValue(fixture.activities[0])
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: fixture.context, createdAt: fixture.createdAt)
    #expect(report == TaskActivityBackfillReport(scannedTasks: 1, insertedActivities: 0))
    #expect(goalSafePhysicalActivityValue(fixture.activities[0]) == preserved)
    #expect(!fixture.context.hasChanges)
}

private enum GoalSafeBackfillFailure: Error { case afterMutation }

private struct GoalSafeBackfillFixture {
    let container: ModelContainer
    let context: ModelContext
    var tasks: [Task]
    var activities: [TaskCompletionActivity]
    let completion: Date
    let createdAt: Date
}

@MainActor
private func goalSafeBackfillFixture(count: Int, captured: Bool) throws -> GoalSafeBackfillFixture {
    let completion = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let tasks = (0..<count).map { goalSafeBackfillTask($0, completion: completion) }
    let activities = captured ? tasks.enumerated().map { goalSafeCaptured($0.element, index: $0.offset) } : []
    for task in tasks { context.insert(task) }
    for activity in activities { context.insert(activity) }
    try context.save()
    return GoalSafeBackfillFixture(container: container, context: context, tasks: tasks, activities: activities,
        completion: completion, createdAt: completion.addingTimeInterval(86_400))
}

@MainActor
private func goalSafeBackfillApplyDirty(_ fixture: inout GoalSafeBackfillFixture) {
    let context = fixture.context
    context.delete(fixture.activities[0])
    fixture.tasks[1].completedAt = fixture.completion.addingTimeInterval(86_400)
    fixture.tasks[2].status = TaskStatus.todo.rawValue
    fixture.tasks[2].completedAt = nil
    context.delete(fixture.tasks[3])
    fixture.tasks[4].supersededAt = fixture.createdAt
    fixture.activities[5].supersededAt = fixture.createdAt
    fixture.activities[6].activityDayKey = TaskActivityRules.legacyDayKey(for: fixture.completion.addingTimeInterval(86_400))
    let count = fixture.tasks.count
    for index in [count, count + 1] {
        let task = goalSafeBackfillTask(index, completion: fixture.completion)
        context.insert(task)
        fixture.tasks.append(task)
    }
    let pending = goalSafeCaptured(fixture.tasks[count + 1], index: count + 1)
    context.insert(pending)
    fixture.activities.append(pending)
}

private func goalSafeBackfillTask(_ index: Int, completion: Date, logicalID: UUID? = nil) -> Task {
    let occurred = completion.addingTimeInterval(Double(index % 5) * 60)
    let task = Task(id: logicalID ?? goalSafeID(1, index), instanceID: goalSafeID(2, index),
        title: "Backfill \(index)", status: .done, plannedAt: completion.addingTimeInterval(-2 * 86_400),
        order: Double(index), createdAt: completion.addingTimeInterval(-30 * 86_400), updatedAt: occurred.addingTimeInterval(5))
    task.completedAt = occurred
    task.completedDayKey = "2026-09-29"
    return task
}

private func goalSafeCaptured(_ task: Task, index: Int) -> TaskCompletionActivity {
    let occurred = task.completedAt!
    let day = TaskActivityRules.legacyDayKey(for: occurred)
    return TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day),
        instanceID: goalSafeID(3, index), taskId: task.id, activityDayKey: day, occurredAt: occurred,
        origin: .captured, createdAt: occurred.addingTimeInterval(1), updatedAt: occurred.addingTimeInterval(2))
}

private func goalSafeTaskValue(_ task: Task) -> String {
    [task.id.uuidString, task.instanceID.uuidString, task.title, task.status, task.plannedDayKey,
     goalSafeDate(task.plannedAt), String(task.order), task.completedDayKey ?? "nil", goalSafeDate(task.completedAt),
     task.archivedDayKey ?? "nil", goalSafeDate(task.archivedAt), goalSafeDate(task.createdAt),
     goalSafeDate(task.updatedAt), goalSafeDate(task.supersededAt)].joined(separator: "|")
}

private func goalSafeActivityValue(_ row: TaskCompletionActivity) -> String {
    [row.id.uuidString, row.taskId.uuidString, row.activityDayKey, goalSafeDate(row.occurredAt), row.originRawValue,
     goalSafeDate(row.createdAt), goalSafeDate(row.updatedAt), goalSafeDate(row.supersededAt)].joined(separator: "|")
}

private func goalSafePhysicalActivityValue(_ row: TaskCompletionActivity) -> String { "\(row.instanceID)|\(goalSafeActivityValue(row))" }

private func goalSafeLegacyValue(_ task: Task, createdAt: Date) -> String {
    let completion = task.completedAt!
    let day = TaskActivityRules.legacyDayKey(for: completion)
    return [TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day).uuidString, task.id.uuidString, day,
        goalSafeDate(completion), TaskCompletionActivityOrigin.legacyBackfill.rawValue, goalSafeDate(createdAt),
        goalSafeDate(createdAt), "nil"].joined(separator: "|")
}

private func goalSafeDate(_ value: Date?) -> String { value.map { String($0.timeIntervalSince1970) } ?? "nil" }

private func goalSafeID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "40000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
