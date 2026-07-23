import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func dayKeyRoundTripsDateString() throws {
    let date = try #require(DayKey.date(from: "2026-07-06"))

    #expect(DayKey.key(for: date) == "2026-07-06")
}

@Test
func carryoverTasksAreOpenPastTasksSortedByDayAndOrder() throws {
    let olderDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let laterPastDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)))

    let olderSecond = Task(title: "오래된 두 번째", plannedAt: olderDay, order: 200)
    let olderFirst = Task(title: "오래된 첫 번째", plannedAt: olderDay, order: 100)
    let laterDoing = Task(title: "진행 중 과거 작업", status: .doing, plannedAt: laterPastDay, order: 100)
    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let donePast = Task(title: "완료된 과거 작업", plannedAt: olderDay, order: 300)
    let archivedPast = Task(title: "보관된 과거 작업", plannedAt: olderDay, order: 400)

    TaskRules.applyStatus(.done, to: donePast, now: now)
    archivedPast.archivedAt = now

    let result = TaskRules.carryoverTasks(
        [todayTask, olderSecond, laterDoing, donePast, archivedPast, olderFirst],
        before: DayKey.key(for: today)
    )

    #expect(result.map(\.title) == ["오래된 첫 번째", "오래된 두 번째", "진행 중 과거 작업"])
}

@Test
func movingTaskToDateUpdatesDayKeyOrderAndTimestamp() throws {
    let originalDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 15)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10)))
    let task = Task(title: "날짜 이동", plannedAt: originalDate, order: 100)

    TaskRules.move(task, to: targetDate, order: 500, now: now)

    #expect(task.plannedAt == DayKey.startOfDay(for: targetDate))
    #expect(task.plannedDayKey == "2026-07-08")
    #expect(task.order == 500)
    #expect(task.updatedAt == now)
}

@Test
func bringingCarryoverTaskToTodayMovesAndResetsStatus() throws {
    let originalDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 10)))
    let task = Task(title: "진행 중 이월 작업", status: .doing, plannedAt: originalDate, order: 100)

    TaskRules.bringToToday(task, order: 500, now: now)

    #expect(task.plannedAt == DayKey.startOfDay(for: now))
    #expect(task.plannedDayKey == "2026-07-14")
    #expect(task.status == TaskStatus.todo.rawValue)
    #expect(task.order == 500)
    #expect(task.updatedAt == now)
}

@Test
func completingCarryoverTasksUsesEachOriginalPlannedDay() throws {
    let july4 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 21)))
    let first = Task(title: "7월 4일 미완료", plannedAt: july4, order: 100)
    let second = Task(title: "7월 7일 진행 중", status: .doing, plannedAt: july7, order: 200)

    TaskRules.completeOnPlannedDays([first, second], now: now)

    #expect(first.status == TaskStatus.done.rawValue)
    #expect(first.plannedDayKey == "2026-07-04")
    #expect(first.completedDayKey == "2026-07-04")
    #expect(first.completedAt == now)
    #expect(second.status == TaskStatus.done.rawValue)
    #expect(second.plannedDayKey == "2026-07-07")
    #expect(second.completedDayKey == "2026-07-07")
    #expect(second.completedAt == now)

    let todayBoard = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-14",
        todayKey: "2026-07-14"
    )
    let july4Board = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-04",
        todayKey: "2026-07-14"
    )
    let july7Board = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-07",
        todayKey: "2026-07-14"
    )

    #expect(todayBoard.isEmpty)
    #expect(july4Board.map(\.title) == ["7월 4일 미완료"])
    #expect(july7Board.map(\.title) == ["7월 7일 진행 중"])
}

@Test
func completingAllTasksUsesSharedStatusRule() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let first = Task(title: "첫 번째", plannedAt: plannedDate, order: 100)
    let second = Task(title: "두 번째", status: .doing, plannedAt: plannedDate, order: 200)

    TaskRules.completeAll([first, second], now: now)

    #expect(first.status == TaskStatus.done.rawValue)
    #expect(first.completedAt == now)
    #expect(first.completedDayKey == "2026-07-07")
    #expect(second.status == TaskStatus.done.rawValue)
    #expect(second.completedAt == now)
    #expect(second.completedDayKey == "2026-07-07")
}

@Test
func boardQueryRulesPreserveDesktopAndMobileCarryoverPolicies() throws {
    let yesterday = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let todayKey = DayKey.key(for: today)
    let completionTime = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 11)))

    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let carryoverTask = Task(title: "이월 작업", plannedAt: yesterday, order: 100)
    let doneToday = Task(title: "오늘 완료", plannedAt: yesterday, order: 200)
    TaskRules.applyStatus(.done, to: doneToday, now: completionTime)

    let tasks = [carryoverTask, doneToday, todayTask]
    let desktopBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey
    )
    let mobileBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey,
        includeCarryoverOnToday: true
    )

    #expect(Set(desktopBoard.map(\.title)) == Set(["오늘 완료", "오늘 작업"]))
    #expect(Set(mobileBoard.map(\.title)) == Set(["오늘 완료", "이월 작업", "오늘 작업"]))
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .todo).map(\.title) == ["이월 작업", "오늘 작업"])
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .done).map(\.title) == ["오늘 완료"])
}

@Test
func boardNextOrderUsesOnlyTargetDayAndStatus() throws {
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let otherDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let targetKey = DayKey.key(for: targetDate)

    let targetTodo = Task(title: "대상 날짜", plannedAt: targetDate, order: 300)
    let targetDoing = Task(title: "진행 중", status: .doing, plannedAt: targetDate, order: 900)
    let otherTodo = Task(title: "다른 날짜", plannedAt: otherDate, order: 9_000)

    let nextTodoOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .todo
    )
    let nextDoingOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .doing
    )

    #expect(nextTodoOrder == 400)
    #expect(nextDoingOrder == 1_000)
}
