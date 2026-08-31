import Foundation
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func lockScreenWidgetSummariesUsePlannedTodayEligibility() throws {
    let today = try #require(DayKey.date(from: "2026-07-16"))
    let yesterday = try #require(DayKey.date(from: "2026-07-15"))
    let todo = makeTask(title: "할 일", status: .todo, plannedAt: today, order: 20)
    let doing = makeTask(title: "진행", status: .doing, plannedAt: today, order: 10)
    let completedToday = makeTask(
        title: "오늘 완료",
        status: .done,
        plannedAt: yesterday,
        completedDayKey: "2026-07-16"
    )
    let completedTomorrow = makeTask(
        title: "내일 완료",
        status: .done,
        plannedAt: today,
        completedDayKey: "2026-07-17"
    )
    let carryover = makeTask(title: "이월", status: .todo, plannedAt: yesterday)
    let archived = makeTask(
        title: "보관됨",
        status: .done,
        plannedAt: today,
        completedDayKey: "2026-07-16"
    )
    archived.archivedAt = today
    let superseded = makeTask(title: "대체됨", status: .todo, plannedAt: today)
    superseded.supersededAt = today

    let summaries = LockScreenWidgetRules.makeDaySummaries(
        tasks: [
            carryover,
            completedTomorrow,
            superseded,
            archived,
            completedToday,
            doing,
            todo
        ],
        events: [],
        referenceDate: today
    )
    let todaySummary = try #require(summaries.first)
    let tomorrowSummary = try #require(summaries.dropFirst().first)

    #expect(todaySummary.todoCount == 1)
    #expect(todaySummary.doingCount == 1)
    #expect(todaySummary.doneCount == 1)
    #expect(todaySummary.remainingTaskCount == 2)
    #expect(todaySummary.focusTitle == "진행")
    #expect(todaySummary.focusKind == .doingTask)
    #expect(tomorrowSummary.doneCount == 0)
    #expect(tomorrowSummary.todoCount == 0)
    #expect(tomorrowSummary.doingCount == 0)
}

@Test
func lockScreenTaskPresentationPrefersDoingThenTodoAndUsesCompactProgress() {
    let doingID = UUID()
    let todoID = UUID()
    let doing = PlannerWidgetTaskPreview(
        id: doingID,
        title: "기획서 작성",
        status: .doing,
        order: 0
    )
    let todo = PlannerWidgetTaskPreview(
        id: todoID,
        title: "검토 요청",
        status: .todo,
        order: 1
    )
    let doingPresentation = LockScreenWidgetRules.taskPresentation(
        summary: LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 1,
            doingCount: 1,
            doneCount: 3,
            eventCount: 0
        ),
        previews: [doing, todo]
    )
    #expect(doingPresentation.state == .doing)
    #expect(doingPresentation.taskID == doingID)
    #expect(doingPresentation.title == "기획서 작성")
    #expect(doingPresentation.progressText == "3/5")

    let todoPresentation = LockScreenWidgetRules.taskPresentation(
        summary: LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 1,
            doingCount: 0,
            doneCount: 3,
            eventCount: 0
        ),
        previews: [todo]
    )
    #expect(todoPresentation.state == .startable)
    #expect(todoPresentation.taskID == todoID)
    #expect(todoPresentation.progressText == "3/4")
}

@Test
func lockScreenTaskPresentationHandlesCompleteAndEmptyDays() {
    let complete = LockScreenWidgetRules.taskPresentation(
        summary: LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 0,
            doingCount: 0,
            doneCount: 4,
            eventCount: 1
        ),
        previews: []
    )
    #expect(complete.state == .complete)
    #expect(complete.title == "오늘 완료")
    #expect(complete.progressText == "4/4")

    let empty = LockScreenWidgetRules.taskPresentation(
        summary: LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 0,
            doingCount: 0,
            doneCount: 0,
            eventCount: 2
        ),
        previews: []
    )
    #expect(empty.state == .empty)
    #expect(empty.title == "오늘 할 일 없음")
    #expect(empty.progressText == "0/0")
}

@Test
@MainActor
func lockScreenWidgetSummariesCoverEightDaysIncludingEmptyDays() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let coverage = LockScreenWidgetRules.coverageDayKeys(for: referenceDate)
    let summaries = LockScreenWidgetRules.makeDaySummaries(
        tasks: [],
        events: [],
        referenceDate: referenceDate
    )

    #expect(coverage.startDayKey == "2026-07-16")
    #expect(coverage.endDayKey == "2026-07-23")
    #expect(summaries.count == 8)
    #expect(summaries.map(\.dayKey) == [
        "2026-07-16",
        "2026-07-17",
        "2026-07-18",
        "2026-07-19",
        "2026-07-20",
        "2026-07-21",
        "2026-07-22",
        "2026-07-23"
    ])
    #expect(summaries.allSatisfy { !$0.hasContent })
}

