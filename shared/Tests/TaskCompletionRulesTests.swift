import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func applyingSameDoneStatusPreservesCompletionMetadata() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let firstCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let secondCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let task = Task(title: "완료 날짜 보존", plannedAt: plannedDate, order: 100)

    TaskRules.applyStatus(.done, to: task, now: firstCompletionDate)
    let completedAt = task.completedAt
    let completedDayKey = task.completedDayKey
    let updatedAt = task.updatedAt

    TaskRules.applyStatus(.done, to: task, now: secondCompletionDate)

    #expect(task.completedAt == completedAt)
    #expect(task.completedDayKey == completedDayKey)
    #expect(task.updatedAt == updatedAt)
}

@Test
func completionDayCanFollowBoardDateInsteadOfActualCompletionDate() throws {
    let july4 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let july8Completion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 21)))
    let july4Key = DayKey.key(for: july4)
    let july7Key = DayKey.key(for: july7)
    let todayKey = DayKey.key(for: july8Completion)
    let originalBoardTask = Task(title: "7월 4일 보드 완료", plannedAt: july4, order: 100)
    let movedTask = Task(title: "7월 7일로 이월 후 완료", plannedAt: july4, order: 200)

    TaskRules.applyStatus(.done, to: originalBoardTask, now: july8Completion, completionDayKey: july4Key)
    TaskRules.move(movedTask, to: july7)
    TaskRules.applyStatus(.done, to: movedTask, now: july8Completion, completionDayKey: movedTask.plannedDayKey)

    #expect(originalBoardTask.completedAt == july8Completion)
    #expect(originalBoardTask.completedDayKey == july4Key)
    #expect(movedTask.completedAt == july8Completion)
    #expect(movedTask.completedDayKey == july7Key)

    let july4Board = BoardQueryRules.tasksForBoard(
        [originalBoardTask, movedTask],
        selectedDayKey: july4Key,
        todayKey: todayKey
    )
    let july7Board = BoardQueryRules.tasksForBoard(
        [originalBoardTask, movedTask],
        selectedDayKey: july7Key,
        todayKey: todayKey
    )

    #expect(BoardQueryRules.tasks(july4Board, matching: .done).map(\.title) == ["7월 4일 보드 완료"])
    #expect(BoardQueryRules.tasks(july7Board, matching: .done).map(\.title) == ["7월 7일로 이월 후 완료"])
}
