import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func taskReminderDateIsNormalizedToWholeMinute() throws {
    let date = Date(timeIntervalSinceReferenceDate: 7_234.9)
    let normalized = try #require(TaskReminderRules.normalizedDate(date))

    #expect(normalized.timeIntervalSinceReferenceDate == 7_200)
    #expect(TaskReminderRules.normalizedDate(Date(timeIntervalSinceReferenceDate: .infinity)) == nil)
}

@Test
func taskReminderIdentifierRoundTripsLogicalTaskID() {
    let taskID = UUID()
    let identifier = TaskReminderRules.identifier(for: taskID)

    #expect(TaskReminderRules.taskID(from: identifier) == taskID)
    #expect(TaskReminderRules.taskID(from: "unrelated.\(taskID)") == nil)
}

@Test
@MainActor
func taskReminderRulesSetReplaceClearAndComplete() throws {
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let task = Task(title: "알림 작업", plannedAt: day, order: 100)
    let first = Date(timeIntervalSinceReferenceDate: 7_234.9)
    let changedAt = Date(timeIntervalSinceReferenceDate: 8_000)

    #expect(TaskRules.setReminder(first, on: task, now: changedAt))
    #expect(task.reminderAt == Date(timeIntervalSinceReferenceDate: 7_200))
    #expect(task.updatedAt == changedAt)
    #expect(!TaskRules.setReminder(first, on: task, now: changedAt.addingTimeInterval(1)))

    TaskRules.applyStatus(.done, to: task, now: changedAt.addingTimeInterval(2))
    #expect(task.reminderAt == nil)
    #expect(!TaskRules.setReminder(first, on: task, now: changedAt.addingTimeInterval(3)))
}

@Test
@MainActor
func taskReminderSnapshotRejectsBlankTitlesAndMalformedStatuses() throws {
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let now = Date(timeIntervalSinceReferenceDate: 10_000)
    let reminderAt = Date(timeIntervalSinceReferenceDate: 10_200)
    let task = Task(
        title: "  \n\t  ",
        plannedAt: day,
        order: 100,
        reminderAt: reminderAt
    )

    #expect(TaskReminderRules.snapshot(for: task, now: now) == nil)

    task.title = "  알림 작업  "
    task.status = "unknown"
    #expect(TaskReminderRules.snapshot(for: task, now: now) == nil)

    task.status = TaskStatus.done.rawValue
    #expect(TaskReminderRules.snapshot(for: task, now: now) == nil)

    task.status = TaskStatus.doing.rawValue
    let snapshot = try #require(TaskReminderRules.snapshot(for: task, now: now))
    #expect(snapshot.title == "알림 작업")
}

@Test
func taskReminderReconciliationSchedulesReplacesAndCancelsOnlyOwnedRequests() {
    let firstID = UUID()
    let secondID = UUID()
    let first = TaskReminderSnapshot(
        taskID: firstID,
        title: "첫 작업",
        plannedDayKey: "2026-07-12",
        reminderAt: Date(timeIntervalSinceReferenceDate: 12_000)
    )
    let second = TaskReminderSnapshot(
        taskID: secondID,
        title: "둘째 작업",
        plannedDayKey: "2026-07-13",
        reminderAt: Date(timeIntervalSinceReferenceDate: 18_000)
    )
    let staleID = TaskReminderRules.identifier(for: UUID())
    let plan = TaskReminderRules.reconciliationPlan(
        desired: [first, second],
        pending: [
            PendingTaskReminder(
                identifier: first.identifier,
                title: "이전 제목",
                reminderAt: first.reminderAt
            ),
            PendingTaskReminder(
                identifier: staleID,
                title: "삭제된 작업",
                reminderAt: first.reminderAt
            ),
            PendingTaskReminder(
                identifier: "another-app.notification",
                title: "다른 알림",
                reminderAt: nil
            )
        ]
    )

    #expect(Set(plan.remindersToSchedule.map(\.taskID)) == Set([firstID, secondID]))
    #expect(Set(plan.identifiersToCancel) == Set([first.identifier, staleID]))
}

@Test
@MainActor
func taskReminderDescriptorFetchesOnlyActiveOpenReminders() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let reminder = Date(timeIntervalSinceReferenceDate: 12_000)
    let active = Task(
        title: "활성",
        plannedAt: day,
        order: 100,
        reminderAt: reminder
    )
    let noReminder = Task(title: "알림 없음", plannedAt: day, order: 200)
    let done = Task(
        title: "완료",
        status: .done,
        plannedAt: day,
        order: 300,
        reminderAt: reminder
    )
    let superseded = Task(
        title: "대체됨",
        plannedAt: day,
        order: 400,
        reminderAt: reminder
    )
    superseded.supersededAt = Date()
    [active, noReminder, done, superseded].forEach(context.insert)
    try context.save()

    let rows = try context.fetch(BoundedQueryService.activeReminderTasksDescriptor())
    #expect(rows.map(\.id) == [active.id])
}

@Test
@MainActor
func integrityNormalizesReminderAndClearsCompletedReminder() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let open = Task(
        title: "열림",
        plannedAt: day,
        order: 100,
        reminderAt: Date(timeIntervalSinceReferenceDate: 7_234.9)
    )
    let done = Task(
        title: "완료",
        status: .done,
        plannedAt: day,
        order: 200,
        reminderAt: Date(timeIntervalSinceReferenceDate: 8_000)
    )
    [open, done].forEach(context.insert)
    try context.save()

    _ = try DataIntegrityService.reconcile(context: context)

    #expect(open.reminderAt == Date(timeIntervalSinceReferenceDate: 7_200))
    #expect(done.reminderAt == nil)
}
