import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func calendarEventTimelineBadgeText() throws {
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let tomorrow = DayKey.addingDays(1, to: today)
    let afterTwoDays = DayKey.addingDays(2, to: today)

    let activeEvent = CalendarEvent(title: "TodoApp MVP 설계", startAt: today, endAt: afterTwoDays)
    let futureEvent = CalendarEvent(title: "다음 릴리즈", startAt: tomorrow, endAt: afterTwoDays)
    let endingTodayEvent = CalendarEvent(title: "테스트 일정", startAt: DayKey.addingDays(-2, to: today), endAt: today)
    let singleDayEvent = CalendarEvent(title: "하루 일정", startAt: today, endAt: today)

    #expect(CalendarEventTimeline.badgeText(for: activeEvent, today: today) == "종료 D-2")
    #expect(CalendarEventTimeline.badgeText(for: futureEvent, today: today) == "시작 D-1")
    #expect(CalendarEventTimeline.badgeText(for: endingTodayEvent, today: today) == "오늘 종료")
    #expect(CalendarEventTimeline.badgeText(for: singleDayEvent, today: today) == "오늘")
}

@Test
func calendarEventRulesNormalizeDraftAndUpdateEvent() throws {
    let lateStart = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 18)))
    let earlyEnd = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 9)))
    let createdAt = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 8)))
    let updatedAt = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10)))

    let event = try #require(CalendarEventRules.makeEvent(
        title: "  릴리즈 준비  ",
        startAt: lateStart,
        endAt: earlyEnd,
        note: "  주요 일정  ",
        color: " blue ",
        now: createdAt
    ))
    let blankEvent = CalendarEventRules.makeEvent(
        title: "   ",
        startAt: earlyEnd,
        endAt: lateStart
    )
    let invalidColorEvent = try #require(CalendarEventRules.makeEvent(
        title: "잘못된 색상",
        startAt: earlyEnd,
        endAt: lateStart,
        color: "indigo"
    ))

    #expect(blankEvent == nil)
    #expect(event.title == "릴리즈 준비")
    #expect(event.startAt == DayKey.startOfDay(for: earlyEnd))
    #expect(event.endAt == DayKey.startOfDay(for: lateStart))
    #expect(event.startDayKey == "2026-07-07")
    #expect(event.endDayKey == "2026-07-09")
    #expect(event.note == "주요 일정")
    #expect(event.color == "blue")
    #expect(event.createdAt == createdAt)
    #expect(event.updatedAt == createdAt)
    #expect(invalidColorEvent.color == nil)

    let didUpdate = CalendarEventRules.update(
        event,
        title: "  일정 수정  ",
        startAt: earlyEnd,
        endAt: earlyEnd,
        note: "   ",
        color: "",
        now: updatedAt
    )

    #expect(didUpdate)
    #expect(event.title == "일정 수정")
    #expect(event.startDayKey == "2026-07-07")
    #expect(event.endDayKey == "2026-07-07")
    #expect(event.note == nil)
    #expect(event.color == nil)
    #expect(event.updatedAt == updatedAt)
}

@Test
func calendarEventRulesQueryEventsByDayAndRangeInStableOrder() throws {
    let july6 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let july8 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let july9 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))

    let longB = CalendarEvent(title: "B 장기", startAt: july6, endAt: july8)
    let longA = CalendarEvent(title: "A 장기", startAt: july6, endAt: july8)
    let short = CalendarEvent(title: "단기", startAt: july6, endAt: july6)
    let later = CalendarEvent(title: "후속", startAt: july7, endAt: july9)

    let dayEvents = CalendarEventRules.events(on: july6, in: [later, short, longB, longA])
    let rangeEvents = CalendarEventRules.events(
        overlapping: july8,
        through: july9,
        in: [later, short, longB, longA]
    )

    #expect(dayEvents.map(\.title) == ["A 장기", "B 장기", "단기"])
    #expect(rangeEvents.map(\.title) == ["A 장기", "B 장기", "후속"])
}

@Test
func calendarEventRulesDetachLinkedTasksWhenDeletingEvent() throws {
    let day = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 11)))
    let event = CalendarEvent(title: "연결 일정", startAt: day, endAt: day)
    let otherEventID = UUID()
    let linkedFirst = Task(title: "연결 작업 1", plannedAt: day, order: 100, eventId: event.id)
    let linkedSecond = Task(title: "연결 작업 2", plannedAt: day, order: 200, eventId: event.id)
    let unrelated = Task(title: "다른 일정 작업", plannedAt: day, order: 300, eventId: otherEventID)

    let detachedCount = CalendarEventRules.detachTasks(
        from: event,
        in: [unrelated, linkedFirst, linkedSecond],
        now: now
    )

    #expect(detachedCount == 2)
    #expect(linkedFirst.eventId == nil)
    #expect(linkedSecond.eventId == nil)
    #expect(linkedFirst.updatedAt == now)
    #expect(linkedSecond.updatedAt == now)
    #expect(unrelated.eventId == otherEventID)
}

@Test
func specialDayStoreLoadsBundledKoreanSpecialDays() {
    let store = SpecialDayStore.load()
    let liberationDay = store.days(on: "2026-08-15")
    let overlappingDay = store.days(on: "2028-10-03")

    #expect(liberationDay.contains { $0.name == "광복절" && $0.isPublicHoliday })
    #expect(overlappingDay.contains { $0.name == "개천절" })
    #expect(overlappingDay.contains { $0.name == "추석" })
}
