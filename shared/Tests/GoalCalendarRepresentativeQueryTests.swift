import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum GoalCalendarQueryTestFailure: Error, Equatable { case unavailable }

private func goalCalendarQueryID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func goalCalendarQueryEvent(
    logicalID: Int = 1, physicalID: Int, start: String = "2026-08-06",
    title: String = "공장 점검", updatedAt: Double, supersededAt: Double? = nil
) throws -> CalendarEvent {
    let date = try #require(DayKey.date(from: start))
    return CalendarEvent(id: goalCalendarQueryID(logicalID), instanceID: goalCalendarQueryID(physicalID),
        title: title, startAt: date, endAt: date, createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        supersededAt: supersededAt.map { Date(timeIntervalSince1970: $0) })
}

@MainActor
private func goalCalendarQueryContainer(_ events: [CalendarEvent]) throws -> ModelContainer {
    let container = try PlanBaseContainerFactory.makeInMemory()
    for event in events { container.mainContext.insert(event) }
    try container.mainContext.save()
    return container
}

@Test @MainActor
func goalCalendarRangeRulesChooseRepresentativeBeforeFiltering() throws {
    let older = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 10)
    let latest = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    let container = try goalCalendarQueryContainer([older, latest])
    let allVersions = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())
    let first = try #require(DayKey.date(from: "2026-08-01"))
    let last = try #require(DayKey.date(from: "2026-08-31"))
    #expect(CalendarEventRules.events(overlapping: first, through: last, in: allVersions).isEmpty)
    #expect(CalendarEventRules.events(overlapping: last, through: first, in: allVersions).isEmpty)
}

@Test @MainActor
func goalCalendarReaderCompletesVersionsOutsideDayAndMonthRanges() throws {
    let older = try goalCalendarQueryEvent(physicalID: 102, updatedAt: 10)
    let latest = try goalCalendarQueryEvent(physicalID: 101, start: "2026-09-10", updatedAt: 20)
    let unrelated = try goalCalendarQueryEvent(logicalID: 2, physicalID: 201, start: "2026-10-01", updatedAt: 30)
    let container = try goalCalendarQueryContainer([older, latest, unrelated])
    let context = container.mainContext
    for bounds in [("2026-08-06", "2026-08-06"), ("2026-07-26", "2026-09-05")]
    {
        let seeds = try context.fetch(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: bounds.0, endDayKey: bounds.1))
        #expect(seeds.map(\.instanceID) == [older.instanceID])
        #expect(try BoundedQueryService.events(
            overlappingStartDayKey: bounds.0, endDayKey: bounds.1, in: context).isEmpty)
    }
    #expect(older.supersededAt == nil)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 3)
    #expect(!context.hasChanges)
}

@Test @MainActor
func goalCalendarReaderUsesPhysicalIDTieEvenWhenWinnerMovedOutsideRange() throws {
    let lower = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 20)
    let higher = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    let container = try goalCalendarQueryContainer([higher, lower])
    #expect(try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: container.mainContext).isEmpty)
}

@Test @MainActor
func goalCalendarReaderPreservesDistinctLogicalTitlesAndIgnoresSupersededWinner() throws {
    let active = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 10)
    let superseded = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 100, supersededAt: 200)
    let separate = try goalCalendarQueryEvent(logicalID: 2, physicalID: 201, updatedAt: 20)
    let container = try goalCalendarQueryContainer([superseded, separate, active])
    let rows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: container.mainContext)
    #expect(Set(rows.map(\.instanceID)) == Set([active.instanceID, separate.instanceID]))
}

@Test @MainActor
func goalCalendarReaderCompletesEveryIDBatchWithoutCappingVersionRows() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    for index in 1...401 {
        let older = try goalCalendarQueryEvent(logicalID: index, physicalID: index + 1_000, updatedAt: 10)
        let latest = try goalCalendarQueryEvent(logicalID: index, physicalID: index + 2_000,
            start: "2026-09-10", updatedAt: 20)
        context.insert(older)
        context.insert(latest)
    }
    try context.save()
    var fetchedRowCounts: [Int] = []
    let rows = try BoundedQueryService.representativeCalendarEvents(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", fetch: { descriptor in
            let fetched = try context.fetch(descriptor)
            fetchedRowCounts.append(fetched.count)
            return fetched
        })
    #expect(rows.isEmpty)
    #expect(fetchedRowCounts == [401, 400, 400, 2])
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 802)
}

@Test @MainActor
func goalCalendarReaderDoesNotFetchVersionsWhenNoSeedIDsOverlap() throws {
    let unrelated = try goalCalendarQueryEvent(physicalID: 101, start: "2026-09-10", updatedAt: 20)
    let container = try goalCalendarQueryContainer([unrelated])
    var fetchCount = 0
    let rows = try BoundedQueryService.representativeCalendarEvents(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", fetch: { descriptor in
            fetchCount += 1
            return try container.mainContext.fetch(descriptor)
        })
    #expect(rows.isEmpty)
    #expect(fetchCount == 1)
}

@Test @MainActor
func goalCalendarReaderIncludesPendingMovedVersionWithoutSavingOrDiscardingIt() throws {
    let older = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 10)
    let container = try goalCalendarQueryContainer([older])
    let context = container.mainContext
    let pending = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    context.insert(pending)
    #expect(context.hasChanges)
    #expect(try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context).isEmpty)
    #expect(context.hasChanges)
    context.rollback()
    let restored = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    #expect(restored.map(\.instanceID) == [older.instanceID])
}

@Test @MainActor
func goalCalendarReaderFailurePreservesPreviousRowsAndRetryReadsMovedVersion() throws {
    let older = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 10)
    let container = try goalCalendarQueryContainer([older])
    let context = container.mainContext
    var visibleRows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    let latest = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    context.insert(latest)
    try context.save()

    var fetchCount = 0
    var failed = false
    do {
        visibleRows = try BoundedQueryService.representativeCalendarEvents(
            overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", fetch: { descriptor in
                fetchCount += 1
                if fetchCount == 2 { throw GoalCalendarQueryTestFailure.unavailable }
                return try context.fetch(descriptor)
            })
        Issue.record("Active-version query failure must reach the caller")
    } catch let error as GoalCalendarQueryTestFailure {
        failed = true
        #expect(error == .unavailable)
    }
    #expect(failed)
    #expect(visibleRows.map(\.instanceID) == [older.instanceID])
    visibleRows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    #expect(visibleRows.isEmpty)
}

@Test @MainActor
func goalCalendarReaderRefreshAfterDeferredImportNotificationSeesOutsideVersion() throws {
    let older = try goalCalendarQueryEvent(physicalID: 101, updatedAt: 10)
    let container = try goalCalendarQueryContainer([older])
    let context = container.mainContext
    let revision = PersistenceViewRevision(context: context, domains: .calendar)
    let originalRevision = revision.value
    var visibleRows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)

    // A separate local context models imported records. No CloudKit is opened.
    let importingContext = ModelContext(container)
    let latest = try goalCalendarQueryEvent(physicalID: 102, start: "2026-09-10", updatedAt: 20)
    importingContext.insert(latest)
    try importingContext.save()
    // Successful import reconciliation publishes this all-domain notification.
    // Hidden views retain their rows while their revision observer records it.
    try PersistenceCommandService.perform(in: context, invalidating: .all) {}
    #expect(revision.value > originalRevision)
    #expect(visibleRows.map(\.instanceID) == [older.instanceID])
    visibleRows = try BoundedQueryService.events(
        overlappingStartDayKey: "2026-08-06", endDayKey: "2026-08-06", in: context)
    #expect(visibleRows.isEmpty)
}
