import Foundation
import Testing
@testable import EasyTaskCore

// Synthetic model values only. No App Group, persistent store or global time-zone
// mutation is needed to compare the internal one-day and public eight-day APIs.
private func goalWatchTodayID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func goalWatchTodayTask(
    _ value: Int,
    logicalID: Int? = nil,
    title: String? = nil,
    status: TaskStatus = .todo,
    day: Date,
    order: Double = 0,
    updatedSeconds: TimeInterval = 0
) -> EasyTaskCore.Task {
    EasyTaskCore.Task(
        id: goalWatchTodayID(logicalID ?? value),
        instanceID: goalWatchTodayID(10_000 + value),
        title: title ?? "작업 \(value)",
        status: status,
        plannedAt: day,
        order: order,
        createdAt: DayKey.startOfDay(for: day),
        updatedAt: DayKey.startOfDay(for: day).addingTimeInterval(updatedSeconds)
    )
}

@MainActor
private func goalWatchTodayEvent(
    _ value: Int,
    logicalID: Int? = nil,
    title: String? = nil,
    start: Date,
    end: Date? = nil,
    updatedAt: Date? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: goalWatchTodayID(20_000 + (logicalID ?? value)),
        instanceID: goalWatchTodayID(30_000 + value),
        title: title ?? "일정 \(value)",
        startAt: start,
        endAt: end ?? start,
        createdAt: start,
        updatedAt: updatedAt ?? start
    )
}

@MainActor
@discardableResult
private func checkGoalWatchTodayProjection(
    tasks: [EasyTaskCore.Task],
    events: [CalendarEvent],
    at referenceDate: Date,
    activeFocus: FocusActiveSessionSnapshot? = nil
) throws -> LockScreenWidgetDaySummary {
    let summaries = LockScreenWidgetRules.makeDaySummaries(
        tasks: tasks, events: events, referenceDate: referenceDate
    )
    #expect(summaries.count == 8)
    #expect(summaries.map(\.dayKey) == (0..<8).map {
        DayKey.key(for: DayKey.addingDays($0, to: DayKey.startOfDay(for: referenceDate)))
    })
    let first = try #require(summaries.first)
    let actual = LockScreenWidgetRules.makeTodaySummary(
        tasks: tasks, events: events, referenceDate: referenceDate
    )
    #expect(actual == first)

    // Full constructor comparison includes Focus validity/title fallback and all
    // timer metadata, not just the visible task/event counts.
    let expectedWatch = WatchWidgetSnapshot(
        generatedAt: referenceDate,
        dayKey: DayKey.key(for: referenceDate),
        todoCount: first.todoCount,
        doingCount: first.doingCount,
        doneCount: first.doneCount,
        eventCount: first.eventCount,
        focusTitle: first.focusTitle,
        focusKind: first.focusKind,
        activeFocus: activeFocus
    )
    let actualWatch = WatchWidgetSnapshot.make(
        tasks: tasks, events: events, referenceDate: referenceDate, activeFocus: activeFocus
    )
    #expect(actualWatch == expectedWatch)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    #expect(try encoder.encode(actualWatch) == encoder.encode(expectedWatch))
    return actual
}

@Test @MainActor
func goalWatchTodayProjectionKeepsEightDayCoverageAndEmptyContract() throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let summary = try checkGoalWatchTodayProjection(tasks: [], events: [], at: date)
    #expect(summary.dayKey == "2026-10-02")
    #expect(summary.totalTaskCount == 0)
    #expect(summary.eventCount == 0)
    #expect(summary.focusTitle == nil)
    #expect(summary.focusKind == nil)
    let coverage = LockScreenWidgetRules.coverageDayKeys(for: date)
    #expect(coverage.startDayKey == "2026-10-02")
    #expect(coverage.endDayKey == "2026-10-09")
}

@Test @MainActor
func goalWatchTodayProjectionPreservesTaskPreparationAndPlannedDayPolicies() throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let tomorrow = DayKey.addingDays(1, to: date)
    let oldMoved = goalWatchTodayTask(1, logicalID: 1, status: .doing, day: date)
    let latestMoved = goalWatchTodayTask(2, logicalID: 1, title: "최신 미래", day: tomorrow)
    let oldArchived = goalWatchTodayTask(3, logicalID: 2, title: "활성 이전", day: date)
    let latestArchived = goalWatchTodayTask(4, logicalID: 2, status: .doing, day: date, updatedSeconds: 1)
    latestArchived.archivedAt = date
    let oldInvalid = goalWatchTodayTask(5, logicalID: 3, day: date)
    let latestInvalid = goalWatchTodayTask(6, logicalID: 3, day: date, updatedSeconds: 1)
    latestInvalid.status = "unknown-status"
    let oldSuperseded = goalWatchTodayTask(7, logicalID: 4, day: date)
    let latestSuperseded = goalWatchTodayTask(8, logicalID: 4, status: .doing, day: date, updatedSeconds: 1)
    latestSuperseded.supersededAt = date
    let blankDoing = goalWatchTodayTask(9, title: " \n ", status: .doing, day: date)
    let done = goalWatchTodayTask(10, status: .done, day: date)
    done.completedAt = DayKey.addingDays(-1, to: date)
    done.completedDayKey = DayKey.key(for: try #require(done.completedAt))
    let future = goalWatchTodayTask(11, status: .doing, day: tomorrow)
    let tasks = [oldMoved, latestMoved, oldArchived, latestArchived, oldInvalid, latestInvalid,
                 oldSuperseded, latestSuperseded, blankDoing, done, future]
    let event = goalWatchTodayEvent(1, title: "일정 fallback", start: date)
    let summary = try checkGoalWatchTodayProjection(tasks: tasks, events: [event], at: date)
    // Archive/status/superseded filtering occurs before Task representative
    // selection, preserving the existing policy instead of adopting event C3.
    #expect(summary.todoCount == 3)
    #expect(summary.doingCount == 1)
    #expect(summary.doneCount == 1)
    #expect(summary.eventCount == 1)
    #expect(summary.focusTitle == "일정 fallback")
    #expect(summary.focusKind == .event)
}

