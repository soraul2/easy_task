import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Ordinary, baseline-compatible public API tests. No candidate helper, cache,
// performance switch, external store, or CloudKit is used as an expectation oracle.
@Test(arguments: [TaskCompletionActivityOrigin.captured, .legacyBackfill], [
    "none", "captured", "legacy", "unknown-origin", "superseded",
    "wrong-logical-id", "same-logical-id-other-task", "same-logical-id-other-day"
])
@MainActor
func goalActivityRecordUsesActiveNaturalKeyAndRequestedOrigin(
    requested: TaskCompletionActivityOrigin, condition: String
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = goalRecordDate
    let taskID = goalRecordTaskID
    let day = DayKey.key(for: date)
    var existing: TaskCompletionActivity?
    if condition != "none" {
        let row = goalRecordSeed(taskID: taskID, day: day, at: date)
        switch condition {
        case "legacy": row.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
        case "unknown-origin": row.originRawValue = "unknown-origin"
        case "superseded": row.supersededAt = date.addingTimeInterval(30)
        case "wrong-logical-id": row.id = goalRecordOtherTaskID
        case "same-logical-id-other-task": row.taskId = goalRecordOtherTaskID
        case "same-logical-id-other-day": row.activityDayKey = goalRecordOtherDay
        default: break
        }
        context.insert(row)
        existing = row
    }
    try context.save()
    let before = existing.map { GoalRecordActivityValue($0) }
    let savedBefore = try goalRecordSavedValues(in: container)
    #expect(!context.hasChanges)

    let result = try TaskActivityService.record(
        taskID: taskID, activityDayKey: day, occurredAt: date.addingTimeInterval(60),
        origin: requested, createdAt: date.addingTimeInterval(120), in: context)
    let blocks: Bool
    switch condition {
    case "captured", "wrong-logical-id": blocks = true
    case "legacy", "unknown-origin": blocks = requested == .legacyBackfill
    default: blocks = false
    }
    #expect((result == nil) == blocks)
    if !blocks {
        let inserted = try #require(result)
        goalRecordExpectNew(inserted, taskID: taskID, day: day, origin: requested,
            occurredAt: date.addingTimeInterval(60), createdAt: date.addingTimeInterval(120), in: context)
        if let existing {
            #expect(inserted.persistentModelID != existing.persistentModelID)
            #expect(inserted.instanceID != existing.instanceID)
        }
    }
    if let existing, let before { #expect(GoalRecordActivityValue(existing) == before) }
    let rows = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(rows.count == (existing == nil ? 0 : 1) + (blocks ? 0 : 1))
    #expect(context.hasChanges == !blocks)
    // A separate context only reads; record did not save or alter a saved row.
    #expect(try goalRecordSavedValues(in: container) == savedBefore)
}

@Test(arguments: [TaskCompletionActivityOrigin.captured, .legacyBackfill], [
    "move-task-out", "move-day-out", "supersede", "delete",
    "origin-to-legacy", "origin-to-unknown", "move-task-in", "move-day-in",
    "revive", "origin-to-captured", "insert", "insert-delete"
])
@MainActor
func goalActivityRecordUsesCurrentPendingValuesAndPreservesCallerEdits(
    requested: TaskCompletionActivityOrigin, condition: String
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = DayKey.key(for: goalRecordDate)
    let row = goalRecordSeed(taskID: goalRecordTaskID, day: day, at: goalRecordDate)
    switch condition {
    case "move-task-in": row.taskId = goalRecordOtherTaskID
    case "move-day-in": row.activityDayKey = goalRecordOtherDay
    case "revive": row.supersededAt = goalRecordDate
    case "origin-to-captured": row.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
    default: break
    }
    if condition != "insert" && condition != "insert-delete" { context.insert(row) }
    try context.save()
    let savedBefore = try goalRecordSavedValues(in: container)
    let draft = Memo(content: "record 전 미저장 메모", createdAt: goalRecordDate, updatedAt: goalRecordDate)
    context.insert(draft)
    draft.isPinned = true
    let draftBefore = GoalRecordMemoValue(draft)
    var deleted = false
    switch condition {
    case "move-task-out": row.taskId = goalRecordOtherTaskID
    case "move-day-out": row.activityDayKey = goalRecordOtherDay
    case "supersede": row.supersededAt = goalRecordDate.addingTimeInterval(30)
    case "delete": context.delete(row); deleted = true
    case "origin-to-legacy": row.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
    case "origin-to-unknown": row.originRawValue = "unknown-origin"
    case "move-task-in": row.taskId = goalRecordTaskID
    case "move-day-in": row.activityDayKey = day
    case "revive": row.supersededAt = nil
    case "origin-to-captured": row.originRawValue = TaskCompletionActivityOrigin.captured.rawValue
    case "insert": context.insert(row)
    case "insert-delete": context.insert(row); context.delete(row); deleted = true
    default: break
    }
    let rowBefore = deleted ? nil : GoalRecordActivityValue(row)
    let pendingBefore = GoalRecordPendingState(context)
    #expect(context.hasChanges)
    let result = try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(60), origin: requested,
        createdAt: goalRecordDate.addingTimeInterval(120), in: context)
    let blocks: Bool
    switch condition {
    case "move-task-in", "move-day-in", "revive", "origin-to-captured", "insert": blocks = true
    case "origin-to-legacy", "origin-to-unknown": blocks = requested == .legacyBackfill
    default: blocks = false
    }
    #expect((result == nil) == blocks)
    if !blocks {
        let inserted = try #require(result)
        goalRecordExpectNew(inserted, taskID: goalRecordTaskID, day: day, origin: requested,
            occurredAt: goalRecordDate.addingTimeInterval(60), createdAt: goalRecordDate.addingTimeInterval(120), in: context)
    }
    if let rowBefore {
        #expect(GoalRecordActivityValue(row) == rowBefore)
        let registeredRow: TaskCompletionActivity? = context.registeredModel(for: row.persistentModelID)
        #expect(registeredRow === row)
    }
    #expect(GoalRecordMemoValue(draft) == draftBefore)
    #expect(GoalRecordPendingState(context).removing(result?.persistentModelID) == pendingBefore)
    let registeredDraft: Memo? = context.registeredModel(for: draft.persistentModelID)
    #expect(registeredDraft === draft)

    // Moving out of K must leave the same physical row blocking its new key L.
    if condition == "move-task-out" || condition == "move-day-out" {
        let moved = try TaskActivityService.record(taskID: row.taskId, activityDayKey: row.activityDayKey,
            occurredAt: goalRecordDate.addingTimeInterval(90), origin: requested, in: context)
        #expect(moved == nil)
        #expect(GoalRecordActivityValue(row) == rowBefore)
        #expect(GoalRecordPendingState(context).removing(result?.persistentModelID) == pendingBefore)
    }
    #expect(context.hasChanges)
    #expect(try goalRecordSavedValues(in: container) == savedBefore)
    let verifier = ModelContext(container)
    verifier.autosaveEnabled = false
    #expect(try verifier.fetchCount(FetchDescriptor<Memo>()) == 0)
    #expect(!verifier.hasChanges)
}

