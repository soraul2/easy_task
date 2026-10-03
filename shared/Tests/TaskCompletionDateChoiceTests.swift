import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func backdatedCompletionChoiceRequiresAnUnfinishedTaskOnItsPastBoard() {
    #expect(TaskCompletionRules.backdatedDayKey(
        selectedDayKey: "2026-10-02", plannedDayKey: "2026-10-02", status: .todo,
        todayKey: "2026-10-03"
    ) == "2026-10-02")
    for (selected, planned, status) in [
        ("2026-10-03", "2026-10-02", TaskStatus.todo),
        ("2026-10-03", "2026-10-03", .todo),
        ("2026-10-04", "2026-10-04", .todo),
        ("2026-10-02", "2026-10-01", .doing),
        ("2026-10-02", "2026-10-02", .done),
        ("2026-02-30", "2026-02-30", .todo)
    ] {
        #expect(TaskCompletionRules.backdatedDayKey(
            selectedDayKey: selected, plannedDayKey: planned, status: status,
            todayKey: "2026-10-03"
        ) == nil)
    }
    #expect(TaskCompletionRules.defaultActionTitle(selectedDayKey: "2026-10-02", todayKey: "2026-10-03") == "오늘 완료")
    #expect(TaskCompletionRules.defaultActionTitle(selectedDayKey: "2026-10-03", todayKey: "2026-10-03") == "완료")
    #expect(TaskCompletionRules.backdatedActionTitle(dayKey: "2026-10-02", todayKey: "2026-10-03") == "10월 2일 완료로 기록")
    #expect(TaskCompletionRules.backdatedActionTitle(dayKey: "2025-10-02", todayKey: "2026-10-03") == "2025년 10월 2일 완료로 기록")
}

@Test(arguments: [false, true], ["todo", "doing"])
@MainActor
func boardCompletionDateChoicePersistsAndUndoesWithoutChangingTheActionTime(
    backdated: Bool, previousStatusRawValue: String
) throws {
    let previousStatus = try #require(TaskStatus(rawValue: previousStatusRawValue))
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let plannedAt = try #require(DayKey.date(from: "2026-10-02"))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 13)))
    let task = Task(title: "지난 날짜에 추가한 작업", plannedAt: plannedAt, order: 100)
    task.reminderAt = now.addingTimeInterval(3_600)
    context.insert(task)
    try TaskLifecycleService.applyStatus(previousStatus, to: task, in: context, now: now.addingTimeInterval(-60))
    try context.save()
    let recordedKey = backdated ? "2026-10-02" : "2026-10-03"
    let token = try #require(try TaskCompletionUndoService.complete(
        task, in: context, now: now, completionDayKey: backdated ? recordedKey : nil
    ))

    let reader = ModelContext(container)
    let stored = try #require(reader.fetch(BoundedQueryService.taskDescriptor(id: task.id)).first)
    #expect(stored.plannedDayKey == "2026-10-02")
    #expect(stored.completedDayKey == recordedKey)
    #expect(stored.completedAt == now)
    #expect(stored.reminderAt == now.addingTimeInterval(3_600))
    let pastRows = try reader.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: "2026-10-02"))
    let todayRows = try reader.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: "2026-10-03"))
    #expect(BoardQueryRules.tasksForBoard(pastRows, selectedDayKey: "2026-10-02", todayKey: "2026-10-03").count == (backdated ? 1 : 0))
    #expect(BoardQueryRules.tasksForBoard(todayRows, selectedDayKey: "2026-10-03", todayKey: "2026-10-03").count == (backdated ? 0 : 1))
    #expect(TaskHistoryDatePresentation(task: stored).text == (backdated ? "계획·완료 10월 2일" : "계획 10월 2일 · 완료 10월 3일"))
    let activity = try #require(reader.fetch(FetchDescriptor<TaskCompletionActivity>()).first)
    #expect(activity.activityDayKey == "2026-10-03")
    #expect(activity.occurredAt == now)

    #expect(try TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))
    #expect(task.plannedAt == plannedAt)
    #expect(task.status == previousStatus.rawValue)
    #expect(task.completedDayKey == nil)
    #expect(task.completedAt == nil)
    #expect(task.reminderAt == now.addingTimeInterval(3_600))
    #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).allSatisfy { $0.supersededAt != nil })
    if previousStatus == .doing {
        let events = try TaskProgressEventService.events(forTaskIDs: [task.id], in: context)
        #expect(TaskProgressEventRules.projection(for: events).elapsedDuration(at: now.addingTimeInterval(1)) == 61)
    }
}

@Test(arguments: ["2026-10-01", "2026-10-03", "2026-10-04", "2026-02-30"])
@MainActor
func backdatedCompletionRejectsStaleOrInvalidDayBeforeWriting(_ dayKey: String) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let planned = try #require(DayKey.date(from: "2026-10-02"))
    let now = try #require(DayKey.date(from: "2026-10-03"))
    let task = Task(title: "날짜가 바뀐 작업", plannedAt: planned, order: 100)
    context.insert(task)
    try context.save()
    #expect(throws: TaskCompletionUndoService.CompletionError.self) {
        _ = try TaskCompletionUndoService.complete(task, in: context, now: now, completionDayKey: dayKey)
    }
    #expect(task.status == TaskStatus.todo.rawValue)
    #expect(task.completedAt == nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
}

@Test
@MainActor
func backdatedCompletionUndoDoesNotOverwriteAChangedCompletionDay() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let planned = try #require(DayKey.date(from: "2026-10-02"))
    let now = try #require(DayKey.date(from: "2026-10-03"))
    let task = Task(title: "완료일 변경 보호", plannedAt: planned, order: 100)
    context.insert(task)
    let token = try #require(try TaskCompletionUndoService.complete(
        task, in: context, now: now, completionDayKey: "2026-10-02"
    ))
    task.completedDayKey = "2026-10-01"
    try context.save()
    #expect(try !TaskCompletionUndoService.undo(token, in: context, now: now.addingTimeInterval(1)))
    #expect(task.completedDayKey == "2026-10-01")
    #expect(task.status == TaskStatus.done.rawValue)
}
