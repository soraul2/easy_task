import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum GoalSnapshotQueryFailure: Error { case unavailable }

private func goalSnapshotQueryID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func goalSnapshotQueryEvent(
    logicalID: Int = 1, physicalID: Int, key: String = "2026-08-06",
    title: String = "같은 제목", updatedAt: Double, superseded: Bool = false
) throws -> CalendarEvent {
    let date = try #require(DayKey.date(from: key))
    return CalendarEvent(
        id: goalSnapshotQueryID(logicalID), instanceID: goalSnapshotQueryID(physicalID),
        title: title, startAt: date, endAt: date,
        createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: updatedAt),
        supersededAt: superseded ? Date(timeIntervalSince1970: 100) : nil)
}

@MainActor
private func goalSnapshotQueryContainer(_ events: [CalendarEvent]) throws -> ModelContainer {
    let container = try PlanBaseContainerFactory.makeInMemory()
    for event in events { container.mainContext.insert(event) }
    try container.mainContext.save()
    return container
}

@Test @MainActor
func goalCalendarSnapshotRangeReaderDoesNotReviveVersionMovedOutsidePublicationCoverage() throws {
    let old = try goalSnapshotQueryEvent(physicalID: 101, updatedAt: 10)
    let latest = try goalSnapshotQueryEvent(physicalID: 102, key: "2026-11-10", updatedAt: 20)
    let container = try goalSnapshotQueryContainer([old, latest])
    let context = container.mainContext
    let reference = try #require(DayKey.date(from: "2026-08-06"))
    let coverage = CalendarWidgetSnapshot.coverageDayKeys(for: reference)
    let seeds = try context.fetch(BoundedQueryService.eventsDescriptor(
        overlappingStartDayKey: coverage.startDayKey, endDayKey: coverage.endDayKey))
    #expect(seeds.map(\.instanceID) == [old.instanceID])
    let calendarRows = try BoundedQueryService.events(
        overlappingStartDayKey: coverage.startDayKey, endDayKey: coverage.endDayKey, in: context)
    let calendar = CalendarWidgetSnapshot.make(events: calendarRows, tasks: [], referenceDate: reference)
    #expect(calendar.events.isEmpty)
    #expect(calendar.totalEventCount(onDayKey: "2026-08-06") == 0)
    #expect(calendar.lockScreenSummary(onDayKey: "2026-08-06")?.eventCount == 0)
    let watchRows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    let watch = WatchWidgetSnapshot.make(tasks: [], events: watchRows, referenceDate: reference)
    #expect(watch.eventCount == 0)
    #expect(watch.focusTitle == nil)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 2)
    #expect(old.supersededAt == nil)
    #expect(!context.hasChanges)
}

@Test @MainActor
func goalCalendarSnapshotReaderAndVisibilityKeepPendingBlankInvalidAndTieRepresentatives() throws {
    let reference = try #require(DayKey.date(from: "2026-08-06"))
    for scenario in ["blank", "invalid", "tie-blank"] {
        let old = try goalSnapshotQueryEvent(physicalID: 101, updatedAt: 10)
        let container = try goalSnapshotQueryContainer([old])
        let context = container.mainContext
        let latest = try goalSnapshotQueryEvent(physicalID: 102, updatedAt: scenario == "tie-blank" ? 10 : 20)
        if scenario == "invalid" {
            latest.startDayKey = "2026-02-30"
        } else {
            latest.title = " \n\t "
        }
        context.insert(latest)
        let rows = try BoundedQueryService.events(
            overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
        #expect(rows.map(\.instanceID) == [latest.instanceID])
        let calendar = CalendarWidgetSnapshot.make(events: rows, tasks: [], referenceDate: reference)
        let watch = WatchWidgetSnapshot.make(tasks: [], events: rows, referenceDate: reference)
        #expect(calendar.events.isEmpty)
        #expect(calendar.totalEventCount(onDayKey: "2026-08-06") == 0)
        #expect(calendar.lockScreenSummary(onDayKey: "2026-08-06")?.eventCount == 0)
        #expect(watch.eventCount == 0)
        #expect(watch.focusTitle == nil)
        #expect(context.hasChanges)
        context.rollback()
        let restored = try BoundedQueryService.events(
            overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
        #expect(CalendarWidgetSnapshot.make(events: restored, referenceDate: reference)
            .totalEventCount(onDayKey: "2026-08-06") == 1)
    }
}

@Test @MainActor
func goalCalendarSnapshotReaderPreservesSupersededDistinctIDsAndPreCapCounts() throws {
    let old = try goalSnapshotQueryEvent(physicalID: 101, updatedAt: 10)
    let superseded = try goalSnapshotQueryEvent(physicalID: 102, title: " ", updatedAt: 100, superseded: true)
    let separate = try goalSnapshotQueryEvent(logicalID: 2, physicalID: 201, updatedAt: 20)
    let container = try goalSnapshotQueryContainer([superseded, separate, old])
    let context = container.mainContext
    let reference = try #require(DayKey.date(from: "2026-08-06"))
    let rows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    #expect(Set(rows.map(\.instanceID)) == Set([old.instanceID, separate.instanceID]))
    let calendar = CalendarWidgetSnapshot.make(events: rows, tasks: [], referenceDate: reference, maximumEventCount: 1)
    #expect(calendar.events.count == 1)
    #expect(calendar.totalEventCount(onDayKey: "2026-08-06") == 2)
    #expect(calendar.lockScreenSummary(onDayKey: "2026-08-06")?.eventCount == 2)
    #expect(WatchWidgetSnapshot.make(tasks: [], events: rows, referenceDate: reference).eventCount == 2)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 3)
    #expect(!context.hasChanges)
}

@Test @MainActor
func goalCalendarSnapshotCandidateFetchFailureKeepsPreviousValueAndRetryDoesNotReviveOldRange() throws {
    let old = try goalSnapshotQueryEvent(physicalID: 101, updatedAt: 10)
    let container = try goalSnapshotQueryContainer([old])
    let context = container.mainContext
    let reference = try #require(DayKey.date(from: "2026-08-06"))
    let previous = CalendarWidgetSnapshot.make(events: [old], referenceDate: reference)
    var publishedValue = previous
    context.insert(try goalSnapshotQueryEvent(physicalID: 102, key: "2026-11-10", updatedAt: 20))
    try context.save()
    var fetchCount = 0
    var snapshotAssignments = 0
    do {
        let rows = try BoundedQueryService.representativeCalendarEvents(
            overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", fetch: { descriptor in
                fetchCount += 1
                if fetchCount == 2 { throw GoalSnapshotQueryFailure.unavailable }
                return try context.fetch(descriptor)
            })
        publishedValue = CalendarWidgetSnapshot.make(events: rows, referenceDate: reference)
        snapshotAssignments += 1
        Issue.record("Candidate-version query failure must reach the publisher before a new snapshot is assigned")
    } catch GoalSnapshotQueryFailure.unavailable {}
    #expect(fetchCount == 2)
    #expect(snapshotAssignments == 0)
    #expect(publishedValue == previous)
    let rows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    publishedValue = CalendarWidgetSnapshot.make(events: rows, referenceDate: reference)
    #expect(publishedValue.events.isEmpty)
    #expect(publishedValue.totalEventCount(onDayKey: "2026-08-06") == 0)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 2)
    #expect(!context.hasChanges)
}