@Test @MainActor
func goalActivityRecordNoSaveSequenceDistinguishesOriginsAndRechecksDeletes() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = DayKey.key(for: goalRecordDate)
    let legacy = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate, origin: .legacyBackfill, createdAt: goalRecordDate, in: context))
    let legacyBefore = GoalRecordActivityValue(legacy)
    let captured = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(60), origin: .captured, createdAt: goalRecordDate, in: context))
    let repeated = try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(120), origin: .captured, in: context)
    #expect(repeated == nil && captured.id == legacy.id)
    #expect(captured.instanceID != legacy.instanceID && captured.persistentModelID != legacy.persistentModelID)
    #expect(GoalRecordActivityValue(legacy) == legacyBefore)
    context.delete(captured)
    let replacement = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(180), origin: .captured, createdAt: goalRecordDate, in: context))
    let replacementBefore = GoalRecordActivityValue(replacement)
    replacement.supersededAt = goalRecordDate.addingTimeInterval(240)
    let supersededBefore = GoalRecordActivityValue(replacement)
    let last = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(300), origin: .captured, createdAt: goalRecordDate, in: context))
    #expect(last.id == replacementBefore.id && last.instanceID != replacementBefore.instanceID)
    #expect(GoalRecordActivityValue(replacement) == supersededBefore)
    #expect(GoalRecordActivityValue(legacy) == legacyBefore)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 3)
    #expect(try goalRecordSavedValues(in: container).isEmpty)
    #expect(context.hasChanges)
}