@Test
@MainActor
func lockScreenWidgetFocusPrefersDoingThenEventThenTodo() throws {
    let firstDay = try #require(DayKey.date(from: "2026-07-16"))
    let secondDay = try #require(DayKey.date(from: "2026-07-17"))
    let thirdDay = try #require(DayKey.date(from: "2026-07-18"))
    let tasks = [
        makeTask(title: "나중 진행", status: .doing, plannedAt: firstDay, order: 20),
        makeTask(title: "  먼저 진행  ", status: .doing, plannedAt: firstDay, order: 10),
        makeTask(title: "첫째 할 일", status: .todo, plannedAt: firstDay, order: 0),
        makeTask(title: "둘째 할 일", status: .todo, plannedAt: secondDay, order: 0),
        makeTask(title: "셋째 할 일", status: .todo, plannedAt: thirdDay, order: 0)
    ]
    let secondDayEvent = try #require(CalendarEventRules.makeEvent(
        title: "  둘째 일정  ",
        startAt: secondDay,
        endAt: secondDay,
        now: firstDay
    ))

    let summaries = LockScreenWidgetRules.makeDaySummaries(
        tasks: tasks,
        events: [secondDayEvent],
        referenceDate: firstDay
    )

    #expect(summaries[0].focusTitle == "먼저 진행")
    #expect(summaries[0].focusKind == .doingTask)
    #expect(summaries[1].focusTitle == "둘째 일정")
    #expect(summaries[1].focusKind == .event)
    #expect(summaries[2].focusTitle == "셋째 할 일")
    #expect(summaries[2].focusKind == .todoTask)
}

@Test
@MainActor
func lockScreenWidgetSpanningEventsAndDuplicatesAreCountedOnce() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let endDate = try #require(DayKey.date(from: "2026-07-18"))
    let logicalID = UUID()
    let older = try #require(CalendarEventRules.makeEvent(
        title: "이전 제목",
        startAt: referenceDate,
        endAt: endDate,
        now: referenceDate
    ))
    older.id = logicalID
    let newer = try #require(CalendarEventRules.makeEvent(
        title: "최신 제목",
        startAt: referenceDate,
        endAt: endDate,
        now: DayKey.addingDays(1, to: referenceDate)
    ))
    newer.id = logicalID

    let summaries = LockScreenWidgetRules.makeDaySummaries(
        tasks: [],
        events: [older, newer],
        referenceDate: referenceDate
    )

    #expect(summaries[0].eventCount == 1)
    #expect(summaries[1].eventCount == 1)
    #expect(summaries[2].eventCount == 1)
    #expect(summaries[0].focusTitle == "최신 제목")
    #expect(summaries[0].focusKind == .event)
}

@Test
@MainActor
func lockScreenWidgetDuplicateTasksChooseLatestRepresentative() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let logicalID = UUID()
    let older = makeTask(
        id: logicalID,
        title: "이전 작업",
        status: .todo,
        plannedAt: referenceDate,
        updatedAt: referenceDate
    )
    let newer = makeTask(
        id: logicalID,
        title: "최신 작업",
        status: .doing,
        plannedAt: referenceDate,
        updatedAt: DayKey.addingDays(1, to: referenceDate)
    )

    let summary = try #require(LockScreenWidgetRules.makeDaySummaries(
        tasks: [older, newer],
        events: [],
        referenceDate: referenceDate
    ).first)

    #expect(summary.todoCount == 0)
    #expect(summary.doingCount == 1)
    #expect(summary.focusTitle == "최신 작업")
}

@MainActor
private func makeTask(
    id: UUID = UUID(),
    title: String,
    status: TaskStatus,
    plannedAt: Date,
    order: Double = 0,
    completedDayKey: String? = nil,
    updatedAt: Date? = nil
) -> Task {
    let task = Task(
        id: id,
        title: title,
        status: status,
        plannedAt: plannedAt,
        order: order,
        createdAt: plannedAt,
        updatedAt: updatedAt ?? plannedAt
    )
    if status == .done {
        task.completedAt = plannedAt
        task.completedDayKey = completedDayKey
    }
    return task
}
