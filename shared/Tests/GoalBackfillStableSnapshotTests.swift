import Foundation
import SwiftData
import Testing
import EasyTaskCore

// Public-service acceptance gates shared by the original defaulted callback API
// and a default two-argument / explicit three-argument overload implementation.
// Deliberately synchronous: no yields, sleeps, save, or user callback is hidden
// inside a default invocation. Autosave remains enabled on both caller/readers.

@Test(arguments: ["memory", "local-file"])
@MainActor
func goalBackfillStableDefaultMatchesExplicitWithoutSavingOrReplacingDrafts(storage: String) throws {
    var results: [(TaskActivityBackfillReport, GoalStableSemanticStore)] = []
    for explicit in [false, true] {
        let result = try goalStableWithFixture(storage: storage, count: 12) { fixture in
            let context = fixture.source
            fixture.memo.content = "기존 미저장 초안 · 감사 Café 👨‍👩‍👧‍👦"
            fixture.memo.isPinned = true
            fixture.memo.preferredModeRawValue = "checklist"
            fixture.memo.updatedAt = goalStableCreated.addingTimeInterval(9)
            let draft = goalStableMemo(1, content: "새 미저장 초안\n둘째 줄")
            context.insert(draft)
            fixture.tasks[0].completedAt = goalStableCompletion.addingTimeInterval(86_400)
            fixture.tasks[0].note = "pending note"
            fixture.tasks[0].tags = ["한글", "Café"]
            fixture.tasks[0].order = 123.5
            fixture.activities[1].taskId = goalStableID(9, 1)
            fixture.activities[1].updatedAt = goalStableCreated.addingTimeInterval(100)
            context.delete(fixture.activities[2])
            fixture.activities[3].supersededAt = goalStableCreated
            fixture.tasks[4].status = TaskStatus.todo.rawValue
            fixture.tasks[4].completedAt = nil
            let blocked = goalStableTask(12)
            let missing = goalStableTask(13)
            context.insert(blocked)
            context.insert(missing)
            let pendingActivity = goalStableActivity(12, taskID: blocked.id)
            pendingActivity.originRawValue = "future-unknown-origin"
            pendingActivity.updatedAt = goalStableCreated.addingTimeInterval(101)
            context.insert(pendingActivity)
            let unrelatedActivity = goalStableActivity(14, taskID: goalStableID(9, 14))
            context.insert(unrelatedActivity)

            let savedBefore = try goalStableSavedStore(fixture)
            let retainedTasks = fixture.tasks + [blocked, missing]
            let retainedActivities = fixture.activities.filter { $0 !== fixture.activities[2] }
                + [pendingActivity, unrelatedActivity]
            let taskFields = retainedTasks.map(goalStableTaskFields)
            let activityFields = retainedActivities.map { goalStableActivityFields($0) }
            let memoFields = [fixture.memo, draft].map(goalStableMemoFields)
            let taskPIDs = retainedTasks.map(\.persistentModelID)
            let activityPIDs = retainedActivities.map(\.persistentModelID)
            let memoPIDs = [fixture.memo, draft].map(\.persistentModelID)
            let pendingBefore = GoalStablePending(context)
            #expect(!pendingBefore.inserted.isEmpty && context.hasChanges)
            #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0)

            let report = try goalStableInvoke(in: context, explicit: explicit)
            #expect(report == TaskActivityBackfillReport(scannedTasks: 13, insertedActivities: 5))
            #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0)
            #expect(retainedTasks.map(goalStableTaskFields) == taskFields)
            #expect(retainedActivities.map { goalStableActivityFields($0) } == activityFields)
            #expect([fixture.memo, draft].map(goalStableMemoFields) == memoFields)
            #expect(retainedTasks.map(\.persistentModelID) == taskPIDs)
            #expect(retainedActivities.map(\.persistentModelID) == activityPIDs)
            #expect([fixture.memo, draft].map(\.persistentModelID) == memoPIDs)
            goalStableExpectRegistered(retainedTasks, in: context)
            goalStableExpectRegistered(retainedActivities, in: context)
            goalStableExpectRegistered([fixture.memo, draft], in: context)

            let generated = GoalStablePending(context).inserted.subtracting(pendingBefore.inserted)
            #expect(generated.count == 5)
            #expect(GoalStablePending(context).removing(generated) == pendingBefore)
            #expect(try goalStableSavedStore(fixture) == savedBefore)
            #expect(context.hasChanges && !fixture.reader.hasChanges)
            let semantic = try goalStableStore(in: context, ignoringActivityInstances: generated)
            #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0)
            return (report, semantic)
        }
        results.append(result)
    }
    #expect(results[0].0 == results[1].0)
    // Generated activity instance UUIDs/PIDs belong to each physical store;
    // all other activity fields and every seeded instance UUID remain compared.
    #expect(results[0].1 == results[1].1)
}

