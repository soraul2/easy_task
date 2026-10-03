import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Follow-up correctness repro only: snapshot production is not changed by C2.
// The ordinary tests below express representative-before-visibility semantics;
// the starting builders are expected to revive old rows in the first five.
// Fixtures and snapshot values are local/memory-only; no App Group file is read.
private func goalSnapshotRepresentativeID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func goalSnapshotRepresentativeEvent(
    logicalID: Int = 1, physicalID: Int, key: String = "2026-08-06",
    title: String = "기존 일정", updatedAt: Double, superseded: Bool = false
) throws -> CalendarEvent {
    let date = try #require(DayKey.date(from: key))
    return CalendarEvent(
        id: goalSnapshotRepresentativeID(logicalID), instanceID: goalSnapshotRepresentativeID(physicalID),
        title: title, startAt: date, endAt: date,
        createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: updatedAt),
        supersededAt: superseded ? Date(timeIntervalSince1970: 100) : nil)
}

@MainActor
private struct GoalSnapshotRepresentativeFixture {
    let container: ModelContainer
    let events: [CalendarEvent]
    let referenceDate: Date

    init(events: [CalendarEvent]) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        self.events = events
        referenceDate = try #require(DayKey.date(from: "2026-08-06"))
        for event in events { container.mainContext.insert(event) }
        try container.mainContext.save()
    }

    var calendar: CalendarWidgetSnapshot {
        CalendarWidgetSnapshot.make(events: events, tasks: [], referenceDate: referenceDate)
    }

    var lockScreen: LockScreenWidgetDaySummary? {
        LockScreenWidgetRules.makeDaySummaries(tasks: [], events: events, referenceDate: referenceDate).first
    }

    var watch: WatchWidgetSnapshot {
        WatchWidgetSnapshot.make(tasks: [], events: events, referenceDate: referenceDate)
    }
}

@Test @MainActor
func goalCalendarSnapshotDoesNotReviveOlderIntervalOutsideCoverageLatest() throws {
    let fixture = try GoalSnapshotRepresentativeFixture(events: [
        goalSnapshotRepresentativeEvent(physicalID: 101, updatedAt: 10),
        goalSnapshotRepresentativeEvent(physicalID: 102, key: "2026-11-10", updatedAt: 20)
    ])
    #expect(fixture.calendar.events.isEmpty)
    #expect(fixture.calendar.totalEventCount(onDayKey: "2026-08-06") == 0)
}

@Test @MainActor
func goalCalendarLockScreenAndWatchDoNotReviveOlderIntervalOutsideDayCoverageLatest() throws {
    let fixture = try GoalSnapshotRepresentativeFixture(events: [
        goalSnapshotRepresentativeEvent(physicalID: 101, updatedAt: 10),
        goalSnapshotRepresentativeEvent(physicalID: 102, key: "2026-08-19", updatedAt: 20)
    ])
    #expect(fixture.lockScreen?.eventCount == 0)
    #expect(fixture.lockScreen?.focusTitle == nil)
    #expect(fixture.watch.eventCount == 0)
    #expect(fixture.watch.focusTitle == nil)
    // A valid latest version remains in the calendar's wider coverage.
    #expect(fixture.calendar.events.map(\.renderID) == [goalSnapshotRepresentativeID(102)])
}

@Test @MainActor
func goalCalendarSnapshotsDoNotReviveOlderTitleWhenLatestIsBlank() throws {
    let fixture = try GoalSnapshotRepresentativeFixture(events: [
        goalSnapshotRepresentativeEvent(physicalID: 102, updatedAt: 10),
        goalSnapshotRepresentativeEvent(physicalID: 101, title: " \n\t ", updatedAt: 20)
    ])
    #expect(fixture.calendar.events.isEmpty)
    #expect(fixture.calendar.totalEventCount(onDayKey: "2026-08-06") == 0)
    #expect(fixture.lockScreen?.eventCount == 0)
    #expect(fixture.watch.eventCount == 0)
}

@Test @MainActor
func goalCalendarSnapshotsSelectTimestampTieBeforeTitleValidityInEitherOrder() throws {
    let older = try goalSnapshotRepresentativeEvent(physicalID: 101, updatedAt: 20)
    let latest = try goalSnapshotRepresentativeEvent(physicalID: 102, title: " ", updatedAt: 20)
    let fixture = try GoalSnapshotRepresentativeFixture(events: [older, latest])
    for events in [fixture.events, Array(fixture.events.reversed())] {
        let calendar = CalendarWidgetSnapshot.make(events: events, referenceDate: fixture.referenceDate)
        let lockScreen = LockScreenWidgetRules.makeDaySummaries(tasks: [], events: events, referenceDate: fixture.referenceDate)
        let watch = WatchWidgetSnapshot.make(tasks: [], events: events, referenceDate: fixture.referenceDate)
        #expect(calendar.events.isEmpty)
        #expect(lockScreen.first?.eventCount == 0)
        #expect(watch.eventCount == 0)
    }
}

@Test @MainActor
func goalCalendarSnapshotsDoNotReviveOlderRangeWhenLatestDayKeyIsInvalid() throws {
    let older = try goalSnapshotRepresentativeEvent(physicalID: 101, updatedAt: 10)
    let latest = try goalSnapshotRepresentativeEvent(physicalID: 102, updatedAt: 20)
    // Corrupt only synthetic model keys; no deployed schema or store is changed.
    latest.startDayKey = "2026-02-30"
    let fixture = try GoalSnapshotRepresentativeFixture(events: [older, latest])
    #expect(fixture.calendar.events.isEmpty)
    #expect(fixture.calendar.totalEventCount(onDayKey: "2026-08-06") == 0)
    #expect(fixture.lockScreen?.eventCount == 0)
    #expect(fixture.watch.eventCount == 0)
}

@Test @MainActor
func goalCalendarSnapshotsIgnoreSupersededLatestAndKeepActiveOlderRepresentative() throws {
    let fixture = try GoalSnapshotRepresentativeFixture(events: [
        goalSnapshotRepresentativeEvent(physicalID: 101, updatedAt: 10),
        goalSnapshotRepresentativeEvent(physicalID: 102, title: " ", updatedAt: 20, superseded: true)
    ])
    #expect(fixture.calendar.events.map(\.renderID) == [goalSnapshotRepresentativeID(101)])
    #expect(fixture.calendar.totalEventCount(onDayKey: "2026-08-06") == 1)
    #expect(fixture.lockScreen?.eventCount == 1)
    #expect(fixture.watch.eventCount == 1)
}

@Test @MainActor
func goalCalendarSnapshotsPreserveDifferentLogicalIDsWithSameTitleAndUncappedCount() throws {
    let fixture = try GoalSnapshotRepresentativeFixture(events: [
        goalSnapshotRepresentativeEvent(logicalID: 1, physicalID: 101, updatedAt: 10),
        goalSnapshotRepresentativeEvent(logicalID: 2, physicalID: 201, updatedAt: 10)
    ])
    let capped = CalendarWidgetSnapshot.make(events: fixture.events, referenceDate: fixture.referenceDate, maximumEventCount: 1)
    #expect(capped.events.count == 1)
    #expect(capped.totalEventCount(onDayKey: "2026-08-06") == 2)
    #expect(fixture.lockScreen?.eventCount == 2)
    #expect(fixture.watch.eventCount == 2)
}
