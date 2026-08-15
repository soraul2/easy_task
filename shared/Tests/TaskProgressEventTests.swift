import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func taskProgressTransitionKindsCoverEveryRealStatusChange() {
    #expect(TaskProgressEventRules.eventKind(from: .todo, to: .doing) == .started)
    #expect(TaskProgressEventRules.eventKind(from: .done, to: .doing) == .started)
    #expect(TaskProgressEventRules.eventKind(from: .doing, to: .todo) == .stopped)
    #expect(TaskProgressEventRules.eventKind(from: .doing, to: .done) == .stopped)
    #expect(TaskProgressEventRules.eventKind(from: .todo, to: .done) == .stopped)
    #expect(TaskProgressEventRules.eventKind(from: .done, to: .todo) == .stopped)
    #expect(TaskProgressEventRules.eventKind(from: .todo, to: .todo) == nil)
}

@Test
func taskProgressProjectionUsesOneGlobalStateMachineAndDeterministicOrdering() {
    let taskID = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let duplicateStart = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: start.addingTimeInterval(60)
    )
    let firstStart = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: start
    )
    let stop = TaskProgressEvent(
        taskId: taskID,
        kind: .stopped,
        occurredAt: start.addingTimeInterval(600)
    )
    let extraStop = TaskProgressEvent(
        taskId: taskID,
        kind: .stopped,
        occurredAt: start.addingTimeInterval(900)
    )
    let secondStart = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: start.addingTimeInterval(1_200)
    )

    let projection = TaskProgressEventRules.projection(
        for: [extraStop, secondStart, stop, duplicateStart, firstStart]
    )

    #expect(projection.intervals == [
        TaskProgressInterval(
            startedAt: start,
            stoppedAt: start.addingTimeInterval(600)
        )
    ])
    #expect(projection.currentStartedAt == start.addingTimeInterval(1_200))
    #expect(projection.elapsedDuration(at: start.addingTimeInterval(1_500)) == 900)
}

@Test
func sameTimestampProgressTransitionsFollowCaptureOrder() {
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let capturedAt = occurredAt.addingTimeInterval(10)
    let immediateStart = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: occurredAt,
        createdAt: capturedAt,
        updatedAt: capturedAt
    )
    let immediateStop = TaskProgressEvent(
        taskId: taskID,
        kind: .stopped,
        occurredAt: occurredAt,
        createdAt: capturedAt.addingTimeInterval(0.001),
        updatedAt: capturedAt.addingTimeInterval(0.001)
    )

    let completed = TaskProgressEventRules.projection(for: [immediateStop, immediateStart])
    #expect(completed.intervals.count == 1)
    #expect(completed.recordedDuration == 0)
    #expect(completed.currentStartedAt == nil)

    let earlierStart = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: occurredAt.addingTimeInterval(-600),
        createdAt: capturedAt.addingTimeInterval(-600),
        updatedAt: capturedAt.addingTimeInterval(-600)
    )
    let pause = TaskProgressEvent(
        taskId: taskID,
        kind: .stopped,
        occurredAt: occurredAt,
        createdAt: capturedAt,
        updatedAt: capturedAt
    )
    let resume = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: occurredAt,
        createdAt: capturedAt.addingTimeInterval(0.001),
        updatedAt: capturedAt.addingTimeInterval(0.001)
    )

    let resumed = TaskProgressEventRules.projection(for: [resume, pause, earlierStart])
    #expect(resumed.recordedDuration == 600)
    #expect(resumed.currentStartedAt == occurredAt)
}

@Test
func compatibilityBoundaryClosesButDoesNotInventDuration() {
    let taskID = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let boundaryDate = start.addingTimeInterval(3_600)
    let started = TaskProgressEvent(
        taskId: taskID,
        kind: .started,
        occurredAt: start
    )
    let boundary = TaskProgressEvent(
        id: TaskProgressEventService.compatibilityBoundaryID(
            taskID: taskID,
            occurredAt: boundaryDate
        ),
        taskId: taskID,
        kind: .stopped,
        origin: .compatibilityBoundary,
        occurredAt: boundaryDate
    )

    let projection = TaskProgressEventRules.projection(for: [boundary, started])
    #expect(projection.intervals.isEmpty)
    #expect(projection.currentStartedAt == nil)
    #expect(projection.hasUnknownDuration)
    #expect(TaskProgressEventRules.detailText(
        projection: projection,
        status: .done
    ) == "일부 진행 시간 기록 없음")
}

