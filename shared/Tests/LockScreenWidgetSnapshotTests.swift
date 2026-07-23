import Foundation
import Testing
@testable import EasyTaskCore

@Test
func lockScreenWidgetSnapshotRoundTripsV4Summary() throws {
    let summary = LockScreenWidgetDaySummary(
        dayKey: "2026-07-16",
        todoCount: 2,
        doingCount: 1,
        doneCount: 3,
        eventCount: 4,
        focusTitle: "출시 준비",
        focusKind: .doingTask
    )
    let snapshot = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 100),
        events: [],
        lockScreenCoveredStartDayKey: "2026-07-16",
        lockScreenCoveredEndDayKey: "2026-07-23",
        lockScreenDaySummaries: [summary]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(
        CalendarWidgetSnapshot.self,
        from: encoder.encode(snapshot)
    )

    #expect(decoded.schemaVersion == 4)
    #expect(decoded.lockScreenSummary(onDayKey: "2026-07-16") == summary)
    #expect(decoded.hasLockScreenCoverage(dayKey: "2026-07-16"))
    #expect(!decoded.hasLockScreenCoverage(dayKey: "2026-07-17"))
}

@Test
func lockScreenWidgetSnapshotDecodesV3WithoutSummary() throws {
    let data = Data(
        #"{"schemaVersion":3,"generatedAt":"2026-07-16T00:00:00Z","themeID":"appleSystem","coveredStartDayKey":"2026-06-01","coveredEndDayKey":"2026-08-31","eventCountsByDayKey":{},"events":[]}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let snapshot = try decoder.decode(CalendarWidgetSnapshot.self, from: data)

    #expect(snapshot.schemaVersion == 3)
    #expect(snapshot.lockScreenCoveredStartDayKey == nil)
    #expect(snapshot.lockScreenCoveredEndDayKey == nil)
    #expect(snapshot.lockScreenDaySummaries == nil)
    #expect(!snapshot.hasLockScreenCoverage(dayKey: "2026-07-16"))
}

@Test
func lockScreenWidgetSummaryParticipatesInContentEquality() {
    let first = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 100),
        events: [],
        lockScreenCoveredStartDayKey: "2026-07-16",
        lockScreenCoveredEndDayKey: "2026-07-23",
        lockScreenDaySummaries: [LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 1,
            doingCount: 0,
            doneCount: 0,
            eventCount: 0
        )]
    )
    let sameContent = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 200),
        events: [],
        lockScreenCoveredStartDayKey: "2026-07-16",
        lockScreenCoveredEndDayKey: "2026-07-23",
        lockScreenDaySummaries: first.lockScreenDaySummaries
    )
    let changedCount = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 200),
        events: [],
        lockScreenCoveredStartDayKey: "2026-07-16",
        lockScreenCoveredEndDayKey: "2026-07-23",
        lockScreenDaySummaries: [LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 2,
            doingCount: 0,
            doneCount: 0,
            eventCount: 0
        )]
    )

    #expect(first.hasSameContent(as: sameContent))
    #expect(!first.hasSameContent(as: changedCount))
}

@Test
@MainActor
func calendarWidgetSnapshotMakeIncludesCompleteLockScreenCoverageWhenTasksProvided() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let task = Task(
        title: "오늘 작업",
        status: .todo,
        plannedAt: referenceDate,
        order: 0
    )

    let snapshot = CalendarWidgetSnapshot.make(
        events: [],
        tasks: [task],
        referenceDate: referenceDate
    )

    #expect(snapshot.lockScreenCoveredStartDayKey == "2026-07-16")
    #expect(snapshot.lockScreenCoveredEndDayKey == "2026-07-23")
    #expect(snapshot.lockScreenDaySummaries?.count == 8)
    #expect(snapshot.lockScreenSummary(onDayKey: "2026-07-16")?.todoCount == 1)
    #expect(snapshot.lockScreenSummary(onDayKey: "2026-07-23")?.hasContent == false)
}

@Test
func lockScreenTimelineEntriesStayInsideCoverageAndRefreshAfterLastEntry() throws {
    let now = try #require(DayKey.date(from: "2026-07-16"))
        .addingTimeInterval(12 * 60 * 60)
    let summaries = (0..<8).map { offset in
        LockScreenWidgetDaySummary(
            dayKey: DayKey.key(for: DayKey.addingDays(offset, to: now)),
            todoCount: 0,
            doingCount: 0,
            doneCount: 0,
            eventCount: 0
        )
    } + [LockScreenWidgetDaySummary(
        dayKey: "2026-07-24",
        todoCount: 1,
        doingCount: 0,
        doneCount: 0,
        eventCount: 0
    )]
    let snapshot = CalendarWidgetSnapshot(
        generatedAt: now,
        events: [],
        lockScreenCoveredStartDayKey: "2026-07-16",
        lockScreenCoveredEndDayKey: "2026-07-23",
        lockScreenDaySummaries: summaries
    )

    let dates = snapshot.lockScreenTimelineEntryDates(startingAt: now)
    let refreshDate = CalendarWidgetSnapshot.lockScreenTimelineRefreshDate(
        after: try #require(dates.last)
    )

    #expect(dates.count == 8)
    #expect(dates.first == now)
    #expect(DayKey.key(for: try #require(dates.last)) == "2026-07-23")
    #expect(DayKey.key(for: refreshDate) == "2026-07-24")
}
