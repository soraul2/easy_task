import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func boundedBoardFetchReturnsOneDayFromTenThousandTasks() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let firstDate = try #require(DayKey.date(from: "2026-01-01"))
    let targetDayKey = "2026-02-10"

    for index in 0..<10_000 {
        let date = DayKey.addingDays(index % 100, to: firstDate)
        context.insert(Task(
            title: "작업 \(index)",
            plannedAt: date,
            order: Double(index)
        ))
    }
    try context.save()

    let clock = ContinuousClock()
    let startedAt = clock.now
    let rows = try context.fetch(BoundedQueryService.boardTasksDescriptor(
        selectedDayKey: targetDayKey
    ))
    let elapsed = startedAt.duration(to: clock.now)

    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 10_000)
    #expect(rows.count == 100)
    #expect(rows.allSatisfy { $0.plannedDayKey == targetDayKey })
    #expect(elapsed < .seconds(5))
}

@Test
@MainActor
func boundedBoardAndCarryoverDescriptorsPreserveVisibilityRules() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = try #require(DayKey.date(from: "2026-07-12"))
    let yesterday = try #require(DayKey.date(from: "2026-07-11"))
    let tomorrow = try #require(DayKey.date(from: "2026-07-13"))

    let todayTask = Task(title: "오늘", plannedAt: today, order: 100)
    let carryover = Task(title: "이월", plannedAt: yesterday, order: 100)
    let future = Task(title: "미래", plannedAt: tomorrow, order: 100)
    let completed = Task(title: "완료", status: .done, plannedAt: today, order: 100)
    completed.completedDayKey = "2026-07-12"
    let superseded = Task(title: "대체됨", plannedAt: yesterday, order: 200)
    superseded.supersededAt = Date()
    [todayTask, carryover, future, completed, superseded].forEach(context.insert)
    try context.save()

    let boardRows = try context.fetch(BoundedQueryService.boardTasksDescriptor(
        selectedDayKey: "2026-07-12"
    ))
    let carryoverRows = try context.fetch(BoundedQueryService.carryoverTasksDescriptor(
        before: "2026-07-12"
    ))

    #expect(Set(boardRows.map(\.title)) == Set(["오늘", "완료"]))
    #expect(carryoverRows.map(\.title) == ["이월"])
}

@Test
@MainActor
func boundedCalendarDescriptorsFetchOnlyOverlappingRange() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let june = try #require(DayKey.date(from: "2026-06-20"))
    let julyStart = try #require(DayKey.date(from: "2026-07-02"))
    let julyEnd = try #require(DayKey.date(from: "2026-07-15"))
    let august = try #require(DayKey.date(from: "2026-08-01"))

    let before = CalendarEvent(title: "이전", startAt: june, endAt: june)
    let overlapping = CalendarEvent(title: "겹침", startAt: julyStart, endAt: julyEnd)
    let after = CalendarEvent(title: "이후", startAt: august, endAt: august)
    let placement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "7월 배치",
        dayKey: "2026-07-10"
    )
    let outsidePlacement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "8월 배치",
        dayKey: "2026-08-10"
    )
    [before, overlapping, after].forEach(context.insert)
    [placement, outsidePlacement].forEach(context.insert)
    try context.save()

    let events = try context.fetch(BoundedQueryService.eventsDescriptor(
        overlappingStartDayKey: "2026-07-01",
        endDayKey: "2026-07-31"
    ))
    let placements = try context.fetch(BoundedQueryService.templatePlacementsDescriptor(
        from: "2026-07-01",
        through: "2026-07-31"
    ))

    #expect(events.map(\.title) == ["겹침"])
    #expect(placements.map(\.templateName) == ["7월 배치"])
}

@Test
@MainActor
func boundedNextOrderAndEventLinksAvoidWholeTaskArray() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: "2026-07-12"))
    let eventID = UUID()
    let first = Task(title: "첫 작업", plannedAt: date, order: 100, eventId: eventID)
    let second = Task(title: "둘째 작업", plannedAt: date, order: 350, eventId: eventID)
    let other = Task(
        title: "다른 상태",
        status: .doing,
        plannedAt: date,
        order: 900
    )
    [first, second, other].forEach(context.insert)
    try context.save()

    #expect(try BoundedQueryService.nextOrder(
        in: context,
        dayKey: "2026-07-12",
        status: .todo
    ) == 450)
    #expect(Set(try BoundedQueryService.tasksLinked(
        toEventID: eventID,
        in: context
    ).map(\.id)) == Set([first.id, second.id]))
}