@Test
func taskProgressDurationTextUsesAtMostTwoUsefulUnits() {
    #expect(TaskProgressEventRules.durationText(for: 30) == "1분 미만")
    #expect(TaskProgressEventRules.durationText(for: 75 * 60) == "1시간 15분")
    #expect(TaskProgressEventRules.durationText(for: (3 * 24 + 2) * 3_600 + 59 * 60) == "3일 2시간")
}

@Test
@MainActor
func lifecycleRecordsStartStopAndTransactionalDelete() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let stop = start.addingTimeInterval(4_500)
    let task = Task(title: "집중 작업", plannedAt: start, order: 100)
    context.insert(task)
    try context.save()

    let started = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: start)
    }
    let stopped = try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: stop)
    }
    let events = try TaskProgressEventService.events(forTaskIDs: [task.id], in: context)
    let projection = TaskProgressEventRules.projection(for: events)

    #expect(started.progressEventKind == .started)
    #expect(stopped.progressEventKind == .stopped)
    #expect(events.count == 2)
    #expect(projection.recordedDuration == 4_500)
    let detail = try #require(TaskProgressEventRules.detailText(
        projection: projection,
        status: .done,
        completedAt: stop,
        locale: Locale(identifier: "ko_KR"),
        timeZone: TimeZone(secondsFromGMT: 0)!
    ))
    #expect(detail.contains("시작"))
    #expect(detail.contains("완료"))
    #expect(detail.hasSuffix("진행 1시간 15분"))

    try PersistenceCommandService.perform(in: context) {
        try TaskRules.delete(task, from: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
}

@Test
@MainActor
func compatibilityReconciliationIsDeterministicAndIdempotent() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let boundary = start.addingTimeInterval(600)
    let task = Task(
        title: "이전 버전에서 중지",
        status: .todo,
        plannedAt: start,
        order: 100,
        updatedAt: boundary
    )
    context.insert(task)
    context.insert(TaskProgressEvent(
        taskId: task.id,
        kind: .started,
        occurredAt: start,
        createdAt: start,
        updatedAt: start
    ))
    try context.save()

    let first = try TaskProgressCompatibilityService.reconcile(
        tasks: [task],
        in: context
    )
    let second = try TaskProgressCompatibilityService.reconcile(
        tasks: [task],
        in: context
    )
    let events = try TaskProgressEventService.events(forTaskIDs: [task.id], in: context)

    #expect(first.insertedBoundaries == 1)
    #expect(second.insertedBoundaries == 0)
    #expect(events.count == 2)
    #expect(events.first { $0.originRawValue == TaskProgressEventOrigin.compatibilityBoundary.rawValue }?.id ==
        TaskProgressEventService.compatibilityBoundaryID(taskID: task.id, occurredAt: boundary))
}

@Test
@MainActor
func progressIntegritySupersedesInvalidAndDuplicateEventsWithoutDeletingOrphans() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let logicalID = UUID()
    let orphanTaskID = UUID()
    let older = TaskProgressEvent(
        id: logicalID,
        instanceID: UUID(),
        taskId: orphanTaskID,
        kind: .started,
        occurredAt: now,
        createdAt: now,
        updatedAt: now
    )
    let newer = TaskProgressEvent(
        id: logicalID,
        instanceID: UUID(),
        taskId: orphanTaskID,
        kind: .started,
        occurredAt: now,
        createdAt: now,
        updatedAt: now.addingTimeInterval(10)
    )
    let invalid = TaskProgressEvent(
        taskId: orphanTaskID,
        kind: .started,
        origin: .compatibilityBoundary,
        occurredAt: now
    )
    context.insert(older)
    context.insert(newer)
    context.insert(invalid)

    let report = try TaskProgressEventIntegrityService.reconcile(in: context)

    #expect(report.mergedRecords == 1)
    #expect(report.supersededRecords == 2)
    #expect(newer.supersededAt == nil)
    #expect(older.supersededAt != nil)
    #expect(invalid.supersededAt != nil)
    #expect(newer.taskId == orphanTaskID)
}
