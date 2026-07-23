import Foundation
import Testing
@testable import EasyTaskCore

@Test
func adaptiveMonthGridUsesFiveOrSixWeeks() throws {
    let fiveWeekMonth = try #require(DayKey.date(from: "2026-07-01"))
    let sixWeekMonth = try #require(DayKey.date(from: "2026-08-01"))

    let fiveWeekDates = DayKey.adaptiveMonthGridDates(for: fiveWeekMonth)
    let sixWeekDates = DayKey.adaptiveMonthGridDates(for: sixWeekMonth)

    #expect(fiveWeekDates.count == 35)
    #expect(sixWeekDates.count == 42)
    #expect(DayKey.key(for: fiveWeekDates.first!) == "2026-06-28")
    #expect(DayKey.key(for: sixWeekDates.last!) == "2026-09-05")
}

@Test
func calendarEventGridLayoutSplitsAcrossWeeksAndReusesLanes() throws {
    let month = try #require(DayKey.date(from: "2026-08-01"))
    let dates = DayKey.adaptiveMonthGridDates(for: month)
    let longEvent = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: UUID(),
        title: "출장",
        startDayKey: "2026-08-06",
        endDayKey: "2026-08-10"
    )
    let laterEvent = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: UUID(),
        title: "회의",
        startDayKey: "2026-08-11",
        endDayKey: "2026-08-11"
    )

    let result = CalendarEventGridLayout.make(
        items: [laterEvent, longEvent],
        dates: dates,
        visibleMonth: month,
        maximumLanes: 2
    )

    let longSegments = result.segments.filter { $0.eventID == longEvent.eventID }
    #expect(longSegments.count == 2)
    #expect(longSegments.map(\.weekIndex) == [1, 2])
    #expect(longSegments.map(\.span) == [3, 2])
    #expect(result.segments.first { $0.eventID == laterEvent.eventID }?.lane == 0)
}

@Test
func calendarEventGridLayoutReportsUniqueHiddenCounts() throws {
    let month = try #require(DayKey.date(from: "2026-07-01"))
    let dates = DayKey.adaptiveMonthGridDates(for: month)
    let dayKey = "2026-07-16"
    let items = (0..<4).map { index in
        CalendarEventGridLayoutItem(
            renderID: UUID(),
            eventID: UUID(),
            title: "이벤트 \(index)",
            startDayKey: dayKey,
            endDayKey: dayKey
        )
    }

    let result = CalendarEventGridLayout.make(
        items: items,
        dates: dates,
        visibleMonth: month,
        maximumLanes: 3,
        totalEventCountsByDayKey: [dayKey: 6]
    )

    #expect(result.displayedEventIDsByDayKey[dayKey]?.count == 3)
    #expect(result.hiddenEventCountByDayKey[dayKey] == 3)
}

@Test
func calendarEventGridLayoutUsesStableOrdering() throws {
    let month = try #require(DayKey.date(from: "2026-07-01"))
    let dates = DayKey.adaptiveMonthGridDates(for: month)
    let first = CalendarEventGridLayoutItem(
        renderID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        eventID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        title: "가",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16"
    )
    let second = CalendarEventGridLayoutItem(
        renderID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        eventID: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        title: "나",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16"
    )

    let forward = CalendarEventGridLayout.make(
        items: [first, second],
        dates: dates,
        visibleMonth: month,
        maximumLanes: 2
    )
    let reversed = CalendarEventGridLayout.make(
        items: [second, first],
        dates: dates,
        visibleMonth: month,
        maximumLanes: 2
    )

    #expect(forward.segments == reversed.segments)
    #expect(forward.hiddenEventCountByDayKey == reversed.hiddenEventCountByDayKey)
}

@Test
func calendarEventGridLayoutRejectsInvalidRangesAndCountsLogicalDuplicatesOnce() throws {
    let month = try #require(DayKey.date(from: "2026-07-01"))
    let dates = DayKey.adaptiveMonthGridDates(for: month)
    let eventID = UUID()
    let newerUpdatedAt = try #require(DayKey.date(from: "2026-07-16"))
    let olderUpdatedAt = try #require(DayKey.date(from: "2026-07-15"))
    let valid = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: eventID,
        title: "원본",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16",
        updatedAt: newerUpdatedAt
    )
    let duplicate = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: eventID,
        title: "수렴 전 중복",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16",
        updatedAt: olderUpdatedAt
    )
    let malformed = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: UUID(),
        title: "잘못된 날짜",
        startDayKey: "2026-02-31",
        endDayKey: "2026-07-16"
    )
    let reversed = CalendarEventGridLayoutItem(
        renderID: UUID(),
        eventID: UUID(),
        title: "역전 범위",
        startDayKey: "2026-07-17",
        endDayKey: "2026-07-16"
    )

    let result = CalendarEventGridLayout.make(
        items: [malformed, reversed, duplicate, valid],
        dates: dates,
        visibleMonth: month,
        maximumLanes: 3
    )

    #expect(result.segments.count == 1)
    #expect(result.segments.first?.renderID == valid.renderID)
    #expect(result.displayedEventIDsByDayKey["2026-07-16"] == [eventID])
    #expect(result.hiddenEventCountByDayKey["2026-07-16"] == nil)
}

@Test
func calendarEventGridLayoutBreaksEqualTimestampDuplicatesByRenderID() throws {
    let eventID = UUID()
    let updatedAt = try #require(DayKey.date(from: "2026-07-16"))
    let lowerRenderID = try #require(UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    ))
    let higherRenderID = try #require(UUID(
        uuidString: "00000000-0000-0000-0000-000000000002"
    ))
    let lower = CalendarEventGridLayoutItem(
        renderID: lowerRenderID,
        eventID: eventID,
        title: "낮은 instanceID",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16",
        updatedAt: updatedAt
    )
    let higher = CalendarEventGridLayoutItem(
        renderID: higherRenderID,
        eventID: eventID,
        title: "높은 instanceID",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-16",
        updatedAt: updatedAt
    )

    let representatives = CalendarEventGridLayout.representativeItems(
        from: [higher, lower]
    )

    #expect(representatives.count == 1)
    #expect(representatives.first?.renderID == higherRenderID)
}