@Test @MainActor
func goalWatchTodayProjectionPreservesTaskTieSortAndBlankFallback() throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let blank = goalWatchTodayTask(1, title: "\t ", status: .doing, day: date, order: -2)
    let second = goalWatchTodayTask(2, title: "  Z 진행  ", status: .doing, day: date, order: 0)
    let first = goalWatchTodayTask(3, title: "  A 진행  ", status: .doing, day: date, order: 0)
    let todo = goalWatchTodayTask(4, title: "할 일", day: date, order: -10)
    let event = goalWatchTodayEvent(1, title: "일정", start: date)
    let summary = try checkGoalWatchTodayProjection(tasks: [blank, second, todo, first], events: [event], at: date)
    #expect(summary.doingCount == 3)
    #expect(summary.focusTitle == "A 진행")
    #expect(summary.focusKind == .doingTask)
    let noTitledDoing = try checkGoalWatchTodayProjection(tasks: [blank, todo], events: [], at: date)
    #expect(noTitledDoing.doingCount == 1)
    #expect(noTitledDoing.focusTitle == "할 일")
    #expect(noTitledDoing.focusKind == .todoTask)

    let old = goalWatchTodayTask(5, logicalID: 100, day: date, updatedSeconds: 1)
    let latest = goalWatchTodayTask(6, logicalID: 100, day: date, updatedSeconds: 1)
    latest.plannedAt = DayKey.addingDays(1, to: date)
    latest.plannedDayKey = DayKey.key(for: latest.plannedAt)
    for tasks in [[old, latest], [latest, old]] {
        let tied = try checkGoalWatchTodayProjection(tasks: tasks, events: [], at: date)
        #expect(tied.totalTaskCount == 0)
    }
}

@Test(arguments: ["future", "outside", "blank", "invalid-key", "inverted", "tie-blank", "superseded"])
@MainActor
func goalWatchTodayProjectionKeepsC3RepresentativeBeforeEventVisibility(scenario: String) throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let old = goalWatchTodayEvent(1, logicalID: 1, title: "이전 오늘", start: date, updatedAt: date)
    let latestDate = scenario == "future" ? DayKey.addingDays(1, to: date) :
        scenario == "outside" ? DayKey.addingDays(20, to: date) : date
    let latest = goalWatchTodayEvent(
        2, logicalID: 1, title: "최신", start: latestDate,
        updatedAt: scenario == "tie-blank" ? date : date.addingTimeInterval(1)
    )
    if scenario == "blank" || scenario == "tie-blank" { latest.title = " \n\t " }
    if scenario == "invalid-key" { latest.startDayKey = "2026-02-30" }
    if scenario == "inverted" { latest.endDayKey = DayKey.key(for: DayKey.addingDays(-1, to: date)) }
    if scenario == "superseded" { latest.supersededAt = date }
    for events in [[old, latest], [latest, old]] {
        let summary = try checkGoalWatchTodayProjection(tasks: [], events: events, at: date)
        if scenario == "superseded" {
            #expect(summary.eventCount == 1)
            #expect(summary.focusTitle == "이전 오늘")
            #expect(summary.focusKind == .event)
        } else {
            #expect(summary.eventCount == 0)
            #expect(summary.focusTitle == nil)
            #expect(summary.focusKind == nil)
        }
    }
}

@Test @MainActor
func goalWatchTodayProjectionPreservesEventOrderAndInclusivePeriod() throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let earlier = DayKey.addingDays(-1, to: date)
    let end = DayKey.addingDays(1, to: date)
    let span = goalWatchTodayEvent(1, title: "  기간 일정  ", start: earlier, end: end)
    let sameDay = goalWatchTodayEvent(2, title: "A 당일", start: date)
    for reference in [earlier, date, end] {
        let summary = try checkGoalWatchTodayProjection(tasks: [], events: [sameDay, span], at: reference)
        #expect(summary.eventCount == (reference == date ? 2 : 1))
        #expect(summary.focusTitle == "기간 일정")
        #expect(summary.focusKind == .event)
    }
    let after = try checkGoalWatchTodayProjection(tasks: [], events: [span, sameDay], at: DayKey.addingDays(1, to: end))
    #expect(after.eventCount == 0)
    #expect(after.focusTitle == nil)
}

