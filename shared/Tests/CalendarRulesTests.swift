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
func calendarEventReuseBuildsSingleAndCrossMonthDrafts() throws {
    let singleDay = try #require(DayKey.date(from: "2026-07-25"))
    let crossMonthStart = try #require(DayKey.date(from: "2026-01-30"))
    let crossMonthEnd = try #require(DayKey.date(from: "2026-02-02"))
    let target = try #require(DayKey.date(from: "2026-02-27"))
    let single = CalendarEvent(
        title: "하루 공장",
        startAt: singleDay,
        endAt: singleDay,
        note: "설비 점검",
        color: CalendarEventColor.red.rawValue
    )
    let crossMonth = CalendarEvent(
        title: "월 경계 공장",
        startAt: crossMonthStart,
        endAt: crossMonthEnd,
        note: "4일 일정",
        color: CalendarEventColor.blue.rawValue
    )

    let singleDraft = CalendarEventReuseRules.duplicateDraft(
        from: single,
        targetStartAt: target
    )
    let crossMonthDraft = CalendarEventReuseRules.duplicateDraft(
        from: crossMonth,
        targetStartAt: target
    )

    #expect(singleDraft.includedDayCount == 1)
    #expect(singleDraft.startAt == singleDraft.endAt)
    #expect(crossMonthDraft.title == "월 경계 공장")
    #expect(crossMonthDraft.note == "4일 일정")
    #expect(crossMonthDraft.color == CalendarEventColor.blue.rawValue)
    #expect(crossMonthDraft.sourceEventID == crossMonth.id)
    #expect(crossMonthDraft.includedDayCount == 4)
    #expect(DayKey.key(for: crossMonthDraft.startAt) == "2026-02-27")
    #expect(DayKey.key(for: crossMonthDraft.endAt) == "2026-03-02")
}

@Test
func calendarEventReusePreservesDayCountAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let sourceStart = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 3,
        day: 7
    )))
    let sourceEnd = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 3,
        day: 9
    )))
    let targetStart = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 10,
        day: 31
    )))
    let source = CalendarEvent(
        title: "DST 경계 일정",
        startAt: sourceStart,
        endAt: sourceEnd
    )

    let draft = CalendarEventReuseRules.duplicateDraft(
        from: source,
        targetStartAt: targetStart,
        calendar: calendar
    )

    #expect(CalendarEventReuseRules.includedDayCount(
        from: sourceStart,
        through: sourceEnd,
        calendar: calendar
    ) == 3)
    #expect(CalendarEventReuseRules.includedDayCount(
        from: draft.startAt,
        through: draft.endAt,
        calendar: calendar
    ) == 3)
    #expect(DayKey.key(for: draft.startAt, calendar: calendar) == "2026-10-31")
    #expect(DayKey.key(for: draft.endAt, calendar: calendar) == "2026-11-02")
}

@Test
func calendarEventReuseMakesIndependentIdentifiersAndKeepsTaskLinkOnSource() throws {
    let day = try #require(DayKey.date(from: "2026-07-25"))
    let target = try #require(DayKey.date(from: "2026-08-03"))
    let now = Date(timeIntervalSince1970: 1_000)
    let source = CalendarEvent(
        title: "공장",
        startAt: day,
        endAt: DayKey.addingDays(2, to: day),
        note: "원본 메모",
        color: CalendarEventColor.red.rawValue
    )
    let linkedTask = Task(
        title: "원본 연결 작업",
        plannedAt: day,
        order: 100,
        eventId: source.id
    )
    let draft = CalendarEventReuseRules.duplicateDraft(
        from: source,
        targetStartAt: target
    )
    let duplicate = try #require(
        CalendarEventReuseRules.makeIndependentEvent(
            from: draft,
            now: now
        )
    )

    #expect(duplicate.id != source.id)
    #expect(duplicate.instanceID != source.instanceID)
    #expect(duplicate.title == source.title)
    #expect(duplicate.note == source.note)
    #expect(duplicate.color == source.color)
    #expect(duplicate.createdAt == now)
    #expect(duplicate.updatedAt == now)
    #expect(linkedTask.eventId == source.id)
    #expect(linkedTask.eventId != duplicate.id)
}