@Test(arguments: [TaskCompletionActivityOrigin.captured, .legacyBackfill]) @MainActor
func goalActivityRecordFindsTailAfterMoreThanTwoHundredExcludedPhysicalCopies(
    requested: TaskCompletionActivityOrigin
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = DayKey.key(for: goalRecordDate)
    var rows: [TaskCompletionActivity] = []
    for index in 0..<205 {
        let row = goalRecordSeed(taskID: goalRecordTaskID, day: day, at: goalRecordDate,
            physicalIndex: index + 1)
        row.updatedAt = goalRecordDate.addingTimeInterval(Double(205 - index))
        context.insert(row)
        rows.append(row)
    }
    try context.save()
    let savedBefore = try goalRecordSavedValues(in: container)
    let savedOrder = try context.fetch(TaskActivityService.activeDescriptor(taskID: goalRecordTaskID, activityDayKey: day))
    #expect(savedOrder.map(\.instanceID) == rows.map(\.instanceID))
    var retained: [TaskCompletionActivity] = []
    for (index, row) in rows.prefix(204).enumerated() {
        switch index % 3 {
        case 0: row.taskId = goalRecordOtherTaskID; retained.append(row)
        case 1: row.supersededAt = goalRecordDate; retained.append(row)
        default: context.delete(row)
        }
    }
    let tail = rows[204]
    retained.append(tail)
    let before = Set(retained.map { GoalRecordActivityValue($0) })
    let pendingBefore = GoalRecordPendingState(context)
    let result = try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(600), origin: requested, in: context)
    #expect(result == nil)
    #expect(Set(retained.map { GoalRecordActivityValue($0) }) == before)
    #expect(GoalRecordPendingState(context) == pendingBefore)
    #expect(try context.fetch(TaskActivityService.activeDescriptor(taskID: goalRecordTaskID, activityDayKey: day))
        .map(\.persistentModelID) == [tail.persistentModelID])

    // Only after excluding the final saved physical copy may absence be true.
    tail.supersededAt = goalRecordDate.addingTimeInterval(700)
    let secondBefore = Set(retained.map { GoalRecordActivityValue($0) })
    let secondPending = GoalRecordPendingState(context)
    let inserted = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
        occurredAt: goalRecordDate.addingTimeInterval(720), origin: requested,
        createdAt: goalRecordDate.addingTimeInterval(780), in: context))
    goalRecordExpectNew(inserted, taskID: goalRecordTaskID, day: day, origin: requested,
        occurredAt: goalRecordDate.addingTimeInterval(720), createdAt: goalRecordDate.addingTimeInterval(780), in: context)
    #expect(Set(retained.map { GoalRecordActivityValue($0) }) == secondBefore)
    #expect(GoalRecordPendingState(context).removing(inserted.persistentModelID) == secondPending)
    #expect(try goalRecordSavedValues(in: container) == savedBefore)
}

