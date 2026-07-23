import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func lockScreenWidgetDescriptorsFetchPlannedAndCompletedCoverageWithoutCarryover() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let yesterday = try #require(DayKey.date(from: "2026-07-15"))
    let today = try #require(DayKey.date(from: "2026-07-16"))
    let lastDay = try #require(DayKey.date(from: "2026-07-23"))
    let outside = try #require(DayKey.date(from: "2026-07-24"))
    let planned = Task(title: "계획됨", plannedAt: today, order: 0)
    let completed = Task(title: "오늘 완료", status: .done, plannedAt: yesterday, order: 0)
    completed.completedDayKey = "2026-07-16"
    let last = Task(title: "마지막 날", plannedAt: lastDay, order: 0)
    let carryover = Task(title: "이월", plannedAt: yesterday, order: 0)
    let after = Task(title: "범위 밖", plannedAt: outside, order: 0)
    let archived = Task(title: "보관", plannedAt: today, order: 0)
    archived.archivedAt = today
    let superseded = Task(title: "대체", plannedAt: today, order: 0)
    superseded.supersededAt = today
    [planned, completed, last, carryover, after, archived, superseded].forEach(context.insert)
    try context.save()

    let plannedRows = try context.fetch(
        BoundedQueryService.widgetPlannedTasksDescriptor(
            from: "2026-07-16",
            through: "2026-07-23"
        )
    )
    let completedRows = try context.fetch(
        BoundedQueryService.widgetCompletedTasksDescriptor(
            from: "2026-07-16",
            through: "2026-07-23"
        )
    )

    #expect(Set(plannedRows.map(\.title)) == Set(["계획됨", "마지막 날"]))
    #expect(completedRows.map(\.title) == ["오늘 완료"])
}
