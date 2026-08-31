import Foundation
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func plannerWidgetPreviewsCoverEightDaysIncludingEmptyDays() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-08-31"))

    let previews = PlannerWidgetRules.makeTaskPreviewsByDayKey(
        tasks: [],
        referenceDate: referenceDate
    )

    #expect(previews.count == 8)
    #expect(previews.keys.sorted() == [
        "2026-08-31",
        "2026-09-01",
        "2026-09-02",
        "2026-09-03",
        "2026-09-04",
        "2026-09-05",
        "2026-09-06",
        "2026-09-07"
    ])
    let totalPreviewCount = previews.values.reduce(0) { $0 + $1.count }
    #expect(totalPreviewCount == 0)
}

@Test
@MainActor
func plannerWidgetPreviewsPreferDoingAndCapAtSix() throws {
    let today = try #require(DayKey.date(from: "2026-08-31"))
    let tasks = [
        makePlannerTask(title: "예정 B", status: .todo, plannedAt: today, order: 20),
        makePlannerTask(title: "진행 B", status: .doing, plannedAt: today, order: 20),
        makePlannerTask(title: "예정 A", status: .todo, plannedAt: today, order: 10),
        makePlannerTask(title: "진행 A", status: .doing, plannedAt: today, order: 10),
        makePlannerTask(title: "예정 C", status: .todo, plannedAt: today, order: 30),
        makePlannerTask(title: "예정 D", status: .todo, plannedAt: today, order: 40),
        makePlannerTask(title: "표시 제한 밖", status: .todo, plannedAt: today, order: 50)
    ]

    let previews = try #require(PlannerWidgetRules.makeTaskPreviewsByDayKey(
        tasks: tasks,
        referenceDate: today
    )["2026-08-31"])

    #expect(previews.count == 6)
    #expect(previews.map(\.title) == [
        "진행 A", "진행 B", "예정 A", "예정 B", "예정 C", "예정 D"
    ])
    #expect(previews.map(\.status) == [
        .doing, .doing, .todo, .todo, .todo, .todo
    ])
}

@Test
@MainActor
func plannerWidgetPreviewsExcludeCarryoverUntilMovedToToday() throws {
    let today = try #require(DayKey.date(from: "2026-08-31"))
    let yesterday = DayKey.addingDays(-1, to: today)
    let carryover = makePlannerTask(
        title: "이월함 작업",
        status: .todo,
        plannedAt: yesterday,
        order: 0
    )

    var previews = PlannerWidgetRules.makeTaskPreviewsByDayKey(
        tasks: [carryover],
        referenceDate: today
    )
    #expect(previews["2026-08-31"]?.isEmpty == true)

    carryover.plannedAt = today
    carryover.plannedDayKey = DayKey.key(for: today)
    carryover.updatedAt = today
    previews = PlannerWidgetRules.makeTaskPreviewsByDayKey(
        tasks: [carryover],
        referenceDate: today
    )
    #expect(previews["2026-08-31"]?.map(\.title) == ["이월함 작업"])
}

@Test
@MainActor
func plannerWidgetPreviewsUseLatestValidRepresentative() throws {
    let today = try #require(DayKey.date(from: "2026-08-31"))
    let logicalID = UUID()
    let older = makePlannerTask(
        id: logicalID,
        title: "이전 작업",
        status: .todo,
        plannedAt: today,
        order: 0,
        updatedAt: today
    )
    let newer = makePlannerTask(
        id: logicalID,
        title: "최신 작업",
        status: .doing,
        plannedAt: today,
        order: 0,
        updatedAt: DayKey.addingDays(1, to: today)
    )
    let archived = makePlannerTask(
        title: "보관 작업",
        status: .todo,
        plannedAt: today,
        order: 0
    )
    archived.archivedAt = today
    let completed = makePlannerTask(
        title: "완료 작업",
        status: .done,
        plannedAt: today,
        order: 0
    )
    let invalid = makePlannerTask(
        title: "잘못된 상태",
        status: .todo,
        plannedAt: today,
        order: 0
    )
    invalid.status = "invalid"

    let previews = try #require(PlannerWidgetRules.makeTaskPreviewsByDayKey(
        tasks: [older, archived, completed, invalid, newer],
        referenceDate: today
    )["2026-08-31"])

    #expect(previews.count == 1)
    #expect(previews.first?.title == "최신 작업")
    #expect(previews.first?.renderID == newer.instanceID)
}

@MainActor
private func makePlannerTask(
    id: UUID = UUID(),
    title: String,
    status: TaskStatus,
    plannedAt: Date,
    order: Double,
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
