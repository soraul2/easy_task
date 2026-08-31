import Foundation
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func todayTaskWidgetRulesExcludeCarryoverAndChooseDeterministicRepresentatives() throws {
    let today = try #require(DayKey.date(from: "2026-08-31"))
    let yesterday = DayKey.addingDays(-1, to: today)
    let logicalID = UUID()
    let older = makeTodayWidgetTask(
        id: logicalID,
        title: "이전",
        status: .todo,
        plannedAt: today,
        updatedAt: today
    )
    let newer = makeTodayWidgetTask(
        id: logicalID,
        title: "현재",
        status: .doing,
        plannedAt: today,
        updatedAt: DayKey.addingDays(1, to: today)
    )
    let carryover = makeTodayWidgetTask(
        title: "이월",
        status: .doing,
        plannedAt: yesterday
    )

    let tasks = TodayTaskWidgetRules.eligibleRepresentatives(
        from: [older, carryover, newer],
        dayKey: "2026-08-31"
    )

    #expect(tasks.count == 1)
    #expect(tasks.first?.instanceID == newer.instanceID)
}

@Test
@MainActor
func todayTaskWidgetRulesAdvancePrefersAnotherDoingThenTodo() throws {
    let today = try #require(DayKey.date(from: "2026-08-31"))
    let current = makeTodayWidgetTask(
        title: "현재",
        status: .doing,
        plannedAt: today,
        order: 0
    )
    let otherDoing = makeTodayWidgetTask(
        title: "다른 진행",
        status: .doing,
        plannedAt: today,
        order: 1
    )
    let todo = makeTodayWidgetTask(
        title: "다음 예정",
        status: .todo,
        plannedAt: today,
        order: 0
    )

    #expect(
        TodayTaskWidgetRules.nextTask(
            after: current.id,
            from: [todo, otherDoing, current],
            dayKey: "2026-08-31"
        )?.id == otherDoing.id
    )

    otherDoing.status = TaskStatus.done.rawValue
    #expect(
        TodayTaskWidgetRules.nextTask(
            after: current.id,
            from: [todo, otherDoing, current],
            dayKey: "2026-08-31"
        )?.id == todo.id
    )
}

@MainActor
private func makeTodayWidgetTask(
    id: UUID = UUID(),
    title: String,
    status: TaskStatus,
    plannedAt: Date,
    order: Double = 0,
    updatedAt: Date? = nil
) -> Task {
    Task(
        id: id,
        title: title,
        status: status,
        plannedAt: plannedAt,
        order: order,
        createdAt: plannedAt,
        updatedAt: updatedAt ?? plannedAt
    )
}
