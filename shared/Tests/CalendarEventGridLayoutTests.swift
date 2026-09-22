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

private func wrappingItem(_ title: String, _ start: String, _ end: String? = nil) -> CalendarEventGridLayoutItem {
    CalendarEventGridLayoutItem(renderID: UUID(), eventID: UUID(), title: title,
                                startDayKey: start, endDayKey: end ?? start)
}

@Test
func calendarTwoLineTitlesUseSpareSpaceWithoutHidingEvents() throws {
    let month = try #require(DayKey.date(from: "2026-09-01"))
    let items = [wrappingItem("가 긴 제목", "2026-09-09"), wrappingItem("나 짧음", "2026-09-09")]
    for capacity in 1...4 {
        let baseline = CalendarEventGridLayout.make(items: items, dates: DayKey.monthGridDates(for: month),
                                                    visibleMonth: month, maximumLanes: capacity)
        let expanded = CalendarEventGridLayout.make(items: items, dates: DayKey.monthGridDates(for: month),
                                                    visibleMonth: month, maximumLanes: capacity,
                                                    expandedTitleRenderIDs: [items[0].renderID])
        #expect(expanded.displayedEventIDsByDayKey == baseline.displayedEventIDsByDayKey)
        #expect(expanded.hiddenEventCountByDayKey == baseline.hiddenEventCountByDayKey)
        #expect(expanded.segments.first?.laneSpan == (capacity >= 3 ? 2 : 1))
        if capacity >= 3 {
            #expect(expanded.segments.last?.lane == 2)
            #expect(expanded.segments.last?.laneSpan == 1)
        }
    }
}

@Test
func calendarTwoLineTitlesKeepCrossWeekAndCrossMonthBarsSingleLine() throws {
    let month = try #require(DayKey.date(from: "2026-09-01"))
    let acrossWeek = wrappingItem("주 경계", "2026-09-05", "2026-09-06")
    let acrossMonth = wrappingItem("월 경계", "2026-08-31", "2026-09-02")
    let oneDay = wrappingItem("하루 일정", "2026-09-06")
    let items = [acrossWeek, acrossMonth, oneDay]
    let result = CalendarEventGridLayout.make(items: items, dates: DayKey.monthGridDates(for: month),
                                             visibleMonth: month, maximumLanes: 4,
                                             expandedTitleRenderIDs: Set(items.map(\.renderID)))
    #expect(result.segments.filter { $0.eventID == acrossWeek.eventID }.allSatisfy { $0.span == 1 && $0.laneSpan == 1 })
    #expect(result.segments.filter { $0.eventID == acrossMonth.eventID }.allSatisfy { $0.laneSpan == 1 })
    #expect(result.segments.first { $0.eventID == oneDay.eventID }?.laneSpan == 2)
}

@Test
func calendarTwoLineTitlesPreserveOverflowAndDefaultWidgetLayout() throws {
    let month = try #require(DayKey.date(from: "2026-09-01"))
    let item = wrappingItem("더 긴 제목", "2026-09-09")
    let dates = DayKey.monthGridDates(for: month)
    let defaultLayout = CalendarEventGridLayout.make(items: [item], dates: dates, visibleMonth: month, maximumLanes: 4)
    #expect(defaultLayout.segments.first?.laneSpan == 1)
    let overflow = CalendarEventGridLayout.make(items: [item], dates: dates, visibleMonth: month,
                                               maximumLanes: 4, totalEventCountsByDayKey: ["2026-09-09": 3],
                                               expandedTitleRenderIDs: [item.renderID])
    #expect(overflow.segments.first?.laneSpan == 1)
    #expect(overflow.hiddenEventCountByDayKey["2026-09-09"] == 2)
}

@Test
func calendarTwoLineTitlesNeverOverlapOrChangeVisibleEvents() throws {
    let month = try #require(DayKey.date(from: "2026-09-01"))
    let dates = DayKey.monthGridDates(for: month)
    let items = [wrappingItem("여러 날 A", "2026-09-07", "2026-09-10"),
                 wrappingItem("여러 날 B", "2026-09-09", "2026-09-14")]
        + (7...14).flatMap { day in
            (0..<(day % 4 + 1)).map { wrappingItem("제목 \($0)", "2026-09-\(String(format: "%02d", day))") }
        }
    for capacity in 0...5 {
        let baseline = CalendarEventGridLayout.make(items: items, dates: dates, visibleMonth: month, maximumLanes: capacity)
        let expanded = CalendarEventGridLayout.make(items: items.reversed(), dates: dates, visibleMonth: month,
                                                    maximumLanes: capacity, expandedTitleRenderIDs: Set(items.map(\.renderID)))
        #expect(expanded.displayedEventIDsByDayKey == baseline.displayedEventIDsByDayKey)
        #expect(expanded.hiddenEventCountByDayKey == baseline.hiddenEventCountByDayKey)
        var occupied = Set<String>()
        for segment in expanded.segments {
            #expect(segment.lane + segment.laneSpan <= capacity)
            for column in segment.startColumn..<(segment.startColumn + segment.span) {
                for lane in segment.lane..<(segment.lane + segment.laneSpan) {
                    #expect(occupied.insert("\(segment.weekIndex)/\(column)/\(lane)").inserted)
                }
            }
        }
        for original in baseline.segments where items.prefix(2).contains(where: { $0.renderID == original.renderID }) {
            #expect(expanded.segments.first { $0.id == original.id } == original)
        }
    }
}
