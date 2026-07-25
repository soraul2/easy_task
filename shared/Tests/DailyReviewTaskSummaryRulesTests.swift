import Foundation
import Testing
@testable import EasyTaskCore

@Test
func dailyReviewSummaryIncludesTodayCarryoverAndUsesCompletionDay() throws {
    let yesterday = try #require(DayKey.date(from: "2026-07-05"))
    let today = try #require(DayKey.date(from: "2026-07-06"))
    let todayKey = DayKey.key(for: today)
    let completionTime = try #require(
        DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 18))
    )

    let carryover = Task(title: "어제 미완료", plannedAt: yesterday, order: 100)
    let inProgress = Task(title: "오늘 진행", status: .doing, plannedAt: today, order: 100)
    let completed = Task(title: "오늘 완료", plannedAt: yesterday, order: 200)
    TaskRules.applyStatus(.done, to: completed, now: completionTime, completionDayKey: todayKey)

    let summary = DailyReviewTaskSummaryRules.summary(
        from: [carryover, inProgress, completed],
        selectedDayKey: todayKey,
        todayKey: todayKey
    )

    #expect(summary.completed.isEmpty)
    #expect(summary.actualCompleted.map(\.title) == ["오늘 완료"])
    #expect(summary.inProgress.map(\.title) == ["오늘 진행"])
    #expect(summary.pending.map(\.title) == ["어제 미완료"])
    #expect(summary.pending.first?.isCarryover == true)
    #expect(summary.totalCount == 2)
    #expect(summary.actualCompleted.count == 1)
}

@Test
func dailyReviewSummaryUsesHistoricalBoardRulesWithoutCarryover() throws {
    let selectedDate = try #require(DayKey.date(from: "2026-07-04"))
    let today = try #require(DayKey.date(from: "2026-07-06"))
    let selectedDayKey = DayKey.key(for: selectedDate)
    let todayKey = DayKey.key(for: today)

    let pending = Task(title: "과거 미완료", plannedAt: selectedDate, order: 100)
    let completed = Task(title: "과거 완료", plannedAt: today, order: 100)
    TaskRules.applyStatus(.done, to: completed, now: today, completionDayKey: selectedDayKey)

    let summary = DailyReviewTaskSummaryRules.summary(
        from: [pending, completed],
        selectedDayKey: selectedDayKey,
        todayKey: todayKey
    )

    #expect(summary.completed.isEmpty)
    #expect(summary.actualCompleted.map(\.title) == ["과거 완료"])
    #expect(summary.pending.map(\.title) == ["과거 미완료"])
    #expect(summary.pending.first?.isCarryover == false)
}

@Test
func dailyReviewSummaryExcludesSupersededAndConvergesDuplicateTaskIDs() throws {
    let selectedDate = try #require(DayKey.date(from: "2026-07-06"))
    let taskID = UUID()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)
    let older = Task(
        id: taskID,
        title: "이전 제목",
        plannedAt: selectedDate,
        order: 100,
        updatedAt: olderDate
    )
    let newer = Task(
        id: taskID,
        title: "최신 제목",
        status: .doing,
        plannedAt: selectedDate,
        order: 200,
        updatedAt: newerDate
    )
    let superseded = Task(title: "제외", plannedAt: selectedDate, order: 300)
    superseded.supersededAt = newerDate

    let summary = DailyReviewTaskSummaryRules.summary(
        from: [older, superseded, newer],
        selectedDayKey: DayKey.key(for: selectedDate),
        todayKey: DayKey.key(for: selectedDate)
    )

    #expect(summary.totalCount == 1)
    #expect(summary.inProgress.map(\.title) == ["최신 제목"])
}

@Test
func dailyReviewSummaryExcludesArchivedOpenTasks() throws {
    let selectedDate = try #require(DayKey.date(from: "2026-07-06"))
    let task = Task(title: "보관된 미완료", plannedAt: selectedDate, order: 100)
    task.archivedAt = Date()

    let summary = DailyReviewTaskSummaryRules.summary(
        from: [task],
        selectedDayKey: DayKey.key(for: selectedDate),
        todayKey: DayKey.key(for: selectedDate)
    )

    #expect(summary.isEmpty)
}

@Test
func dailyReviewSummarySeparatesPlannedAndActualCompletionAxes() throws {
    let delayed = try EventReuseTaskHistoryFixtures.thursdayPlannedSaturdayCompleted()
    let sameDay = try EventReuseTaskHistoryFixtures.sameDayCompleted()

    let thursday = DailyReviewTaskSummaryRules.summary(
        from: [delayed, sameDay],
        selectedDayKey: "2026-07-23",
        todayKey: "2026-07-25",
        includeCarryoverOnToday: false
    )
    let saturday = DailyReviewTaskSummaryRules.summary(
        from: [delayed, sameDay],
        selectedDayKey: "2026-07-25",
        todayKey: "2026-07-25",
        includeCarryoverOnToday: false
    )

    #expect(thursday.completed.map(\.id) == [delayed.id])
    #expect(thursday.actualCompleted.isEmpty)
    #expect(Set(saturday.completed.map(\.id)) == [sameDay.id])
    #expect(Set(saturday.actualCompleted.map(\.id)) == [delayed.id, sameDay.id])
    #expect(saturday.actualCompleted.first { $0.id == delayed.id }?.plannedDayKey == "2026-07-23")
}

@Test
func dailyReviewSummaryUsesFallbackAndConvergesDuplicatesOnBothAxes() throws {
    let legacy = try EventReuseTaskHistoryFixtures.completedAtOnlyLegacyTask()
    let logicalID = UUID()
    let saturday = try #require(DayKey.date(from: "2026-07-25"))
    let older = Task(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "이전 중복",
        status: .done,
        plannedAt: saturday,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    older.completedAt = saturday
    older.completedDayKey = "2026-07-25"
    let newer = Task(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "최신 중복",
        status: .done,
        plannedAt: saturday,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    newer.completedAt = saturday
    newer.completedDayKey = "2026-07-25"

    let summary = DailyReviewTaskSummaryRules.summary(
        from: [older, legacy, newer],
        selectedDayKey: "2026-07-25",
        todayKey: "2026-07-25",
        includeCarryoverOnToday: false
    )

    #expect(summary.actualCompleted.contains { $0.id == legacy.id })
    #expect(summary.actualCompleted.filter { $0.id == logicalID }.map(\.title) == ["최신 중복"])
    #expect(summary.completed.filter { $0.id == logicalID }.map(\.title) == ["최신 중복"])
}
