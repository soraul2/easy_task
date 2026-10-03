import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private func goalCountID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

private func goalCountDate(_ key: String) throws -> Date {
    try #require(DayKey.date(from: key))
}

@MainActor
private func goalCountEvent(
    logicalID: Int, physicalID: Int, start: String, end: String? = nil,
    title: String = "같은 제목", updatedAt: Double = 1, superseded: Bool = false
) throws -> CalendarEvent {
    CalendarEvent(
        id: goalCountID(logicalID), instanceID: goalCountID(physicalID), title: title,
        startAt: try goalCountDate(start), endAt: try goalCountDate(end ?? start),
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        supersededAt: superseded ? Date(timeIntervalSince1970: 100) : nil)
}

@MainActor
private func goalCountPlacement(
    logicalID: Int, physicalID: Int, key: String, superseded: Bool = false
) -> TemplatePlacement {
    TemplatePlacement(
        id: goalCountID(logicalID), instanceID: goalCountID(physicalID),
        sourceTemplateId: nil, templateName: "배치", dayKey: key,
        createdAt: Date(timeIntervalSince1970: Double(physicalID)),
        updatedAt: Date(timeIntervalSince1970: 1),
        supersededAt: superseded ? Date(timeIntervalSince1970: 100) : nil)
}

@MainActor
private struct GoalCountFixture {
    let container: ModelContainer
    let events: [CalendarEvent]
    let placements: [TemplatePlacement]

    init(events: [CalendarEvent] = [], placements: [TemplatePlacement] = []) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        self.events = events
        self.placements = placements
        for event in events { container.mainContext.insert(event) }
        for placement in placements { container.mainContext.insert(placement) }
        try container.mainContext.save()
    }

    func projection(dates: [Date]) -> CalendarMonthCountProjection {
        CalendarMonthCountProjection.make(dates: dates, events: events, templatePlacements: placements)
    }
}

@Test @MainActor
func goalCalendarCountProjectionHasExplicitZeroesAndNoUnrequestedKeys() throws {
    let fixture = try GoalCountFixture()
    let dates = try ["2026-08-06", "2026-08-07"].map(goalCountDate)
    let counts = fixture.projection(dates: dates)
    #expect(counts.eventCountByDayKey == ["2026-08-06": 0, "2026-08-07": 0])
    #expect(counts.placementCountByDayKey == counts.eventCountByDayKey)
    #expect(counts.eventCount(onDayKey: "2026-08-08") == 0)
    #expect(counts.placementCount(onDayKey: "2026-08-08") == 0)
    #expect(fixture.projection(dates: []).eventCountByDayKey.isEmpty)
    #expect(fixture.projection(dates: []).placementCountByDayKey.isEmpty)
}

@Test @MainActor
func goalCalendarCountProjectionMatchesDayHelpersForFiveAndSixWeekGrids() throws {
    for monthKey in ["2026-07-01", "2026-08-01"] {
        let dates = DayKey.adaptiveMonthGridDates(for: try goalCountDate(monthKey))
        #expect(dates.count == (monthKey == "2026-07-01" ? 35 : 42))
        let start = try #require(dates.first)
        var events: [CalendarEvent] = []
        var placements: [TemplatePlacement] = []
        for index in 0..<80 {
            let eventStart = DayKey.addingDays(index % dates.count - 2, to: start)
            let eventEnd = DayKey.addingDays(index % 12, to: eventStart)
            events.append(try goalCountEvent(
                logicalID: index + 1, physicalID: index + 1_001,
                start: DayKey.key(for: eventStart), end: DayKey.key(for: eventEnd),
                superseded: index.isMultiple(of: 11)))
            placements.append(goalCountPlacement(
                logicalID: index + 2_001, physicalID: index + 3_001,
                key: DayKey.key(for: dates[index % dates.count]), superseded: index.isMultiple(of: 13)))
        }
        let fixture = try GoalCountFixture(events: events, placements: placements)
        let counts = fixture.projection(dates: dates)
        for date in dates {
            let key = DayKey.key(for: date)
            #expect(counts.eventCount(onDayKey: key) == CalendarEventRules.events(on: date, in: fixture.events).count)
            #expect(counts.placementCount(onDayKey: key) == TemplateService.placements(on: date, in: fixture.placements).count)
        }
    }
}