@Test(arguments: ["memory", "local-file"])
@MainActor
func goalBackfillStableIndexDeduplicatesItsOwnInsertsAcrossSavedTaskPages(storage: String) throws {
    var results: [(TaskActivityBackfillReport, GoalStableSemanticStore)] = []
    for explicit in [false, true] {
        let result = try goalStableWithFixture(storage: storage, count: 205,
            activityIndices: [1, 2, 3, 4], duplicateTaskIndices: [199, 200, 204]) { fixture in
            let context = fixture.source
            fixture.activities[0].originRawValue = "unknown-origin-still-blocks-legacy"
            try context.save() // Fixture preparation, before the invocation interval.
            fixture.sourceSaves.reset()
            fixture.activities[1].taskId = goalStableID(9, 2) // Saved physical key 2 moved out.
            fixture.activities[1].activityDayKey = "2040-02-03"
            context.delete(fixture.activities[2]) // Saved key 3 deleted, key 4 remains clean.
            let pendingBlocker = goalStableActivity(5, taskID: fixture.tasks[5].id)
            pendingBlocker.originRawValue = "unknown-pending-origin"
            context.insert(pendingBlocker)
            fixture.memo.content = "跨 page pending memo must stay unsaved"
            let savedBefore = try goalStableSavedStore(fixture)
            let taskFields = fixture.tasks.map(goalStableTaskFields)
            let movedFields = goalStableActivityFields(fixture.activities[1])
            let movedPID = fixture.activities[1].persistentModelID
            let pendingPID = pendingBlocker.persistentModelID
            let pendingBefore = GoalStablePending(context)

            let first = try goalStableInvoke(in: context, explicit: explicit)
            // 205 physical Tasks, 202 natural keys. Keys 1/4/5 block; the four
            // physical copies of key 0 must produce only one new activity.
            #expect(first == TaskActivityBackfillReport(scannedTasks: 205, insertedActivities: 199))
            #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0)
            let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
            let day = TaskActivityRules.legacyDayKey(for: goalStableCompletion)
            let active = rows.filter { $0.supersededAt == nil && $0.activityDayKey == day }
            #expect(active.count == 202)
            #expect(active.filter { $0.taskId == fixture.tasks[0].id }.count == 1)
            #expect(Set(active.map(\.taskId)).count == 202)
            for index in [0, 2, 3, 6, 198, 201, 203] {
                let inserted = try #require(active.first { $0.taskId == fixture.tasks[index].id })
                #expect(inserted.id == TaskActivityRules.logicalID(taskID: fixture.tasks[index].id, activityDayKey: day))
                #expect(inserted.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue)
                #expect(inserted.occurredAt == goalStableCompletion)
                #expect(inserted.createdAt == goalStableCreated && inserted.updatedAt == goalStableCreated)
            }
            #expect(fixture.tasks.map(goalStableTaskFields) == taskFields)
            #expect(goalStableActivityFields(fixture.activities[1]) == movedFields)
            #expect(fixture.activities[1].persistentModelID == movedPID)
            #expect(pendingBlocker.persistentModelID == pendingPID)
            let generated = GoalStablePending(context).inserted.subtracting(pendingBefore.inserted)
            #expect(generated.count == 199)
            #expect(GoalStablePending(context).removing(generated) == pendingBefore)
            let beforeSecond = try goalStableStore(in: context)
            let physicalBeforeSecond = Set(rows.map(\.persistentModelID))
            let second = try goalStableInvoke(in: context, explicit: explicit)
            #expect(second == TaskActivityBackfillReport(scannedTasks: 205, insertedActivities: 0))
            #expect(try goalStableStore(in: context) == beforeSecond)
            #expect(Set(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).map(\.persistentModelID)) == physicalBeforeSecond)
            #expect(try goalStableSavedStore(fixture) == savedBefore)
            #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0)
            return (first, try goalStableStore(in: context, ignoringActivityInstances: generated))
        }
        results.append(result)
    }
    #expect(results[0].0 == results[1].0)
    #expect(results[0].1 == results[1].1)
}