@Test(arguments: [TaskCompletionActivityOrigin.captured, .legacyBackfill], [
    "legacy-to-captured", "captured-to-legacy", "task-out", "day-out",
    "task-in", "day-in", "supersede", "delete", "insert", "revive"
])
@MainActor
func goalActivityRecordSeesExternalSavedChangesWithoutSavingUnrelatedDraft(
    requested: TaskCompletionActivityOrigin, condition: String
) throws {
    // Both inserted and edited unrelated drafts make the source context dirty;
    // the saved Activity itself is registered before the separate writer saves.
    for draftKind in ["inserted", "edited"] {
        let container = try PlanBaseContainerFactory.makeInMemory()
        defer { withExtendedLifetime(container) {} }
        let source = container.mainContext
        source.autosaveEnabled = false
        let day = DayKey.key(for: goalRecordDate)
        let row = goalRecordSeed(taskID: goalRecordTaskID, day: day, at: goalRecordDate)
        switch condition {
        case "legacy-to-captured": row.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
        case "task-in": row.taskId = goalRecordOtherTaskID
        case "day-in": row.activityDayKey = goalRecordOtherDay
        case "revive": row.supersededAt = goalRecordDate
        default: break
        }
        if condition != "insert" { source.insert(row) }
        try source.save()
        let rowPID: PersistentIdentifier? = condition == "insert" ? nil : row.persistentModelID
        if let rowPID {
            let registered: TaskCompletionActivity? = source.registeredModel(for: rowPID)
            #expect(registered === row)
        }
        let draft = Memo(content: "외부 변경 전 메모", createdAt: goalRecordDate, updatedAt: goalRecordDate)
        source.insert(draft)
        if draftKind == "edited" { try source.save() }
        draft.content = "외부 저장 중에도 유지할 미저장 메모"
        draft.isPinned = true
        let draftBefore = GoalRecordMemoValue(draft)

        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        if condition == "insert" {
            writer.insert(goalRecordSeed(taskID: goalRecordTaskID, day: day, at: goalRecordDate,
                physicalIndex: 2))
        } else {
            let physicalID = row.instanceID
            let external = try #require(try writer.fetch(FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate { $0.instanceID == physicalID })).first)
            switch condition {
            case "legacy-to-captured": external.originRawValue = TaskCompletionActivityOrigin.captured.rawValue
            case "captured-to-legacy": external.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
            case "task-out": external.taskId = goalRecordOtherTaskID
            case "day-out": external.activityDayKey = goalRecordOtherDay
            case "task-in": external.taskId = goalRecordTaskID
            case "day-in": external.activityDayKey = day
            case "supersede": external.supersededAt = goalRecordDate.addingTimeInterval(30)
            case "delete": writer.delete(external)
            case "revive": external.supersededAt = nil
            default: break
            }
            if condition != "delete" { external.updatedAt = goalRecordDate.addingTimeInterval(30) }
        }
        try writer.save()
        #expect(!writer.hasChanges)
        // Classify SDK merge behavior without assuming that a clean registered
        // row remains stale. Do not read an externally deleted model's fields.
        let pendingBefore = GoalRecordPendingState(source)
        let activityPending = rowPID.map { pendingBefore.all.contains($0) } ?? false
        print("GOAL_RECORD_EXTERNAL_BEFORE condition=\(condition) draft=\(draftKind) requested=\(requested.rawValue) activityPending=\(activityPending)")
        #expect(!activityPending)
        #expect(GoalRecordMemoValue(draft) == draftBefore && source.hasChanges)
        let savedBefore = try goalRecordSavedValues(in: container)
        if condition == "delete" {
            #expect(savedBefore.isEmpty)
        } else {
            #expect(savedBefore.count == 1)
            let saved = try #require(savedBefore.first)
            #expect(saved.taskID == (condition == "task-out" ? goalRecordOtherTaskID : goalRecordTaskID))
            #expect(saved.day == (condition == "day-out" ? goalRecordOtherDay : day))
            #expect(saved.origin == (condition == "captured-to-legacy"
                ? TaskCompletionActivityOrigin.legacyBackfill.rawValue : TaskCompletionActivityOrigin.captured.rawValue))
            #expect((saved.supersededAt != nil) == (condition == "supersede"))
        }

        // No source fetch, refresh, save, processPendingChanges, or yield occurs
        // between the external save and this public record call.
        let result = try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
            occurredAt: goalRecordDate.addingTimeInterval(60), origin: requested,
            createdAt: goalRecordDate.addingTimeInterval(120), in: source)
        let blocks: Bool
        switch condition {
        case "legacy-to-captured", "task-in", "day-in", "insert", "revive": blocks = true
        case "captured-to-legacy": blocks = requested == .legacyBackfill
        default: blocks = false
        }
        #expect((result == nil) == blocks)
        if !blocks {
            let inserted = try #require(result)
            goalRecordExpectNew(inserted, taskID: goalRecordTaskID, day: day, origin: requested,
                occurredAt: goalRecordDate.addingTimeInterval(60), createdAt: goalRecordDate.addingTimeInterval(120), in: source)
            #expect(!savedBefore.contains { $0.persistentID == inserted.persistentModelID })
        }
        #expect(GoalRecordPendingState(source).removing(result?.persistentModelID) == pendingBefore)
        #expect(GoalRecordMemoValue(draft) == draftBefore)
        let registeredDraft: Memo? = source.registeredModel(for: draft.persistentModelID)
        #expect(registeredDraft === draft && source.hasChanges)
        #expect(try goalRecordSavedValues(in: container) == savedBefore)
        let verifier = ModelContext(container)
        verifier.autosaveEnabled = false
        let savedMemos = try verifier.fetch(FetchDescriptor<Memo>())
        #expect(savedMemos.count == (draftKind == "edited" ? 1 : 0))
        if let savedDraft = savedMemos.first {
            #expect(savedDraft.content == "외부 변경 전 메모" && !savedDraft.isPinned)
        }
        #expect(!verifier.hasChanges)
    }
}