@Test @MainActor
func goalCalendarCountProjectionSelectsRepresentativeBeforeDateFilter() throws {
    let fixture = try GoalCountFixture(events: [
        goalCountEvent(logicalID: 1, physicalID: 102, start: "2026-08-06", end: "2026-08-08", updatedAt: 10),
        goalCountEvent(logicalID: 1, physicalID: 101, start: "2026-08-19", end: "2026-08-21", updatedAt: 20),
        goalCountEvent(logicalID: 2, physicalID: 201, start: "2026-08-06", updatedAt: 30),
        goalCountEvent(logicalID: 2, physicalID: 202, start: "2026-08-19", updatedAt: 30),
        goalCountEvent(logicalID: 3, physicalID: 301, start: "2026-08-06", updatedAt: 10),
        goalCountEvent(logicalID: 3, physicalID: 302, start: "2026-08-19", updatedAt: 50, superseded: true),
        goalCountEvent(logicalID: 4, physicalID: 401, start: "2026-08-06"),
        goalCountEvent(logicalID: 5, physicalID: 501, start: "2026-08-06")
    ])
    let dates = try ["2026-08-06", "2026-08-07", "2026-08-19", "2026-08-20"].map(goalCountDate)
    let expected = ["2026-08-06": 3, "2026-08-07": 0, "2026-08-19": 2, "2026-08-20": 1]
    #expect(fixture.projection(dates: dates).eventCountByDayKey == expected)
    let reversed = CalendarMonthCountProjection.make(
        dates: dates, events: Array(fixture.events.reversed()), templatePlacements: [])
    #expect(reversed.eventCountByDayKey == expected)
}

@Test @MainActor
func goalCalendarCountProjectionDoesNotReviveOutsideMonthLatestVersion() throws {
    let fixture = try GoalCountFixture(events: [
        goalCountEvent(logicalID: 1, physicalID: 101, start: "2026-08-06", updatedAt: 10),
        goalCountEvent(logicalID: 1, physicalID: 102, start: "2026-09-10", updatedAt: 20)
    ])
    let dates = DayKey.adaptiveMonthGridDates(for: try goalCountDate("2026-08-01"))
    #expect(fixture.projection(dates: dates).eventCountByDayKey.values.allSatisfy { $0 == 0 })
}

@Test @MainActor
func goalCalendarCountProjectionPreservesActivePhysicalPlacementPolicy() throws {
    let fixture = try GoalCountFixture(placements: [
        goalCountPlacement(logicalID: 1, physicalID: 101, key: "2026-08-06"),
        goalCountPlacement(logicalID: 1, physicalID: 102, key: "2026-08-06"),
        goalCountPlacement(logicalID: 1, physicalID: 103, key: "2026-08-06", superseded: true),
        goalCountPlacement(logicalID: 2, physicalID: 201, key: "2026-09-10")
    ])
    let dates = try ["2026-08-06", "2026-08-07"].map(goalCountDate)
    let counts = fixture.projection(dates: dates)
    #expect(counts.placementCountByDayKey == ["2026-08-06": 2, "2026-08-07": 0])
    #expect(counts.placementCountByDayKey["2026-09-10"] == nil)
}

@Test @MainActor
func goalCalendarCountProjectionCountsInclusiveYearBoundaryAndDuplicateDatesOnce() throws {
    let fixture = try GoalCountFixture(events: [
        goalCountEvent(logicalID: 1, physicalID: 101, start: "2026-12-31", end: "2027-01-02")
    ])
    let dates = try ["2027-01-02", "2026-12-30", "2027-01-01", "2026-12-31", "2027-01-01", "2027-01-03"].map(goalCountDate)
    #expect(fixture.projection(dates: dates).eventCountByDayKey == [
        "2026-12-30": 0, "2026-12-31": 1, "2027-01-01": 1, "2027-01-02": 1, "2027-01-03": 0
    ])
}

@Test @MainActor
func goalCalendarCountProjectionValueDoesNotRetainMutableModels() throws {
    let fixture = try GoalCountFixture(events: [
        goalCountEvent(logicalID: 1, physicalID: 101, start: "2026-08-06")
    ])
    let dates = try ["2026-08-06", "2026-08-07"].map(goalCountDate)
    let before = fixture.projection(dates: dates)
    let event = try #require(fixture.events.first)
    event.startDayKey = "2026-08-07"
    event.endDayKey = "2026-08-07"
    let after = fixture.projection(dates: dates)
    #expect(before.eventCountByDayKey == ["2026-08-06": 1, "2026-08-07": 0])
    #expect(after.eventCountByDayKey == ["2026-08-06": 0, "2026-08-07": 1])
    // No save is needed to rebuild counts from the current visible model rows.
    fixture.container.mainContext.rollback()
    #expect(fixture.projection(dates: dates) == before)
}