@Test(arguments: ["memory", "local-file"])
@MainActor
func goalBackfillStableSnapshotLeavesCommitAndFullRollbackToCommand(storage: String) throws {
    try goalStableWithFixture(storage: storage, count: 8, activityIndices: []) { fixture in
        let context = fixture.source
        fixture.tasks[0].title = "caller draft committed before rollback point"
        fixture.tasks[0].note = "caller note"
        fixture.memo.content = "기존 caller 초안은 command 시작 때 저장"
        let draft = goalStableMemo(1, content: "새 caller 초안도 pre-command commit")
        context.insert(draft)
        let callerActivity = goalStableActivity(0, taskID: fixture.tasks[0].id)
        callerActivity.originRawValue = "unknown-caller-origin"
        context.insert(callerActivity)
        let expectedCommitted = try goalStableStore(in: context)
        let originallySaved = try goalStableSavedStore(fixture)
        #expect(expectedCommitted != originallySaved)
        var commandPIDs: Set<PersistentIdentifier> = []
        do {
            try PersistenceCommandService.perform(in: context) {
                // perform intentionally saves caller pending edits before its
                // rollback point. Backfill itself must never save afterward.
                #expect(fixture.sourceSaves.count == 1)
                #expect(try goalStableStore(in: context) == expectedCommitted)
                commandPIDs = try goalStablePhysicalIDs(in: context)
                fixture.tasks[0].note = "must roll back"
                fixture.tasks[0].tags = ["must roll back"]
                fixture.memo.content = "must roll back memo"
                draft.isPinned = true
                context.delete(callerActivity)
                let report = try TaskActivityBackfillService.backfillLegacyCompletions(
                    in: context, createdAt: goalStableCreated)
                #expect(report == TaskActivityBackfillReport(scannedTasks: 8, insertedActivities: 8))
                #expect(fixture.sourceSaves.count == 1 && fixture.readerSaves.count == 0)
                throw GoalStableFailure.afterBackfill
            }
            Issue.record("Expected the command mutation to throw")
        } catch GoalStableFailure.afterBackfill {
            // Expected: the command rolls back only changes after its pre-save.
        }
        #expect(try goalStableStore(in: context) == expectedCommitted)
        #expect(try goalStableSavedStore(fixture) == expectedCommitted)
        #expect(try goalStablePhysicalIDs(in: context) == commandPIDs)
        #expect(!context.hasChanges && !fixture.reader.hasChanges)
        #expect(fixture.sourceSaves.count == 1 && fixture.readerSaves.count == 0)
    }
}

