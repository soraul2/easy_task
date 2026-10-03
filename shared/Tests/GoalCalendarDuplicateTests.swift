import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Calendar grid/recommendations and the integrity contract choose one active
// physical representative per logical ID, by (updatedAt, instanceID).
// These ordinary regression tests intentionally expose the starting day helper's
// different behavior. No production data, CloudKit, or UI process is involved.
@MainActor
private func goalDuplicateEvent(
    logicalID: Int = 1, physicalID: Int, title: String = "공장 점검",
    start: String = "2026-08-06", end: String? = nil,
    updatedAt: Double, supersededAt: Double? = nil
) throws -> CalendarEvent {
    let startDate = try #require(DayKey.date(from: start))
    let endDate = try #require(DayKey.date(from: end ?? start))
    return CalendarEvent(
        id: goalDuplicateID(logicalID), instanceID: goalDuplicateID(physicalID),
        title: title, startAt: startDate, endAt: endDate,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        supersededAt: supersededAt.map { Date(timeIntervalSince1970: $0) })
}

private func goalDuplicateID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func goalDuplicateContainer(events: [CalendarEvent]) throws -> ModelContainer {
    let container = try PlanBaseContainerFactory.makeInMemory()
    for event in events { container.mainContext.insert(event) }
    try container.mainContext.save()
    return container
}

@MainActor
private func goalDuplicateLayoutItems(_ events: [CalendarEvent]) -> [CalendarEventGridLayoutItem] {
    events.filter { $0.supersededAt == nil }.map {
        CalendarEventGridLayoutItem(
            renderID: $0.instanceID, eventID: $0.id, title: $0.title,
            startDayKey: $0.startDayKey, endDayKey: $0.endDayKey, updatedAt: $0.updatedAt)
    }
}

@MainActor
private func goalDuplicateMonthLayout(_ events: [CalendarEvent]) throws -> CalendarEventGridLayoutResult {
    let month = try #require(DayKey.date(from: "2026-08-01"))
    return CalendarEventGridLayout.make(items: goalDuplicateLayoutItems(events),
        dates: DayKey.adaptiveMonthGridDates(for: month), visibleMonth: month, maximumLanes: 4)
}

@Test @MainActor
func goalCalendarDayRowsChooseLatestPhysicalRepresentativeLikeMonthLayout() throws {
    // Timestamp wins even when the older physical UUID sorts higher.
    let older = try goalDuplicateEvent(physicalID: 102, updatedAt: 10)
    let latest = try goalDuplicateEvent(physicalID: 101, updatedAt: 20)
    let container = try goalDuplicateContainer(events: [older, latest])
    let events = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())

    let layout = try goalDuplicateMonthLayout(events)
    #expect(Set(layout.segments.map(\.renderID)) == Set([latest.instanceID]))
    #expect(layout.displayedEventIDsByDayKey["2026-08-06"] == Set([latest.id]))
    let dayRows = CalendarEventRules.events(onDayKey: "2026-08-06", in: events)
    #expect(dayRows.map(\.instanceID) == [latest.instanceID])
}

@Test @MainActor
func goalCalendarDayRowsBreakTimestampTiesByPhysicalIDLikeMonthLayout() throws {
    let lower = try goalDuplicateEvent(physicalID: 101, updatedAt: 20)
    let higher = try goalDuplicateEvent(physicalID: 102, updatedAt: 20)
    let container = try goalDuplicateContainer(events: [higher, lower])
    let stored = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())

    // Both input orders must choose the same physical row.
    for events in [stored, Array(stored.reversed())] {
        let layout = try goalDuplicateMonthLayout(events)
        #expect(Set(layout.segments.map(\.renderID)) == Set([higher.instanceID]))
        let dayRows = CalendarEventRules.events(onDayKey: "2026-08-06", in: events)
        #expect(dayRows.map(\.instanceID) == [higher.instanceID])
    }
}

