import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Suite @MainActor
struct TaskCompletionUndoTests {
    private let now = Date(timeIntervalSince1970: 1_786_752_000)

    @Test(arguments: ["todo", "doing"])
    func undoRestoresStateTimeReminderAndOrder(_ rawStatus: String) throws {
        let status = try #require(TaskStatus(rawValue: rawStatus))
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "실수 완료", plannedAt: now, order: 100)
        task.reminderAt = now.addingTimeInterval(3_600)
        context.insert(task)
        try TaskLifecycleService.applyStatus(status, to: task, in: context, now: now.addingTimeInterval(-600))
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, order: 900, now: now))
        #expect(task.status == TaskStatus.done.rawValue)
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(2)))
        #expect(task.status == status.rawValue)
        #expect(task.completedAt == nil)
        #expect(task.completedDayKey == nil)
        #expect(task.order == 100)
        #expect(task.reminderAt == now.addingTimeInterval(3_600))
        #expect(TaskReminderRules.upcomingReminderDate(for: task, now: now) != nil)
        let activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        #expect(activities.count == 1) // Retain the physical record for synchronization.
        #expect(activities.allSatisfy { $0.supersededAt != nil })
        let events = try TaskProgressEventService.events(forTaskIDs: [task.id], in: context)
        let projection = TaskProgressEventRules.projection(for: events)
        if status == .doing {
            #expect(projection.currentStartedAt == now.addingTimeInterval(-600))
            #expect(projection.elapsedDuration(at: now.addingTimeInterval(2)) == 602)
        } else {
            #expect(projection.currentStartedAt == nil)
            #expect(projection.recordedDuration == 0)
        }
        #expect(try !TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(3)))
        try DataIntegrityService.reconcile(context: context)
        try TaskActivityBackfillService.backfillLegacyCompletions(in: context)
        #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).allSatisfy { $0.supersededAt != nil })
    }

    @Test
    func undoPreservesEarlierCompletionsAndAllowsFreshCompletion() throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "반복 작업", plannedAt: now, order: 100)
        context.insert(task)
        for date in [now.addingTimeInterval(-86_400), now.addingTimeInterval(-60)] {
            try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: date)
            try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: date.addingTimeInterval(1))
        }
        let original = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
        let originalIDs = Set(original.map(\.instanceID))
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))
        let active = try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }
        #expect(Set(active.map(\.instanceID)) == originalIDs)
        #expect(active.count == 2)
        #expect(try TaskCompletionUndoService.complete(task, in: context, now: now.addingTimeInterval(2)) != nil)
        #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }.count == 2)
    }

    @Test
    func freshCompletionAfterUndoSurvivesReconciliation() throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "완료 정정", plannedAt: now, order: 100)
        context.insert(task)
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))
        let later = now.addingTimeInterval(2)
        _ = try TaskCompletionUndoService.complete(task, in: context, now: later)
        try DataIntegrityService.reconcile(context: context)
        try context.save()
        let active = try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }
        #expect(active.count == 1)
        #expect(active.first?.occurredAt == later)
    }

    @Test
    func undoSurvivesContextReloadAndBackupRoundTrip() throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "복구된 진행 상태", plannedAt: now, order: 100)
        context.insert(task)
        try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: now.addingTimeInterval(-600))
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))

        let reloaded = ModelContext(container)
        let stored = try #require(reloaded.fetch(BoundedQueryService.taskDescriptor(id: task.id)).first)
        #expect(stored.status == TaskStatus.doing.rawValue)
        let payload = try BackupCodec.makePayload(context: reloaded)
        #expect(payload.taskCompletionActivities?.isEmpty == true)
        let restoredContainer = try PlanBaseContainerFactory.makeInMemory()
        let restoredContext = restoredContainer.mainContext
        try BackupCodec.replaceAll(with: BackupCodec.decode(BackupCodec.encode(payload)), in: restoredContext)
        let restored = try #require(restoredContext.fetch(BoundedQueryService.taskDescriptor(id: task.id)).first)
        #expect(restored.status == TaskStatus.doing.rawValue)
        let projection = TaskProgressEventRules.projection(for: try TaskProgressEventService.events(forTaskIDs: [task.id], in: restoredContext))
        #expect(projection.currentStartedAt == now.addingTimeInterval(-600))
        #expect(try restoredContext.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func delayedLegacyImportsCannotRestoreAnUndoneCompletion(
        _ saveBeforeReconcile: Bool, _ hasEarlierCompletion: Bool
    ) throws {
        let now = self.now.addingTimeInterval(18 * 3_600)
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "지연 동기화", plannedAt: now, order: 100)
        context.insert(task)
        let start = now.addingTimeInterval(-600)
        try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: start)
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))
        // Another device saw the completed Task before its captured records.
        let legacy = try #require(try TaskActivityService.record(
            taskID: task.id, activityDayKey: TaskActivityRules.legacyDayKey(for: now),
            occurredAt: now, origin: .legacyBackfill, in: context
        ))
        let boundary = try #require(try TaskProgressEventService.recordCompatibilityBoundary(
            taskID: task.id, occurredAt: now, in: context
        ))
        // An older genuine completion must remain, even in the same day's group.
        let earlier = now.addingTimeInterval(-120)
        let olderCompletion = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: DayKey.key(for: earlier)),
            taskId: task.id, activityDayKey: DayKey.key(for: earlier), occurredAt: earlier,
            origin: .captured, createdAt: earlier, updatedAt: earlier
        )
        if hasEarlierCompletion { context.insert(olderCompletion) }
        if saveBeforeReconcile { try context.save() }
        try DataIntegrityService.reconcile(context: context)
        #expect(legacy.supersededAt != nil)
        #expect(boundary.supersededAt != nil)
        if hasEarlierCompletion { #expect(olderCompletion.supersededAt == nil) }
        let projection = TaskProgressEventRules.projection(for: try TaskProgressEventService.events(forTaskIDs: [task.id], in: context))
        #expect(projection.currentStartedAt == start)
        #expect(!projection.hasUnknownDuration)
        try DataIntegrityService.reconcile(context: context)
        #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }.count == (hasEarlierCompletion ? 1 : 0))
    }

    @Test(arguments: ["expired", "edited", "resumed", "deleted", "duplicate", "activity-import", "progress-import"])
    func staleUndoDoesNotChangeLaterWork(_ change: String) throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "변경 보호", plannedAt: now, order: 100)
        context.insert(task)
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        let taskID = task.id
        switch change {
        case "edited": task.title = "다른 기기에서 편집"; task.updatedAt = now.addingTimeInterval(1)
        case "resumed": try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: now.addingTimeInterval(1))
        case "deleted": try TaskRules.delete(task, from: context)
        case "duplicate": context.insert(Task(id: taskID, title: "동기화 중복", plannedAt: now, order: 200))
        case "activity-import": context.insert(TaskCompletionActivity(id: UUID(), taskId: taskID, activityDayKey: DayKey.key(for: now), occurredAt: now))
        case "progress-import": context.insert(TaskProgressEvent(taskId: taskID, kind: .stopped, occurredAt: now))
        default: break
        }
        try context.save()
        let activitiesBefore = try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }.count
        let undoAt = now.addingTimeInterval(change == "expired" ? TaskCompletionUndoService.availabilityDuration : 2)
        #expect(try !TaskCompletionUndoService.undo(token, in: context, now: undoAt))
        #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).filter { $0.supersededAt == nil }.count == activitiesBefore)
        if change == "resumed" { #expect(task.status == TaskStatus.doing.rawValue) }
        if change == "edited" { #expect(task.title == "다른 기기에서 편집") }
    }

    @Test
    func failedUndoRollsBackTaskAndBothRecordTypes() throws {
        enum Failure: Error { case injected }
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let task = Task(title: "취소 롤백", plannedAt: now, order: 100)
        context.insert(task)
        let token = try #require(try TaskCompletionUndoService.complete(task, in: context, now: now))
        #expect(throws: Failure.injected) {
            try PersistenceCommandService.perform(in: context) {
                #expect(try TaskCompletionUndoService.applyUndo(token, in: context, now: now.addingTimeInterval(1)))
                throw Failure.injected
            }
        }
        let rolledBack = try #require(context.fetch(BoundedQueryService.taskDescriptor(id: token.taskID)).first)
        #expect(rolledBack.status == TaskStatus.done.rawValue)
        #expect(rolledBack.completedAt == now)
        #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).allSatisfy { $0.supersededAt == nil })
        #expect(try context.fetch(FetchDescriptor<TaskProgressEvent>()).allSatisfy { $0.supersededAt == nil })
        #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(2)))
    }
}