@Test(arguments: ["memory", "local-file"])
@MainActor
func goalBackfillExplicitCallbackRechecksChangedDeletedInsertedAndExternalKeys(storage: String) throws {
    try goalStableWithFixture(storage: storage, count: 6,
        activityIndices: [1, 2, 3], duplicateTaskIndices: [5]) { fixture in
        let context = fixture.source
        let writer = ModelContext(fixture.container)
        writer.autosaveEnabled = true
        let writerSaves = GoalStableSaveCounter(context: writer)
        let externalInstance = fixture.activities[2].instanceID
        let external = try #require(try writer.fetch(FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate { $0.instanceID == externalInstance })).first)
        let savedBefore = try goalStableSavedStore(fixture)
        fixture.memo.content = "callback must preserve this pending draft"
        let memoBefore = goalStableMemoFields(fixture.memo)
        var didMutate = false
        var pendingBlocker: TaskCompletionActivity?
        var blockerPID: PersistentIdentifier?
        let report = try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context, createdAt: goalStableCreated, isCancelled: {
                // Semantic barrier, not a fixed callback ordinal or fetch limit:
                // key 0's first insertion has happened, key 1 has not been read.
                let insertedFirst = context.insertedModelsArray.contains {
                    guard let row = $0 as? TaskCompletionActivity else { return false }
                    return row.taskId == fixture.tasks[0].id
                }
                if insertedFirst && !didMutate {
                    didMutate = true
                    fixture.activities[0].taskId = goalStableID(9, 1)
                    fixture.activities[0].updatedAt = goalStableCreated.addingTimeInterval(100)
                    context.delete(fixture.activities[1])
                    external.supersededAt = goalStableCreated
                    external.updatedAt = goalStableCreated.addingTimeInterval(101)
                    // The Bool callback cannot throw, so report a failed fixture
                    // write as an issue instead of ignoring it or weakening facts.
                    do { try writer.save() } catch { Issue.record(error) }
                    let blocker = goalStableActivity(4, taskID: fixture.tasks[4].id)
                    blocker.originRawValue = "future-callback-origin"
                    context.insert(blocker)
                    pendingBlocker = blocker
                    blockerPID = blocker.persistentModelID
                }
                return false
            })
        #expect(didMutate)
        #expect(report == TaskActivityBackfillReport(scannedTasks: 6, insertedActivities: 4))
        #expect(fixture.sourceSaves.count == 0 && fixture.readerSaves.count == 0 && writerSaves.count == 1)
        #expect(goalStableMemoFields(fixture.memo) == memoBefore)
        let blocker = try #require(pendingBlocker)
        #expect(blocker.persistentModelID == blockerPID)
        #expect(blocker.originRawValue == "future-callback-origin")
        #expect(fixture.activities[0].taskId == goalStableID(9, 1))
        #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == Set([fixture.activities[1].persistentModelID]))
        let inserted = context.insertedModelsArray.compactMap { $0 as? TaskCompletionActivity }
        let legacy = inserted.filter { $0.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue }
        #expect(legacy.count == 4)
        #expect(Set(legacy.map(\.taskId)) == Set((0...3).map { fixture.tasks[$0].id }))
        #expect(legacy.allSatisfy { $0.occurredAt == goalStableCompletion && $0.createdAt == goalStableCreated })
        #expect(inserted.filter { $0.taskId == fixture.tasks[0].id }.count == 1)
        let expectedSaved = GoalStableSemanticStore(tasks: savedBefore.tasks,
            activities: savedBefore.activities.map { fields in
                guard fields[1] == externalInstance.uuidString else { return fields }
                var changed = fields
                changed[7] = goalStableDate(goalStableCreated.addingTimeInterval(101))
                changed[8] = goalStableDate(goalStableCreated)
                return changed
            }.sorted { $0.lexicographicallyPrecedes($1) }, memos: savedBefore.memos)
        #expect(try goalStableSavedStore(fixture) == expectedSaved)
        #expect(context.hasChanges && !writer.hasChanges && !fixture.reader.hasChanges)
        withExtendedLifetime(writerSaves) {}
    }
}

private let goalStableCompletion = Date(timeIntervalSince1970: 1_790_856_000)
private let goalStableCreated = goalStableCompletion.addingTimeInterval(86_400)
private enum GoalStableFailure: Error { case afterBackfill }

private struct GoalStableSemanticStore: Equatable {
    let tasks: [[String]]
    let activities: [[String]]
    let memos: [[String]]
}

private struct GoalStableFixture {
    let container: ModelContainer
    let source: ModelContext
    let reader: ModelContext
    let sourceSaves: GoalStableSaveCounter
    let readerSaves: GoalStableSaveCounter
    let tasks: [Task]
    let activities: [TaskCompletionActivity]
    let memo: Memo
}

