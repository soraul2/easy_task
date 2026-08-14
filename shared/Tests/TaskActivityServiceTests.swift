import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum TaskActivityServiceTestError: Error {
    case injected
}

@Test
@MainActor
func lifecycleCapturesActualActionDayWithoutChangingBackdatedCompletionMeaning() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let plannedAt = try #require(DayKey.date(from: "2026-08-10"))
    let occurredAt = try #require(ISO8601DateFormatter().date(
        from: "2026-08-14T12:30:00Z"
    ))
    let task = Task(title: "원래 날짜 완료", plannedAt: plannedAt, order: 100)
    context.insert(task)
    try context.save()

    let result = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(
            .done,
            to: task,
            in: context,
            now: occurredAt,
            completionDayKey: "2026-08-10"
        )
    }
    let activity = try #require(
        context.fetch(FetchDescriptor<TaskCompletionActivity>()).first
    )

    #expect(result == TaskLifecycleTransitionResult(
        didChange: true,
        didComplete: true,
        activityInserted: true
    ))
    #expect(task.completedDayKey == "2026-08-10")
    #expect(task.completedAt == occurredAt)
    #expect(activity.activityDayKey == DayKey.key(for: occurredAt))
    #expect(activity.occurredAt == occurredAt)
    #expect(activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue)
}

@Test
@MainActor
func lifecycleCountsOneTaskOncePerDayAndPreservesEarlierOccurrence() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = try #require(ISO8601DateFormatter().date(from: "2026-08-14T01:00:00Z"))
    let laterSameDay = first.addingTimeInterval(3_600)
    let nextDay = first.addingTimeInterval(86_400)
    let task = Task(title: "반복 완료", plannedAt: first, order: 100)
    context.insert(task)
    try context.save()

    _ = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: first)
    }
    _ = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.todo, to: task, in: context, now: laterSameDay)
    }
    let repeated = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: laterSameDay)
    }

    var activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(!repeated.activityInserted)
    #expect(activities.count == 1)
    #expect(activities.first?.occurredAt == first)

    _ = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.todo, to: task, in: context, now: nextDay)
    }
    let next = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: nextDay)
    }
    activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())

    #expect(next.activityInserted)
    #expect(activities.count == 2)
    #expect(Set(activities.map(\.activityDayKey)) == [
        DayKey.key(for: first),
        DayKey.key(for: nextDay)
    ])
}

@Test
@MainActor
func lifecycleRollbackAndTaskDeletionDoNotCorruptActivityHistory() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(title: "롤백 완료", plannedAt: now, order: 100)
    context.insert(task)
    try context.save()

    #expect(throws: TaskActivityServiceTestError.injected) {
        try PersistenceCommandService.perform(in: context) {
            _ = try TaskLifecycleService.applyStatus(
                .done,
                to: task,
                in: context,
                now: now
            )
            throw TaskActivityServiceTestError.injected
        }
    }
    let rolledBackTask = try #require(
        context.fetch(BoundedQueryService.taskDescriptor(id: task.id)).first
    )
    #expect(rolledBackTask.status == TaskStatus.todo.rawValue)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)

    _ = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(
            .done,
            to: rolledBackTask,
            in: context,
            now: now
        )
    }
    try PersistenceCommandService.perform(in: context) {
        try TaskRules.delete(rolledBackTask, from: context)
    }

    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
}

@Test
@MainActor
func capturedActivityCanReplaceLegacyCandidateWithoutOverwritingIt() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_786_752_000)
    let dayKey = DayKey.key(for: occurredAt)

    let legacyCandidate = try TaskActivityService.record(
        taskID: taskID,
        activityDayKey: dayKey,
        occurredAt: occurredAt,
        origin: .legacyBackfill,
        in: context
    )
    let legacy = try #require(legacyCandidate)
    let capturedCandidate = try TaskActivityService.record(
        taskID: taskID,
        activityDayKey: dayKey,
        occurredAt: occurredAt,
        origin: .captured,
        in: context
    )
    let captured = try #require(capturedCandidate)
    let repeated = try TaskActivityService.record(
        taskID: taskID,
        activityDayKey: dayKey,
        occurredAt: occurredAt.addingTimeInterval(60),
        origin: .captured,
        in: context
    )

    #expect(legacy.instanceID != captured.instanceID)
    #expect(legacy.id == captured.id)
    #expect(repeated == nil)
}
