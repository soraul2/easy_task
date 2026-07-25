import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func taskHistoryStatisticsKeepPlannedCohortAndCompletionPeriodSeparate() throws {
    let delayed = try EventReuseTaskHistoryFixtures.thursdayPlannedSaturdayCompleted()
    let archivedOnly = try EventReuseTaskHistoryFixtures.archivedOnlyLegacyTask()
    let friday = try #require(DayKey.date(from: "2026-07-24"))
    let thursday = try #require(DayKey.date(from: "2026-07-23"))
    let outsidePlan = try #require(DayKey.date(from: "2026-07-20"))

    let early = Task(title: "계획일 전 완료", plannedAt: friday, order: 100)
    TaskRules.applyStatus(
        .done,
        to: early,
        now: thursday,
        completionDayKey: "2026-07-23"
    )
    let incomplete = Task(title: "미완료", plannedAt: friday, order: 200)
    let completedOnly = Task(
        title: "기간 밖 계획·기간 안 완료",
        plannedAt: outsidePlan,
        order: 300
    )
    TaskRules.applyStatus(
        .done,
        to: completedOnly,
        now: try #require(DayKey.date(from: "2026-07-25")),
        completionDayKey: "2026-07-25"
    )

    let statistics = TaskHistoryStatisticsRules.statistics(
        from: [delayed, archivedOnly, early, incomplete, completedOnly],
        lowerBound: "2026-07-23",
        upperBound: "2026-07-25"
    )

    #expect(statistics.plannedTaskCount == 4)
    #expect(statistics.completedTaskCount == 4)
    #expect(statistics.completedOnOrBeforePlannedDayCount == 1)
    #expect(statistics.delayedCompletionCount == 2)
    #expect(statistics.incompleteCount == 1)
    #expect(statistics.plannedCompletionRate == 0.75)
}

@Test
func taskHistoryStatisticsUseNewestActiveLogicalTask() throws {
    let day = try #require(DayKey.date(from: "2026-07-25"))
    let logicalID = UUID()
    let older = Task(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "이전 완료",
        status: .done,
        plannedAt: day,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    older.completedAt = day
    older.completedDayKey = "2026-07-25"
    let newer = Task(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "최신 미완료",
        plannedAt: day,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 200)
    )

    let statistics = TaskHistoryStatisticsRules.statistics(
        from: [older, newer],
        lowerBound: "2026-07-25",
        upperBound: "2026-07-25"
    )

    #expect(statistics.plannedTaskCount == 1)
    #expect(statistics.completedTaskCount == 0)
    #expect(statistics.incompleteCount == 1)
}

@Test
func taskHistoryStatisticsPresentationNamesBothPopulations() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-25"))
    let presentation = TaskHistoryStatisticsPresentation(
        filter: ArchiveFilter(
            period: .last7Days,
            dateBasis: .planned
        ),
        referenceDate: referenceDate
    )

    #expect(presentation.periodTitle.contains("2026"))
    #expect(presentation.populationTitle.contains("전체 작업"))
    #expect(presentation.populationTitle.contains("계획일 기준"))
    #expect(presentation.meaningDescription.contains("완료 작업은 완료일 기준"))
}

@Test
@MainActor
func boundedTaskHistoryStatisticsCandidatesUseFixedPagination() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let inPeriod = try #require(DayKey.date(from: "2026-07-24"))
    let outsidePeriod = try #require(DayKey.date(from: "2026-07-01"))
    let completionDay = try #require(DayKey.date(from: "2026-07-25"))

    for index in 0..<450 {
        context.insert(Task(
            title: "계획 코호트 \(index)",
            plannedAt: inPeriod,
            order: Double(index)
        ))
    }
    for index in 0..<50 {
        let task = Task(
            title: "완료 모집단 \(index)",
            plannedAt: outsidePeriod,
            order: Double(index)
        )
        TaskRules.applyStatus(
            .done,
            to: task,
            now: completionDay,
            completionDayKey: "2026-07-25"
        )
        context.insert(task)
    }
    try context.save()

    let candidates = try BoundedQueryService.taskHistoryStatisticsCandidates(
        from: "2026-07-23",
        through: "2026-07-25",
        in: context
    )
    let statistics = TaskHistoryStatisticsRules.statistics(
        from: candidates,
        lowerBound: "2026-07-23",
        upperBound: "2026-07-25"
    )

    #expect(BoundedQueryService.taskHistoryStatisticsBatchSize == 200)
    #expect(candidates.count == 500)
    #expect(statistics.plannedTaskCount == 450)
    #expect(statistics.completedTaskCount == 50)
    #expect(statistics.incompleteCount == 450)
}

@Test
@MainActor
func taskHistoryStatisticsSessionAppliesTheLatestPeriod() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let thursday = try #require(DayKey.date(from: "2026-07-23"))
    let saturday = try #require(DayKey.date(from: "2026-07-25"))
    context.insert(Task(title: "목요일 계획", plannedAt: thursday, order: 100))
    context.insert(Task(title: "토요일 계획", plannedAt: saturday, order: 200))
    try context.save()

    let session = TaskHistoryStatisticsSession(context: context)
    session.apply(ArchiveFilter(), referenceDate: saturday)
    session.apply(
        ArchiveFilter(
            period: .custom,
            customStartDate: thursday,
            customEndDate: thursday
        ),
        referenceDate: saturday
    )
    for _ in 0..<100 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(20))
    }

    #expect(session.errorMessage == nil)
    #expect(session.statistics.plannedTaskCount == 1)
    #expect(session.statistics.incompleteCount == 1)
}