@MainActor
private func goalStableWithFixture<Result>(storage: String, count: Int,
    activityIndices: [Int]? = nil, duplicateTaskIndices: [Int] = [],
    _ body: (GoalStableFixture) throws -> Result
) throws -> Result {
    let directory: URL?
    let container: ModelContainer
    if storage == "local-file" {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlanBase-GoalBackfillStable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directory = url
        container = try PlanBaseContainerFactory.makePersistent(
            storeURL: url.appendingPathComponent("fixture.store"), mode: .local)
    } else {
        directory = nil
        container = try PlanBaseContainerFactory.makeInMemory()
    }
    defer {
        withExtendedLifetime(container) {}
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
    let source = container.mainContext
    source.autosaveEnabled = true
    let sourceSaves = GoalStableSaveCounter(context: source)
    let tasks = (0..<count).map { index in
        goalStableTask(index, logicalID: duplicateTaskIndices.contains(index) ? goalStableID(1, 0) : nil)
    }
    let activities = (activityIndices ?? Array(0..<count)).map { goalStableActivity($0, taskID: tasks[$0].id) }
    let memo = goalStableMemo(0, content: "saved caller memo")
    for task in tasks { source.insert(task) }
    for activity in activities { source.insert(activity) }
    source.insert(memo)
    try source.save()
    // Calibration ensures a zero later really means no synchronous didSave,
    // rather than an observer that never matches the public SDK notification.
    #expect(sourceSaves.count == 1)
    sourceSaves.reset()
    let reader = ModelContext(container)
    reader.autosaveEnabled = true
    let readerSaves = GoalStableSaveCounter(context: reader)
    _ = try goalStableStore(in: reader)
    #expect(!source.hasChanges && !reader.hasChanges)
    return try body(GoalStableFixture(container: container, source: source, reader: reader,
        sourceSaves: sourceSaves, readerSaves: readerSaves, tasks: tasks, activities: activities, memo: memo))
}

@MainActor
private func goalStableInvoke(in context: ModelContext, explicit: Bool) throws -> TaskActivityBackfillReport {
    if explicit {
        return try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context, createdAt: goalStableCreated, isCancelled: { false })
    }
    return try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: goalStableCreated)
}

@MainActor
private func goalStableSavedStore(_ fixture: GoalStableFixture) throws -> GoalStableSemanticStore {
    // A new clean reader avoids asserting refresh of a registered object that
    // the service does not read. This only observes this isolated fixture store.
    let reader = ModelContext(fixture.container)
    reader.autosaveEnabled = true
    let saves = GoalStableSaveCounter(context: reader)
    let value = try goalStableStore(in: reader)
    #expect(saves.count == 0 && !reader.hasChanges)
    withExtendedLifetime(saves) {}
    return value
}

@MainActor
private func goalStableStore(in context: ModelContext,
    ignoringActivityInstances generated: Set<PersistentIdentifier> = []
) throws -> GoalStableSemanticStore {
    GoalStableSemanticStore(
        tasks: try context.fetch(FetchDescriptor<Task>()).map(goalStableTaskFields)
            .sorted { $0.lexicographicallyPrecedes($1) },
        activities: try context.fetch(FetchDescriptor<TaskCompletionActivity>()).map {
            goalStableActivityFields($0, includeInstance: !generated.contains($0.persistentModelID))
        }.sorted { $0.lexicographicallyPrecedes($1) },
        memos: try context.fetch(FetchDescriptor<Memo>()).map(goalStableMemoFields)
            .sorted { $0.lexicographicallyPrecedes($1) })
}

@MainActor
private func goalStablePhysicalIDs(in context: ModelContext) throws -> Set<PersistentIdentifier> {
    Set(try context.fetch(FetchDescriptor<Task>()).map(\.persistentModelID))
        .union(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).map(\.persistentModelID))
        .union(try context.fetch(FetchDescriptor<Memo>()).map(\.persistentModelID))
}

@MainActor
private func goalStableExpectRegistered<Model: PersistentModel>(_ models: [Model], in context: ModelContext) {
    for row in models {
        let registered: Model? = context.registeredModel(for: row.persistentModelID)
        #expect(registered === row)
    }
}

