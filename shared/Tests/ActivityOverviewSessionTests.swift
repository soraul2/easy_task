import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func activityOverviewUsesFixedIntensityAndUniqueTasksPerDay() throws {
    let calendar = activityOverviewCalendar(firstWeekday: 2)
    let referenceDate = try #require(activityOverviewDate("2026-08-14", calendar: calendar))
    let firstTask = UUID()
    let snapshots = [
        TaskActivitySnapshot(taskID: firstTask, activityDayKey: "2026-08-14"),
        TaskActivitySnapshot(taskID: firstTask, activityDayKey: "2026-08-14"),
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2026-08-14"),
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2026-08-13"),
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2026-08-12")
    ]

    let overview = TaskActivityRules.overview(
        from: snapshots,
        weekCount: 26,
        referenceDate: referenceDate,
        calendar: calendar
    )
    let today = try #require(overview.days.first { $0.dayKey == "2026-08-14" })

    #expect(today.completedTaskCount == 2)
    #expect(today.intensity == .medium)
    #expect(overview.currentStreak == 3)
    #expect(overview.bestStreakInLastYear == 3)
    #expect(overview.todayState == .completed)
    #expect(TaskActivityRules.intensity(for: 0) == .none)
    #expect(TaskActivityRules.intensity(for: 1) == .low)
    #expect(TaskActivityRules.intensity(for: 2) == .medium)
    #expect(TaskActivityRules.intensity(for: 4) == .high)
    #expect(TaskActivityRules.intensity(for: 5) == .veryHigh)
}

@Test
func activityOverviewPreservesYesterdayStreakUntilTodayEnds() throws {
    let calendar = activityOverviewCalendar(firstWeekday: 1)
    let referenceDate = try #require(activityOverviewDate("2026-01-01", calendar: calendar))
    let snapshots = [
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2025-12-29"),
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2025-12-30"),
        TaskActivitySnapshot(taskID: UUID(), activityDayKey: "2025-12-31")
    ]

    let overview = TaskActivityRules.overview(
        from: snapshots,
        weekCount: 26,
        referenceDate: referenceDate,
        calendar: calendar
    )

    #expect(overview.currentStreak == 3)
    #expect(overview.todayState == .waitingToContinue)
    #expect(overview.days.filter(\.isInCurrentStreak).map(\.dayKey).sorted() == [
        "2025-12-29", "2025-12-30", "2025-12-31"
    ])
}

@Test
func activityOverviewBuildsLocaleWeeksAndMarksFutureUnavailable() throws {
    let calendar = activityOverviewCalendar(firstWeekday: 2)
    let referenceDate = try #require(activityOverviewDate("2026-08-14", calendar: calendar))
    let compact = TaskActivityRules.overview(
        from: [],
        weekCount: TaskActivityRules.compactWeekCount,
        referenceDate: referenceDate,
        calendar: calendar
    )
    let regular = TaskActivityRules.overview(
        from: [],
        weekCount: TaskActivityRules.regularWeekCount,
        referenceDate: referenceDate,
        calendar: calendar,
        hasEarlierActivity: true
    )

    #expect(compact.weeks.count == 26)
    #expect(compact.days.count == 182)
    #expect(compact.range?.endDayKey == "2026-08-16")
    #expect(compact.days.filter(\.isFuture).map(\.dayKey) == ["2026-08-15", "2026-08-16"])
    #expect(regular.weeks.count == 52)
    #expect(regular.days.count == 364)
    #expect(regular.todayState == .readyToRestart)
}

@Test
func activityOverviewBestStreakIsLimitedToRecent365Days() throws {
    let calendar = activityOverviewCalendar(firstWeekday: 2)
    let referenceDate = try #require(activityOverviewDate("2026-08-14", calendar: calendar))
    var snapshots: [TaskActivitySnapshot] = []
    for offset in 0..<10 {
        let day = calendar.date(byAdding: .day, value: -offset, to: referenceDate)!
        snapshots.append(TaskActivitySnapshot(
            taskID: UUID(),
            activityDayKey: DayKey.key(for: day, calendar: calendar)
        ))
    }
    for offset in 370..<390 {
        let day = calendar.date(byAdding: .day, value: -offset, to: referenceDate)!
        snapshots.append(TaskActivitySnapshot(
            taskID: UUID(),
            activityDayKey: DayKey.key(for: day, calendar: calendar)
        ))
    }

    let overview = TaskActivityRules.overview(
        from: snapshots,
        weekCount: 52,
        referenceDate: referenceDate,
        calendar: calendar
    )

    #expect(overview.currentStreak == 10)
    #expect(overview.bestStreakInLastYear == 10)
}

@Test
@MainActor
func activityOverviewSessionPagesBackwardAndLatestWidthWins() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let calendar = activityOverviewCalendar(firstWeekday: 2)
    let referenceDate = try #require(activityOverviewDate("2026-08-14", calendar: calendar))
    let taskID = UUID()
    for offset in 0..<400 {
        let occurredAt = calendar.date(byAdding: .day, value: -offset, to: referenceDate)!
        let dayKey = DayKey.key(for: occurredAt, calendar: calendar)
        context.insert(TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: dayKey),
            taskId: taskID,
            activityDayKey: dayKey,
            occurredAt: occurredAt,
            origin: .captured,
            createdAt: occurredAt,
            updatedAt: occurredAt
        ))
    }
    try context.save()

    let session = ActivityOverviewSession(context: context)
    session.apply(
        weekCount: TaskActivityRules.compactWeekCount,
        referenceDate: referenceDate,
        calendar: calendar
    )
    session.apply(
        weekCount: TaskActivityRules.regularWeekCount,
        referenceDate: referenceDate,
        calendar: calendar
    )
    for _ in 0..<200 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(10))
    }

    #expect(session.errorMessage == nil)
    #expect(session.overview.range?.weekCount == 52)
    #expect(session.overview.currentStreak == 400)
    #expect(session.overview.bestStreakInLastYear == 365)
    session.cancel()
    #expect(!session.isLoading)
}

@Test
@MainActor
func boundedActivityQueryIncludesPendingRecordsWithoutDuplicates() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let dayKey = "2026-08-14"
    let activity = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: dayKey),
        taskId: taskID,
        activityDayKey: dayKey,
        occurredAt: Date(timeIntervalSince1970: 1_786_752_000)
    )
    context.insert(activity)

    let snapshots = try BoundedQueryService.taskActivitySnapshots(
        from: dayKey,
        through: dayKey,
        in: context
    )

    #expect(snapshots == [TaskActivitySnapshot(taskID: taskID, activityDayKey: dayKey)])
}

@Test
func activityHeatmapLayoutUsesOneGridAndRejectsSpacingHits() {
    let layout = ActivityHeatmapLayout(
        size: CGSize(width: 350, height: 92),
        weekCount: 26,
        spacing: 2
    )
    let target = layout.rect(week: 3, weekday: 4)

    #expect(layout.dayIndex(at: CGPoint(x: target.midX, y: target.midY)) == 25)
    #expect(layout.dayIndex(at: CGPoint(
        x: target.maxX + layout.spacing / 2,
        y: target.midY
    )) == nil)
    #expect(layout.cellSide > 0)
}

private func activityOverviewCalendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func activityOverviewDate(_ dayKey: String, calendar: Calendar) -> Date? {
    let parts = dayKey.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: parts[0],
        month: parts[1],
        day: parts[2]
    ))
}