@Test(arguments: [TaskCompletionActivityOrigin.captured, .legacyBackfill]) @MainActor
func goalActivityRecordRollbackDoesNotRememberAnInsertedOrBlockingKey(
    requested: TaskCompletionActivityOrigin
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = DayKey.key(for: goalRecordDate)
    let draft = Memo(content: "명령 전에 저장할 draft", createdAt: goalRecordDate, updatedAt: goalRecordDate)
    context.insert(draft)
    #expect(throws: GoalRecordTestError.injected) {
        try PersistenceCommandService.perform(in: context) {
            let inserted = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
                occurredAt: goalRecordDate, origin: requested, createdAt: goalRecordDate, in: context))
            goalRecordExpectNew(inserted, taskID: goalRecordTaskID, day: day, origin: requested,
                occurredAt: goalRecordDate, createdAt: goalRecordDate, in: context)
            let repeated = try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
                occurredAt: goalRecordDate.addingTimeInterval(60), origin: requested, in: context)
            #expect(repeated == nil)
            throw GoalRecordTestError.injected
        }
    }
    #expect(!context.hasChanges)
    #expect(try goalRecordSavedValues(in: container).isEmpty)
    let verifier = ModelContext(container)
    verifier.autosaveEnabled = false
    #expect(try verifier.fetch(FetchDescriptor<Memo>()).first?.content == "명령 전에 저장할 draft")

    let newPhysicalID = try PersistenceCommandService.perform(in: context) {
        let retried = try #require(try TaskActivityService.record(taskID: goalRecordTaskID, activityDayKey: day,
            occurredAt: goalRecordDate.addingTimeInterval(120), origin: requested,
            createdAt: goalRecordDate.addingTimeInterval(120), in: context))
        return retried.instanceID
    }
    let saved = try goalRecordSavedValues(in: container)
    #expect(saved.count == 1 && saved.first?.instanceID == newPhysicalID)
    #expect(saved.first?.occurredAt == goalRecordDate.addingTimeInterval(120))
    #expect(!context.hasChanges && !verifier.hasChanges)
}