@Test
func calendarEventRecommendationsPrioritizeExactThenRecentPrefixMatches() throws {
    let day = try #require(DayKey.date(from: "2026-07-25"))
    let exact = CalendarEvent(
        title: "Factory",
        startAt: day,
        endAt: day,
        color: CalendarEventColor.blue.rawValue,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let newerPrefix = CalendarEvent(
        title: "Factory audit",
        startAt: day,
        endAt: DayKey.addingDays(1, to: day),
        note: "점검",
        color: CalendarEventColor.red.rawValue,
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    let olderPrefix = CalendarEvent(
        title: "FACTORY setup",
        startAt: day,
        endAt: DayKey.addingDays(2, to: day),
        color: CalendarEventColor.green.rawValue,
        updatedAt: Date(timeIntervalSince1970: 200)
    )

    let recommendations = CalendarEventReuseRules.recommendations(
        for: "  fAcToRy  ",
        from: [newerPrefix, olderPrefix, exact]
    )

    #expect(recommendations.map(\.title) == [
        "Factory",
        "Factory audit",
        "FACTORY setup"
    ])
    #expect(recommendations[1].summary == "Factory audit · 2일 · 빨강 · 메모 있음")
}

@Test
func calendarEventRecommendationsConvergeLogicalAndSettingsDuplicates() throws {
    let transientDuplicates = try EventReuseTaskHistoryFixtures.transientDuplicateEvents()
    let day = try #require(DayKey.date(from: "2026-07-20"))
    let sameSettings = CalendarEvent(
        title: "공장 최신 중복",
        startAt: day,
        endAt: DayKey.addingDays(1, to: day),
        note: "최신",
        color: CalendarEventColor.red.rawValue,
        updatedAt: Date(timeIntervalSince1970: 150)
    )
    let superseded = CalendarEvent(
        title: "공장 폐기",
        startAt: day,
        endAt: day,
        updatedAt: Date(timeIntervalSince1970: 400),
        supersededAt: Date(timeIntervalSince1970: 500)
    )

    let recommendations = CalendarEventReuseRules.recommendations(
        for: "공",
        from: transientDuplicates + [sameSettings, superseded]
    )

    #expect(recommendations.count == 1)
    #expect(recommendations.first?.title == "공장 최신 중복")
    #expect(recommendations.first?.instanceID == transientDuplicates[1].instanceID)
}

@Test
func calendarEventRecommendationsLimitExcludeAndApplyOnlyReusableSettings() throws {
    let day = try #require(DayKey.date(from: "2026-07-25"))
    let events = (0..<7).map { index in
        CalendarEvent(
            title: "공장 \(index)",
            startAt: day,
            endAt: DayKey.addingDays(index, to: day),
            note: index.isMultiple(of: 2) ? "메모 \(index)" : nil,
            color: CalendarEventColor.allCases[
                index % CalendarEventColor.allCases.count
            ].rawValue,
            updatedAt: Date(timeIntervalSince1970: Double(100 + index))
        )
    }

    let recommendations = CalendarEventReuseRules.recommendations(
        for: "공장",
        from: events,
        excludingEventID: events[6].id
    )
    let inputStart = try #require(DayKey.date(from: "2026-08-10"))
    let currentDraft = CalendarEventReuseDraft(
        title: "공장 새 입력",
        startAt: inputStart,
        endAt: inputStart,
        note: "사용자 메모",
        color: CalendarEventColor.teal.rawValue,
        sourceEventID: events[6].id
    )
    let applied = CalendarEventReuseRules.applying(
        try #require(recommendations.first),
        to: currentDraft
    )

    #expect(recommendations.count == CalendarEventReuseRules.recommendationLimit)
    #expect(!recommendations.contains { $0.eventID == events[6].id })
    #expect(applied.title == currentDraft.title)
    #expect(applied.startAt == currentDraft.startAt)
    #expect(applied.includedDayCount == recommendations[0].includedDayCount)
    #expect(applied.note == recommendations[0].note)
    #expect(applied.color == recommendations[0].color)
    #expect(applied.sourceEventID == currentDraft.sourceEventID)
    #expect(CalendarEventReuseRules.recommendations(
        for: "   ",
        from: events
    ).isEmpty)
}

@Test
@MainActor
func calendarEventRecommendationSessionCancelsOlderTitleQuery() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-25"))
    context.insert(CalendarEvent(
        title: "이전 제목",
        startAt: day,
        endAt: day,
        updatedAt: Date(timeIntervalSince1970: 100)
    ))
    context.insert(CalendarEvent(
        title: "최신 제목",
        startAt: day,
        endAt: day,
        updatedAt: Date(timeIntervalSince1970: 200)
    ))
    try context.save()

    let session = CalendarEventRecommendationSession(context: context)
    session.update(title: "이전", debounce: .milliseconds(20))
    session.update(title: "최신", debounce: .milliseconds(20))
    for _ in 0..<100 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(20))
    }

    #expect(!session.isLoading)
    #expect(session.recommendations.map(\.title) == ["최신 제목"])
    session.dismissRecommendations()
    #expect(session.recommendations.isEmpty)
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
