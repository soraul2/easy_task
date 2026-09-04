import Foundation
import SwiftData
import Testing

@testable import EasyTaskCore

private func recordDate(_ key: String, hour: Int = 0, minute: Int = 0) throws -> Date {
    let day = try #require(DayKey.date(from: key))
    return try #require(DayKey.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
}

@Test @MainActor
func taskRecordSeparatesSelectedDayFromLifetimeAndRetainsReopenedCompletion() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let created = try recordDate("2026-09-01", hour: 8)
    let start = try recordDate("2026-09-03", hour: 23, minute: 50)
    let end = try recordDate("2026-09-04", minute: 20)
    let task = Task(title: "자정 작업", status: .doing, plannedAt: created, order: 1, createdAt: created)
    context.insert(task)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
    context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: end))
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: created))
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: created.addingTimeInterval(600)))
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: end.addingTimeInterval(600)))
    for (date, seconds) in [(start, 1500), (created, 600)] {
        context.insert(
            FocusSession(
                taskId: task.id, startedAt: date, endedAt: date.addingTimeInterval(1800),
                plannedDurationSeconds: 1800, focusedDurationSeconds: seconds, outcome: .stopped))
    }
    try TaskActivityService.recordCapturedCompletion(taskID: task.id, occurredAt: end, in: context)
    try context.save()
    let result = try await TaskRecordQueryService.load(
        selection: .init(taskID: task.id, dayKey: "2026-09-04"), in: context)
    #expect(result.createdAt == created)
    #expect(result.firstStartedAt == created)
    #expect(result.currentStatus == TaskStatus.doing.rawValue)
    #expect(result.latestCompletedAt == end)
    #expect(result.recordedCompletionDayKey == nil)
    #expect(result.selectedDay.completed)
    #expect(result.selectedDay.progressSeconds == 1200)
    #expect(result.progress.recordedDuration == 2400)
    #expect(result.progress.currentStartedAt == end.addingTimeInterval(600))
    #expect(result.selectedDay.focusSeconds == 1500)
    #expect(result.focusedSeconds == 2100)
    #expect(result.focusSessionCount == 2)
    #expect(!context.hasChanges)
}

@Test @MainActor
func taskRecordDeduplicatesEvidenceAndExcludesOtherTasks() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = try recordDate("2026-09-04", hour: 10)
    let task = Task(title: "중복 기록", plannedAt: start, order: 1)
    context.insert(task)
    let focusID = UUID()
    for (duration, revision) in [(1200, 0), (600, 1)] {
        context.insert(
            FocusSession(
                id: focusID, taskId: task.id, startedAt: start, endedAt: start.addingTimeInterval(1200),
                plannedDurationSeconds: 1500, focusedDurationSeconds: duration, outcome: .stopped,
                updatedAt: start.addingTimeInterval(Double(revision))))
    }
    context.insert(
        FocusSession(
            taskId: UUID(), startedAt: start, endedAt: start.addingTimeInterval(3600),
            plannedDurationSeconds: 3600, focusedDurationSeconds: 3600, outcome: .completed))
    let activityID = TaskActivityRules.logicalID(taskID: task.id, activityDayKey: "2026-09-04")
    for origin in [TaskCompletionActivityOrigin.captured, .legacyBackfill] {
        context.insert(
            TaskCompletionActivity(
                id: activityID, taskId: task.id, activityDayKey: "2026-09-04", occurredAt: start,
                origin: origin, updatedAt: origin == .captured ? start : start.addingTimeInterval(100)))
    }
    let result = try await TaskRecordQueryService.load(
        selection: .init(taskID: task.id, dayKey: "2026-09-04"), in: context)
    #expect(result.focusedSeconds == 600)
    #expect(result.focusSessionCount == 1)
    #expect(result.selectedDay.completed)
    #expect(!result.selectedDay.legacyCompletion)
    #expect(result.timeline.filter { $0.kind == .completed }.count == 1)
}

@Test @MainActor
func taskRecordDoesNotInventLegacyCompletionTimeOrUnknownProgress() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = try recordDate("2026-09-03", hour: 10)
    let end = try recordDate("2026-09-04", hour: 15)
    let task = Task(title: "이전 작업", status: .done, plannedAt: start, order: 1, createdAt: start)
    task.completedAt = end
    task.completedDayKey = "2026-09-04"
    context.insert(task)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .stopped, origin: .compatibilityBoundary, occurredAt: end))
    let result = try await TaskRecordQueryService.load(
        selection: .init(taskID: task.id, dayKey: "2026-09-04"), in: context)
    #expect(result.progress.recordedDuration == 0)
    #expect(result.progress.hasUnknownDuration)
    #expect(result.latestCompletedAt == nil)
    #expect(result.recordedCompletionDayKey == "2026-09-04")
    #expect(result.selectedDay.legacyCompletion)
    let legacy = try #require(result.timeline.first { $0.kind == .legacyCompletion })
    #expect(legacy.startedAt == nil)
    #expect(legacy.endedAt == nil)
}

@Test @MainActor
func taskRecordKeepsRemainingFocusWhenTaskIsMissing() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let date = try recordDate("2026-09-04", hour: 9)
    context.insert(
        FocusSession(
            taskId: taskID, startedAt: date, endedAt: date.addingTimeInterval(1500),
            plannedDurationSeconds: 1500, focusedDurationSeconds: 1200, outcome: .interrupted))
    let result = try await TaskRecordQueryService.load(
        selection: .init(taskID: taskID, dayKey: "2026-09-04"), in: context)
    #expect(!result.hasCurrentTask)
    #expect(result.createdAt == nil)
    #expect(result.focusedSeconds == 1200)
}

@Test @MainActor
func taskRecordReadsMultipleBatchesAndOverlaysPendingChangesWithoutSaving() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = try recordDate("2026-09-04", hour: 8)
    let task = Task(title: "기록", plannedAt: date, order: 1)
    context.insert(task)
    for index in 0..<300 {
        let start = date.addingTimeInterval(Double(index * 60))
        context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
        context.insert(
            TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: start.addingTimeInterval(30)))
    }
    try context.save()
    task.title = "수정 중인 제목"
    let result = try await TaskRecordQueryService.load(
        selection: .init(taskID: task.id, dayKey: "2026-09-04"), in: context)
    #expect(result.title == "수정 중인 제목")
    #expect(result.progress.intervals.count == 300)
    #expect(result.progress.recordedDuration == 9000)
    #expect(context.hasChanges)
}