@Test @MainActor
func goalActivityRecordLifecycleRollbackPreservesTaskProgressAndCompletionHistory() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let plannedAt = DayKey.addingDays(-2, to: goalRecordDate)
    let task = Task(title: "원자적 완료", plannedAt: plannedAt, order: 100)
    let taskID = task.id
    let plannedDay = task.plannedDayKey
    context.insert(task)
    try context.save()
    let taskPID = task.persistentModelID
    let taskPhysicalID = task.instanceID
    let start = goalRecordDate.addingTimeInterval(-600)
    let started = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: start)
    }
    #expect(started.progressEventKind == .started && !started.activityInserted)
    let startedRows = try context.fetch(FetchDescriptor<TaskProgressEvent>())
    let startedBefore = Set(startedRows.map { GoalRecordProgressValue($0) })
    #expect(startedBefore.count == 1)
    let draft = Memo(content: "실패하는 완료 전의 미저장 draft", createdAt: goalRecordDate, updatedAt: goalRecordDate)
    context.insert(draft)
    #expect(throws: GoalRecordTestError.injected) {
        try PersistenceCommandService.perform(in: context) {
            let failed = try TaskLifecycleService.applyStatus(.done, to: task, in: context,
                now: goalRecordDate, completionDayKey: plannedDay)
            #expect(failed.activityInserted && failed.progressEventKind == .stopped)
            #expect(task.status == TaskStatus.done.rawValue)
            #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 2)
            throw GoalRecordTestError.injected
        }
    }
    let restored = try #require(try context.fetch(BoundedQueryService.taskDescriptor(id: taskID)).first)
    #expect(restored.persistentModelID == taskPID && restored.instanceID == taskPhysicalID)
    #expect(restored.status == TaskStatus.doing.rawValue)
    #expect(restored.completedAt == nil && restored.completedDayKey == nil)
    #expect(Set(try context.fetch(FetchDescriptor<TaskProgressEvent>()).map { GoalRecordProgressValue($0) }) == startedBefore)
    #expect(try goalRecordSavedValues(in: container).isEmpty && !context.hasChanges)
    let verifier = ModelContext(container)
    verifier.autosaveEnabled = false
    #expect(try verifier.fetch(FetchDescriptor<Memo>()).first?.content == "실패하는 완료 전의 미저장 draft")
    #expect(try verifier.fetch(FetchDescriptor<Task>()).first?.status == TaskStatus.doing.rawValue)
    #expect(try verifier.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
    #expect(try verifier.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 1)

    let completed = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: restored, in: context,
            now: goalRecordDate, completionDayKey: plannedDay)
    }
    #expect(completed.didComplete && completed.activityInserted && completed.progressEventKind == .stopped)
    #expect(restored.completedAt == goalRecordDate && restored.completedDayKey == plannedDay)
    let activity = try #require(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).first)
    let completionBefore = GoalRecordActivityValue(activity)
    #expect(activity.taskId == taskID && activity.activityDayKey == DayKey.key(for: goalRecordDate))
    #expect(activity.occurredAt == goalRecordDate && activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue)
    let progress = try context.fetch(FetchDescriptor<TaskProgressEvent>())
    #expect(progress.count == 2)
    #expect(startedBefore.isSubset(of: Set(progress.map { GoalRecordProgressValue($0) })))
    #expect(progress.contains { $0.taskId == taskID && $0.kindRawValue == TaskProgressEventKind.stopped.rawValue
        && $0.occurredAt == goalRecordDate && $0.originRawValue == TaskProgressEventOrigin.captured.rawValue })
    let sameState = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: restored, in: context, now: goalRecordDate.addingTimeInterval(60))
    }
    #expect(sameState == .unchanged)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 2)
    _ = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.todo, to: restored, in: context, now: goalRecordDate.addingTimeInterval(60))
    }
    let repeated = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: restored, in: context, now: goalRecordDate.addingTimeInterval(120))
    }
    #expect(repeated.didComplete && !repeated.activityInserted)
    #expect(try goalRecordSavedValues(in: container) == [completionBefore])
    try PersistenceCommandService.perform(in: context) { try TaskRules.delete(restored, from: context) }
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
    #expect(try goalRecordSavedValues(in: container) == [completionBefore])
    #expect(!context.hasChanges)
}

private let goalRecordDate = Date(timeIntervalSince1970: 1_790_899_200)
private let goalRecordTaskID = UUID(uuidString: "00000021-0000-4000-8000-000000000001")!
private let goalRecordOtherTaskID = UUID(uuidString: "00000021-0000-4000-8000-000000000002")!
private let goalRecordOtherDay = "2026-10-10"
private enum GoalRecordTestError: Error { case injected }

@MainActor
private func goalRecordSeed(taskID: UUID, day: String, at date: Date, physicalIndex: Int = 1) -> TaskCompletionActivity {
    TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: day),
        instanceID: UUID(uuidString: String(format: "00000022-0000-4000-8000-%012d", physicalIndex))!,
        taskId: taskID, activityDayKey: day, occurredAt: date, origin: .captured,
        createdAt: date.addingTimeInterval(-120), updatedAt: date.addingTimeInterval(-60))
}

