import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func dailyReviewContentRuleDetectsTextMetadataAndImages() {
    let emptyReview = DailyReview(dayKey: "2026-07-06", content: "   ")
    let titleOnlyReview = DailyReview(dayKey: "2026-07-06", title: "회고", content: "")
    let weatherOnlyReview = DailyReview(dayKey: "2026-07-06", weather: "맑음", content: "")
    let moodOnlyReview = DailyReview(dayKey: "2026-07-06", mood: "좋음", content: "")
    let imageOnlyReview = DailyReview(dayKey: "2026-07-06", content: "", imageFileNames: ["sample.jpg"])

    #expect(DailyReviewRules.hasContent(emptyReview) == false)
    #expect(DailyReviewRules.hasContent(titleOnlyReview))
    #expect(DailyReviewRules.hasContent(weatherOnlyReview))
    #expect(DailyReviewRules.hasContent(moodOnlyReview))
    #expect(DailyReviewRules.hasContent(imageOnlyReview))
}

@Test
func archiveQueryRulesGroupCompletedTasksAndUseLatestReview() throws {
    let july6 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let earlyCompletion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)))
    let lateCompletion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 11)))
    let day6Task = Task(title: "6일 완료", plannedAt: july6, order: 100)
    let earlyDay7Task = Task(title: "7일 오전 완료", plannedAt: july7, order: 100)
    let lateDay7Task = Task(title: "7일 오후 완료", plannedAt: july7, order: 200)
    let openTask = Task(title: "미완료", plannedAt: july7, order: 300)
    TaskRules.applyStatus(.done, to: day6Task, now: earlyCompletion, completionDayKey: DayKey.key(for: july6))
    TaskRules.applyStatus(.done, to: earlyDay7Task, now: earlyCompletion, completionDayKey: DayKey.key(for: july7))
    TaskRules.applyStatus(.done, to: lateDay7Task, now: lateCompletion, completionDayKey: DayKey.key(for: july7))

    let olderReview = DailyReview(
        dayKey: DayKey.key(for: july7),
        title: "이전 회고",
        content: "이전 내용",
        updatedAt: earlyCompletion
    )
    let latestReview = DailyReview(
        dayKey: DayKey.key(for: july7),
        title: "최신 회고",
        content: "최신 내용",
        updatedAt: lateCompletion
    )

    let records = ArchiveQueryRules.records(
        tasks: [openTask, earlyDay7Task, day6Task, lateDay7Task],
        reviews: [olderReview, latestReview],
        filter: ArchiveFilter(),
        referenceDate: lateCompletion
    )

    #expect(records.map(\.dayKey) == ["2026-07-07", "2026-07-06"])
    #expect(records.first?.tasks.map(\.title) == ["7일 오후 완료", "7일 오전 완료"])
    #expect(records.first?.review?.id == latestReview.id)
    #expect(records.flatMap(\.tasks).contains { $0.id == openTask.id } == false)
}

@Test
func archiveQueryRulesApplyPeriodScopeAndDayLevelSearch() throws {
    let oldDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    let recentDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)))
    let oldTask = Task(title: "오래된 작업", plannedAt: oldDay, order: 100)
    let recentTask = Task(title: "모바일 보관함 정리", note: "상세 메모", plannedAt: recentDay, order: 100)
    TaskRules.applyStatus(.done, to: oldTask, now: today, completionDayKey: DayKey.key(for: oldDay))
    TaskRules.applyStatus(.done, to: recentTask, now: today, completionDayKey: DayKey.key(for: recentDay))
    let review = DailyReview(
        dayKey: DayKey.key(for: recentDay),
        title: "하루 회고",
        content: "모바일 기록을 확인했다."
    )

    let taskSearch = ArchiveFilter(
        searchText: "보관함",
        period: .last7Days,
        scope: .tasks
    )
    let taskRecords = ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: taskSearch,
        referenceDate: today
    )

    #expect(taskRecords.map(\.dayKey) == ["2026-07-08"])
    #expect(taskRecords.first?.review?.id == review.id)
    #expect(taskRecords.first?.matchedTaskIDs == [recentTask.id])
    #expect(taskRecords.first?.reviewMatchesSearch == false)
    #expect(taskRecords.first?.hasSearchQuery == true)

    let taskPresentation = try ArchiveDayPresentation(record: #require(taskRecords.first))
    #expect(taskPresentation.title == "하루 회고")
    #expect(taskPresentation.displayDate == DayKey.display(recentDay))
    #expect(taskPresentation.summaryText == "작업 1 · 회고")
    #expect(taskPresentation.shouldExpandTaskListForSearch)
    #expect(taskPresentation.taskMatchesSearch(recentTask.id))

    let reviewSearch = ArchiveFilter(
        searchText: "회고",
        period: .last7Days,
        scope: .reviews
    )
    let reviewRecords = ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: reviewSearch,
        referenceDate: today
    )

    #expect(reviewRecords.first?.tasks.map(\.id) == [recentTask.id])
    #expect(reviewRecords.first?.matchedTaskIDs.isEmpty == true)
    #expect(reviewRecords.first?.reviewMatchesSearch == true)
    #expect(reviewRecords.first.map(ArchiveDayPresentation.init(record:))?.shouldExpandTaskListForSearch == false)

    let mismatchedScope = ArchiveFilter(
        searchText: "회고",
        period: .last7Days,
        scope: .tasks
    )
    #expect(ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: mismatchedScope,
        referenceDate: today
    ).isEmpty)
}