@Test @MainActor
func goalCalendarDayFilterDoesNotReviveOlderRangeAfterRepresentativeMoved() throws {
    let older = try goalDuplicateEvent(physicalID: 101, start: "2026-08-06", end: "2026-08-08", updatedAt: 10)
    let latest = try goalDuplicateEvent(physicalID: 102, start: "2026-08-19", end: "2026-08-21", updatedAt: 20)
    let container = try goalDuplicateContainer(events: [older, latest])
    // Both versions are available to the helper. This isolates selecting the
    // representative before testing its range, rather than a query-bound gap.
    let events = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())
    let layout = try goalDuplicateMonthLayout(events)
    #expect(Set(layout.segments.map(\.renderID)) == Set([latest.instanceID]))
    #expect((layout.displayedEventIDsByDayKey["2026-08-06"] ?? []).isEmpty)
    #expect(CalendarEventRules.events(onDayKey: "2026-08-06", in: events).isEmpty)
    #expect(CalendarEventRules.events(onDayKey: "2026-08-19", in: events).map(\.instanceID)
        == [latest.instanceID])
}

@Test @MainActor
func goalCalendarRepresentativesIgnoreSupersededPhysicalCandidates() throws {
    let active = try goalDuplicateEvent(physicalID: 101, updatedAt: 10)
    let superseded = try goalDuplicateEvent(physicalID: 102, updatedAt: 100, supersededAt: 200)
    let container = try goalDuplicateContainer(events: [superseded, active])
    let events = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())

    let layout = try goalDuplicateMonthLayout(events)
    #expect(Set(layout.segments.map(\.renderID)) == Set([active.instanceID]))
    #expect(CalendarEventRules.events(onDayKey: "2026-08-06", in: events).map(\.instanceID)
        == [active.instanceID])
}

@Test @MainActor
func goalCalendarSameTitleDoesNotCollapseDifferentLogicalEvents() throws {
    let first = try goalDuplicateEvent(logicalID: 1, physicalID: 101, updatedAt: 20)
    let second = try goalDuplicateEvent(logicalID: 2, physicalID: 102, updatedAt: 20)
    let container = try goalDuplicateContainer(events: [first, second])
    let events = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())

    let layout = try goalDuplicateMonthLayout(events)
    #expect(layout.displayedEventIDsByDayKey["2026-08-06"] == Set([first.id, second.id]))
    #expect(Set(CalendarEventRules.events(onDayKey: "2026-08-06", in: events).map(\.instanceID))
        == Set([first.instanceID, second.instanceID]))
}

@Test @MainActor
func goalCalendarOverlappingQueryIsNotACompleteLogicalRepresentativeSet() throws {
    let older = try goalDuplicateEvent(physicalID: 101, start: "2026-08-06", updatedAt: 10)
    let latest = try goalDuplicateEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    let container = try goalDuplicateContainer(events: [older, latest])
    let context = container.mainContext

    // This passing diagnostic records why fixing array deduplication alone is
    // insufficient. Even the 42-day August grid excludes the moved latest row.
    let month = try #require(DayKey.date(from: "2026-08-01"))
    let dates = DayKey.adaptiveMonthGridDates(for: month)
    let lower = DayKey.key(for: try #require(dates.first))
    let upper = DayKey.key(for: try #require(dates.last))
    let overlapping = try context.fetch(BoundedQueryService.eventsDescriptor(
        overlappingStartDayKey: lower, endDayKey: upper))
    #expect(overlapping.map(\.instanceID) == [older.instanceID])

    let allCandidates = try context.fetch(FetchDescriptor<CalendarEvent>())
    let representatives = CalendarEventGridLayout.representativeItems(from: goalDuplicateLayoutItems(allCandidates))
    #expect(representatives.map(\.renderID) == [latest.instanceID])
    #expect((try goalDuplicateMonthLayout(allCandidates)).segments.isEmpty)
}