@MainActor
private func goalRecordExpectNew(_ row: TaskCompletionActivity, taskID: UUID, day: String,
    origin: TaskCompletionActivityOrigin, occurredAt: Date, createdAt: Date, in context: ModelContext) {
    #expect(row.id == TaskActivityRules.logicalID(taskID: taskID, activityDayKey: day))
    #expect(row.taskId == taskID && row.activityDayKey == day)
    #expect(row.originRawValue == origin.rawValue && row.occurredAt == occurredAt)
    #expect(row.createdAt == createdAt && row.updatedAt == createdAt && row.supersededAt == nil)
    #expect(context.insertedModelsArray.contains { $0.persistentModelID == row.persistentModelID })
    let registered: TaskCompletionActivity? = context.registeredModel(for: row.persistentModelID)
    #expect(registered === row)
}

@MainActor
private func goalRecordSavedValues(in container: ModelContainer) throws -> Set<GoalRecordActivityValue> {
    let reader = ModelContext(container)
    reader.autosaveEnabled = false
    var descriptor = FetchDescriptor<TaskCompletionActivity>()
    descriptor.includePendingChanges = false
    let rows = try reader.fetch(descriptor)
    let values = Set(rows.map { GoalRecordActivityValue($0) })
    #expect(!reader.hasChanges)
    withExtendedLifetime(reader) {}
    return values
}

private struct GoalRecordPendingState: Equatable {
    let inserted: Set<PersistentIdentifier>
    let changed: Set<PersistentIdentifier>
    let deleted: Set<PersistentIdentifier>
    var all: Set<PersistentIdentifier> { inserted.union(changed).union(deleted) }

    @MainActor init(_ context: ModelContext) {
        inserted = Set(context.insertedModelsArray.map(\.persistentModelID))
        changed = Set(context.changedModelsArray.map(\.persistentModelID))
        deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
    }

    private init(inserted: Set<PersistentIdentifier>, changed: Set<PersistentIdentifier>, deleted: Set<PersistentIdentifier>) {
        self.inserted = inserted; self.changed = changed; self.deleted = deleted
    }

    func removing(_ id: PersistentIdentifier?) -> Self {
        guard let id else { return self }
        return Self(inserted: inserted.subtracting([id]), changed: changed.subtracting([id]), deleted: deleted.subtracting([id]))
    }
}

private struct GoalRecordActivityValue: Hashable {
    let persistentID: PersistentIdentifier
    let id: UUID
    let instanceID: UUID
    let taskID: UUID
    let day: String
    let occurredAt: Date
    let origin: String
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?

    @MainActor init(_ row: TaskCompletionActivity) {
        persistentID = row.persistentModelID; id = row.id; instanceID = row.instanceID
        taskID = row.taskId; day = row.activityDayKey; occurredAt = row.occurredAt
        origin = row.originRawValue; createdAt = row.createdAt; updatedAt = row.updatedAt; supersededAt = row.supersededAt
    }
}

private struct GoalRecordMemoValue: Equatable {
    let persistentID: PersistentIdentifier
    let id: UUID
    let instanceID: UUID
    let content: String
    let pinned: Bool
    let preferredMode: String
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?

    @MainActor init(_ row: Memo) {
        persistentID = row.persistentModelID; id = row.id; instanceID = row.instanceID
        content = row.content; pinned = row.isPinned; preferredMode = row.preferredModeRawValue
        createdAt = row.createdAt; updatedAt = row.updatedAt; supersededAt = row.supersededAt
    }
}

private struct GoalRecordProgressValue: Hashable {
    let persistentID: PersistentIdentifier
    let id: UUID
    let instanceID: UUID
    let taskID: UUID
    let kind: String
    let origin: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?

    @MainActor init(_ row: TaskProgressEvent) {
        persistentID = row.persistentModelID; id = row.id; instanceID = row.instanceID
        taskID = row.taskId; kind = row.kindRawValue; origin = row.originRawValue
        occurredAt = row.occurredAt; createdAt = row.createdAt; updatedAt = row.updatedAt; supersededAt = row.supersededAt
    }
}