@Test
func taskProgressTextDistinguishesPauseCompletionAndCumulativeTime() throws {
    let start = Date(timeIntervalSince1970: 1_786_752_000)
    let firstStop = start.addingTimeInterval(600)
    let resume = start.addingTimeInterval(1_200)
    let stop = start.addingTimeInterval(1_800)
    let projection = TaskProgressProjection(intervals: [
        .init(startedAt: start, stoppedAt: firstStop), .init(startedAt: resume, stoppedAt: stop)
    ])
    for status in [TaskStatus.todo, .done] {
        let text = try #require(TaskProgressEventRules.detailText(projection: projection, status: status, completedAt: stop))
        #expect(text.contains(status == .done ? "완료" : "진행 중단"))
        #expect(text.contains("완료") == (status == .done))
        #expect(text.hasSuffix("진행 누적 20분"))
    }
    var running = projection
    running.currentStartedAt = stop
    let runningText = try #require(TaskProgressEventRules.detailText(projection: running, status: .doing, now: stop.addingTimeInterval(300)))
    #expect(runningText.hasSuffix("진행 누적 25분"))
    let missingCurrentStart = try #require(TaskProgressEventRules.detailText(projection: projection, status: .doing))
    #expect(missingCurrentStart == "진행 누적 20분 · 현재 시작 시각 기록 없음")
    let instantStop = TaskProgressProjection(intervals: [.init(startedAt: start, stoppedAt: start)])
    #expect(TaskProgressEventRules.detailText(projection: instantStop, status: .todo)?.hasSuffix("진행 누적 1분 미만") == true)
    let unknown = TaskProgressProjection(hasUnknownDuration: true)
    #expect(TaskProgressEventRules.detailText(projection: unknown, status: .todo, completedAt: stop) == "일부 진행 시간 기록 없음")
}

@Test
func dailyActivityExplainsCurrentStateWithoutChangingCompletionEvidence() {
    var evidence = DailyActivityEvidence()
    evidence.completed = true
    var entry = DailyActivityEntry(id: UUID(), title: "다시 진행", evidence: evidence, currentStatusRawValue: "doing")
    #expect(entry.completionStatusText == "현재 진행 중 · 완료 이력 유지")
    #expect(entry.evidence.summary == "이날 완료")
    entry.currentStatusRawValue = "todo"
    #expect(entry.completionStatusText == "현재 할 일 · 완료 이력 유지")
    entry.currentStatusRawValue = "done"
    #expect(entry.completionStatusText == nil)
    entry.currentStatusRawValue = nil
    #expect(entry.completionStatusText == nil)
}