@Test @MainActor
func goalWatchTodayProjectionChangesAtMidnightWithoutLosingFutureEightDayEntries() throws {
    let today = try #require(DayKey.date(from: "2026-10-31"))
    let tomorrow = DayKey.addingDays(1, to: today)
    let future = DayKey.addingDays(7, to: today)
    let tasks = [
        goalWatchTodayTask(1, title: "오늘 작업", day: today),
        goalWatchTodayTask(2, title: "내일 작업", day: tomorrow),
        goalWatchTodayTask(3, title: "8일째 작업", day: future)
    ]
    let event = goalWatchTodayEvent(1, title: "내일 일정", start: tomorrow)
    let before = try checkGoalWatchTodayProjection(tasks: tasks, events: [event], at: tomorrow.addingTimeInterval(-1))
    let after = try checkGoalWatchTodayProjection(tasks: tasks, events: [event], at: tomorrow)
    #expect(before.dayKey == "2026-10-31")
    #expect(before.focusTitle == "오늘 작업")
    #expect(after.dayKey == "2026-11-01")
    #expect(after.eventCount == 1)
    #expect(after.focusTitle == "내일 일정")
    let all = LockScreenWidgetRules.makeDaySummaries(tasks: tasks, events: [event], referenceDate: today)
    #expect(all[1].todoCount == 1)
    #expect(all[1].eventCount == 1)
    #expect(all[7].todoCount == 1)
    #expect(all[7].focusTitle == "8일째 작업")
}

@Test(arguments: ["2026-10-02T00:00:00Z", "2026-10-02T14:59:59Z", "2026-10-02T15:00:00Z", "2026-10-02T23:59:59Z"])
@MainActor
func goalWatchTodayProjectionUsesCurrentDayKeyForAbsoluteInstants(instant: String) throws {
    let reference = try #require(ISO8601DateFormatter().date(from: instant))
    let today = DayKey.startOfDay(for: reference)
    let task = goalWatchTodayTask(1, day: today)
    let event = goalWatchTodayEvent(1, start: today)
    let summary = try checkGoalWatchTodayProjection(tasks: [task], events: [event], at: reference)
    #expect(summary.dayKey == DayKey.key(for: reference, calendar: DayKey.calendar))
    #expect(summary.todoCount == 1)
    #expect(summary.eventCount == 1)
    // Use the actual current calendar without changing global process defaults.
    #expect(DayKey.calendar.timeZone == TimeZone.current)
}

@Test @MainActor
func goalWatchTodayProjectionPreservesFullFocusConstructorAndTimerValidation() throws {
    let date = try #require(DayKey.date(from: "2026-10-02"))
    let task = goalWatchTodayTask(1, title: "일반 요약", status: .doing, day: date)
    let running = FocusTimerRules.startFocus(
        taskID: task.id, taskTitle: "  활성 집중  ", now: date,
        sessionID: goalWatchTodayID(40_001), instanceID: goalWatchTodayID(40_002)
    )
    let paused = try FocusTimerRules.pause(running, now: date.addingTimeInterval(30))
    let breakTime = FocusTimerRules.startBreak(
        taskID: task.id, taskTitle: "휴식", now: date,
        sessionID: goalWatchTodayID(40_003), instanceID: goalWatchTodayID(40_004)
    )
    var blank = running
    blank.taskTitleSnapshot = " \n "
    var invalidRevision = running
    invalidRevision.revision = 0
    var invalidPhase = running
    invalidPhase.phaseRawValue = "invalid-phase"
    var invalidDeadline = running
    invalidDeadline.deadline = nil
    let focuses: [FocusActiveSessionSnapshot?] = [nil, running, paused, breakTime, blank,
                                                invalidRevision, invalidPhase, invalidDeadline]
    for reference in [date.addingTimeInterval(-1), date, date.addingTimeInterval(60), DayKey.addingDays(1, to: date)] {
        for focus in focuses {
            try checkGoalWatchTodayProjection(tasks: [task], events: [], at: reference, activeFocus: focus)
        }
    }
    let invalid = WatchWidgetSnapshot.make(tasks: [task], events: [], referenceDate: date, activeFocus: invalidRevision)
    #expect(!invalid.hasActiveFocusTimer)
    #expect(invalid.focusTitle == "일반 요약")
    let blankTitle = WatchWidgetSnapshot.make(tasks: [task], events: [], referenceDate: date, activeFocus: blank)
    #expect(blankTitle.hasActiveFocusTimer)
    #expect(blankTitle.focusTitle == "일반 요약")
    #expect(blankTitle.focusSessionID == running.sessionID)
    #expect(WatchWidgetSnapshot.currentSchemaVersion == 1)
}