@Test
func archivePresentationUsesStableFallbackTitles() {
    let taskOnly = ArchiveDayPresentation(record: ArchiveDayRecord(
        dayKey: "2026-07-06",
        tasks: [],
        review: nil
    ))
    let untitledReview = ArchiveDayPresentation(record: ArchiveDayRecord(
        dayKey: "2026-07-07",
        tasks: [],
        review: DailyReview(dayKey: "2026-07-07", title: "  ", content: "기록")
    ))

    #expect(taskOnly.title == "작업 기록")
    #expect(taskOnly.summaryText.isEmpty)
    #expect(untitledReview.title == "하루 회고")
    #expect(untitledReview.summaryText == "회고")
}

@Test
func archiveQueryRulesNormalizeReversedCustomPeriod() throws {
    let july1 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    let july2 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
    let july5 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let july8 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let july9 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))
    let beforeTask = Task(title: "기간 이전 작업", plannedAt: july1, order: 100)
    let includedTask = Task(title: "기간 내 작업", plannedAt: july5, order: 100)
    let afterTask = Task(title: "기간 이후 작업", plannedAt: july9, order: 100)
    TaskRules.applyStatus(.done, to: beforeTask, now: july8, completionDayKey: DayKey.key(for: july1))
    TaskRules.applyStatus(.done, to: includedTask, now: july8, completionDayKey: DayKey.key(for: july5))
    TaskRules.applyStatus(.done, to: afterTask, now: july8, completionDayKey: DayKey.key(for: july9))
    let filter = ArchiveFilter(
        period: .custom,
        customStartDate: july8,
        customEndDate: july2
    )

    let records = ArchiveQueryRules.records(
        tasks: [beforeTask, includedTask, afterTask],
        reviews: [],
        filter: filter,
        referenceDate: july8
    )

    #expect(records.map(\.dayKey) == ["2026-07-05"])
}

@Test
@MainActor
func dailyReviewServiceSavesReviewAndSynchronizesDiaryBlocks() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let dayKey = "2026-07-06"

    let emptyDraft = DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        content: "   ",
        in: context
    )
    #expect(emptyDraft == nil)

    let review = try #require(DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        title: "  회고  ",
        content: "  오늘 메모  ",
        imageFileNames: ["first.jpg"],
        in: context
    ))
    var blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "회고")
    #expect(review.content == "오늘 메모")
    #expect(review.imageFileNames == ["first.jpg"])
    #expect(blocks.map(\.type) == [DiaryBlockType.text.rawValue, DiaryBlockType.image.rawValue])
    #expect(blocks.first?.text == "오늘 메모")
    #expect(blocks.last?.imageFileName == "first.jpg")

    DailyReviewService.save(
        review: review,
        dayKey: dayKey,
        title: "",
        content: "수정된 메모",
        imageFileNames: [],
        in: context
    )
    blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "")
    #expect(review.content == "수정된 메모")
    #expect(review.imageFileNames.isEmpty)
    #expect(blocks.count == 1)
    #expect(blocks.first?.type == DiaryBlockType.text.rawValue)
    #expect(blocks.first?.text == "수정된 메모")
}

@Test
func dailyReviewServiceMigratesLegacyDiaryBlocksIntoSummaryFields() {
    let review = DailyReview(dayKey: "2026-07-06", content: "")
    let textBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: "첫 번째 줄",
        order: 100
    )
    let imageBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: "legacy.jpg",
        order: 200
    )

    let didMigrate = DailyReviewService.migrateBlockSummaryIfNeeded(
        for: review,
        blocks: [imageBlock, textBlock]
    )

    #expect(didMigrate)
    #expect(review.content == "첫 번째 줄")
    #expect(review.imageFileNames == ["legacy.jpg"])
}