private struct GoalStablePending: Equatable {
    let inserted: Set<PersistentIdentifier>
    let changed: Set<PersistentIdentifier>
    let deleted: Set<PersistentIdentifier>
    @MainActor init(_ context: ModelContext) {
        inserted = Set(context.insertedModelsArray.map(\.persistentModelID))
        changed = Set(context.changedModelsArray.map(\.persistentModelID))
        deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
    }
    private init(inserted: Set<PersistentIdentifier>, changed: Set<PersistentIdentifier>, deleted: Set<PersistentIdentifier>) {
        self.inserted = inserted; self.changed = changed; self.deleted = deleted
    }
    func removing(_ identifiers: Set<PersistentIdentifier>) -> Self {
        Self(inserted: inserted.subtracting(identifiers), changed: changed.subtracting(identifiers),
            deleted: deleted.subtracting(identifiers))
    }
}

private final class GoalStableSaveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var observer: (any NSObjectProtocol)?
    var count: Int { lock.withLock { value } }
    init(context: ModelContext) {
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave,
            object: context, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.value += 1 }
        }
    }
    func reset() { lock.withLock { value = 0 } }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

private func goalStableID(_ family: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "64000000-%04X-4000-8000-%012X", family, index))!
}

private func goalStableTask(_ index: Int, logicalID: UUID? = nil) -> Task {
    let task = Task(id: logicalID ?? goalStableID(1, index), instanceID: goalStableID(2, index),
        title: "Stable \(index) · Café", note: "saved note \(index)", status: .done,
        plannedAt: goalStableCompletion.addingTimeInterval(-86_400), order: Double(index),
        eventId: goalStableID(7, index), templatePlacementId: goalStableID(8, index),
        priority: .high, tags: ["saved", "감사"], estimatedMinutes: 25,
        reminderAt: goalStableCompletion.addingTimeInterval(60),
        createdAt: goalStableCompletion.addingTimeInterval(-2 * 86_400), updatedAt: goalStableCompletion)
    task.completedAt = goalStableCompletion
    task.completedDayKey = "2026-09-29" // Legacy timestamp, not this stale key, determines activity day.
    return task
}

private func goalStableActivity(_ index: Int, taskID: UUID) -> TaskCompletionActivity {
    let day = TaskActivityRules.legacyDayKey(for: goalStableCompletion)
    return TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: day),
        instanceID: goalStableID(3, index), taskId: taskID, activityDayKey: day,
        occurredAt: goalStableCompletion, origin: .captured,
        createdAt: goalStableCompletion.addingTimeInterval(1), updatedAt: goalStableCompletion.addingTimeInterval(2))
}

private func goalStableMemo(_ index: Int, content: String) -> Memo {
    Memo(id: goalStableID(4, index), instanceID: goalStableID(5, index), content: content,
        createdAt: goalStableCompletion, updatedAt: goalStableCompletion)
}

private func goalStableDate(_ date: Date?) -> String {
    date.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "nil"
}

private func goalStableTaskFields(_ row: Task) -> [String] {
    [row.id.uuidString, row.instanceID.uuidString, row.title, row.note ?? "nil", row.status,
     goalStableDate(row.plannedAt), row.plannedDayKey, String(row.order.bitPattern),
     row.eventId?.uuidString ?? "nil", row.templatePlacementId?.uuidString ?? "nil", row.priority ?? "nil",
     String(reflecting: row.tags), row.estimatedMinutes.map(String.init) ?? "nil", goalStableDate(row.reminderAt),
     goalStableDate(row.createdAt), goalStableDate(row.updatedAt), goalStableDate(row.completedAt),
     row.completedDayKey ?? "nil", goalStableDate(row.archivedAt), row.archivedDayKey ?? "nil", goalStableDate(row.supersededAt)]
}

private func goalStableActivityFields(_ row: TaskCompletionActivity, includeInstance: Bool = true) -> [String] {
    [row.id.uuidString, includeInstance ? row.instanceID.uuidString : "generated-instance",
     row.taskId.uuidString, row.activityDayKey, goalStableDate(row.occurredAt), row.originRawValue,
     goalStableDate(row.createdAt), goalStableDate(row.updatedAt), goalStableDate(row.supersededAt)]
}

private func goalStableMemoFields(_ row: Memo) -> [String] {
    [row.id.uuidString, row.instanceID.uuidString, row.content, String(row.isPinned), row.preferredModeRawValue,
     goalStableDate(row.createdAt), goalStableDate(row.updatedAt), goalStableDate(row.supersededAt)]
}
