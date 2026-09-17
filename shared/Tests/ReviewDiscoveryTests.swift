import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@MainActor private final class ReviewDiscoveryFailureSwitch { var fails = false }

@Test @MainActor
func reviewDiscoveryIncludesAuthoredFieldsPhotosAndLegacyBlocksButNotEmptyRows() throws {
    let body = DailyReview(dayKey: "2026-09-01", content: "본문")
    let title = DailyReview(dayKey: "2026-09-02", title: "제목만", content: "")
    let mood = DailyReview(dayKey: "2026-09-03", mood: "기쁨", content: "")
    let weather = DailyReview(dayKey: "2026-09-04", weather: "맑음", content: "")
    let legacy = DailyReview(dayKey: "2026-09-05", content: "", imageFileNames: ["missing.jpg"])
    let blockOnly = DailyReview(dayKey: "2026-09-06", content: "")
    let empty = DailyReview(dayKey: "2026-09-07", content: "  \n")
    let block = DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: "이전 회고 본문", order: 0)
    let records = ReviewDiscoveryRules.records(
        reviews: [body, title, mood, weather, legacy, blockOnly, empty], attachments: [], blocks: [block], query: ""
    )
    #expect(records.map(\.id) == [blockOnly.dayKey, legacy.dayKey, weather.dayKey, mood.dayKey, title.dayKey, body.dayKey])
    #expect(records.first?.bodyText == "이전 회고 본문")
    #expect(records.first?.title == "이날의 회고")
    #expect(records[1].photoCount == 1)
    #expect(ReviewDiscoveryRules.records(reviews: [blockOnly], attachments: [], blocks: [block], query: "이전 회고").count == 1)
    #expect(ReviewDiscoveryRules.records(reviews: [mood], attachments: [], blocks: [], query: "기쁨").count == 1)
}

@Test @MainActor
func reviewDiscoveryNewerEmptyRepresentativeDoesNotResurrectStaleReview() {
    let old = DailyReview(dayKey: "2026-09-01", content: "지운 본문", updatedAt: .distantPast)
    let latest = DailyReview(dayKey: old.dayKey, content: "", updatedAt: Date())
    let result = ReviewDiscoveryRules.records(reviews: [old, latest], attachments: [], blocks: [], query: "")
    #expect(result.isEmpty)
    let laterDay = DailyReview(dayKey: "2026-09-02", content: "더 최근 날짜", updatedAt: .distantPast)
    latest.content = "오래된 날짜 수정"
    #expect(ReviewDiscoveryRules.records(reviews: [old, latest, laterDay], attachments: [], blocks: [], query: "").map(\.id)
            == [laterDay.dayKey, latest.dayKey])
}

@Test @MainActor
func reviewDiscoveryPagesAcrossEmptyRowsAndSparseYearsWithoutTaskHistory() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let recent = DailyReview(dayKey: "2026-09-17", content: "검색 대상 최신")
    let old = DailyReview(dayKey: "2012-01-01", content: "검색 대상 이전")
    context.insert(recent); context.insert(old)
    let date = try #require(DayKey.date(from: "2026-09-16"))
    for offset in 0..<135 {
        context.insert(DailyReview(dayKey: DayKey.key(for: DayKey.addingDays(-offset, to: date)), content: offset % 2 == 0 ? "" : "다른 내용"))
    }
    try context.save()
    var filter = ReviewDiscoveryFilter()
    filter.searchText = "검색 대상"
    let service = ReviewDiscoveryQueryService(context: context)
    let first = try await service.page(filter: filter, pageSize: 1)
    #expect(first.records.map(\.id) == [recent.dayKey])
    #expect(first.hasMore)
    let second = try await service.page(filter: filter, beforeDayKey: first.nextBeforeDayKey, pageSize: 1)
    #expect(second.records.map(\.id) == [old.dayKey])
    #expect(!second.hasMore)
    let both = try await service.page(filter: filter)
    #expect(both.records.map(\.id) == [recent.dayKey, old.dayKey])
    #expect(!both.hasMore)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
}

@Test @MainActor
func reviewDiscoveryCompletesDuplicateBoundaryDayBeforeAdvancingCursor() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let old = DailyReview(dayKey: "2026-09-01", content: "전날")
    context.insert(old)
    for i in 0..<80 {
        context.insert(DailyReview(dayKey: "2026-09-02", content: "사본 \(i)", updatedAt: Date(timeIntervalSince1970: Double(i))))
    }
    try context.save()
    let service = ReviewDiscoveryQueryService(context: context)
    let first = try await service.page(filter: ReviewDiscoveryFilter(), pageSize: 1)
    #expect(first.records.count == 1)
    #expect(first.records.first?.bodyText == "사본 79")
    let next = try await service.page(filter: ReviewDiscoveryFilter(), beforeDayKey: first.nextBeforeDayKey, pageSize: 1)
    #expect(next.records.map(\.id) == [old.dayKey])
}

@Test @MainActor
func reviewDiscoveryPeriodsSearchAndResetStayIndependentOfActivity() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    context.insert(DailyReview(dayKey: "2026-09-17", weather: "Sunny", content: "오늘"))
    context.insert(DailyReview(dayKey: "2026-09-10", content: "이전"))
    context.insert(DailyReview(dayKey: "2026-10-01", content: "미리 작성한 회고"))
    try context.save()
    let now = try #require(DayKey.date(from: "2026-09-17"))
    var filter = ReviewDiscoveryFilter()
    filter.period = .last7Days
    filter.searchText = "sunny"
    let service = ReviewDiscoveryQueryService(context: context)
    #expect(try await service.page(filter: filter, referenceDate: now).records.map(\.id) == ["2026-09-17"])
    filter.reset()
    #expect(try await service.page(filter: filter, referenceDate: now).records.count == 3)
    let state = ArchiveScreenState()
    state.filter.searchText = "작업 검색"
    state.filter.scope = .tasks
    state.pane = .reviews
    state.reviewFilter = filter
    state.reviewFilter.reset()
    #expect(state.filter.searchText == "작업 검색")
    #expect(state.filter.scope == .tasks)
    #expect(state.pane == .reviews)
}

@Test @MainActor
func reviewDiscoveryRefreshPreservesPageDepthAndOldResultsOnFailure() async throws {
    enum Failure: Error { case unavailable }
    let record1 = ReviewDiscoveryRecord(review: DailyReview(dayKey: "2026-09-17", content: "하나"), attachments: [], legacyFileNames: [], bodyText: "하나")
    let record2 = ReviewDiscoveryRecord(review: DailyReview(dayKey: "2026-09-16", content: "둘"), attachments: [], legacyFileNames: [], bodyText: "둘")
    let failure = ReviewDiscoveryFailureSwitch()
    let session = ReviewDiscoverySession { _, cursor in
        if failure.fails { throw Failure.unavailable }
        return ReviewDiscoveryPage(records: cursor == nil ? [record1] : [record2],
                                   nextBeforeDayKey: cursor == nil ? record1.id : nil, hasMore: cursor == nil)
    }
    session.apply(ReviewDiscoveryFilter())
    await session.waitForPendingLoad()
    session.loadNextPage()
    await session.waitForPendingLoad()
    #expect(session.loadedPageCount == 2)
    #expect(session.records.count == 2)
    failure.fails = true
    session.refreshPreservingDepth()
    await session.waitForPendingLoad()
    #expect(session.errorMessage != nil)
    #expect(session.records.count == 2)
    #expect(session.loadedPageCount == 2)
    failure.fails = false
    session.refreshPreservingDepth()
    await session.waitForPendingLoad()
    #expect(session.errorMessage == nil)
    #expect(session.records.map(\.id) == [record1.id, record2.id])
}

@Test @MainActor
func reviewDiscoveryDebouncedSearchCannotPublishOldResultsAfterCancellation() async {
    let record = ReviewDiscoveryRecord(review: DailyReview(dayKey: "2026-09-17", content: "본문"), attachments: [], legacyFileNames: [], bodyText: "본문")
    let session = ReviewDiscoverySession { filter, _ in
        if filter.searchText == "old" { await Swift.Task.yield() }
        return ReviewDiscoveryPage(records: filter.searchText == "new" ? [] : [record], nextBeforeDayKey: nil, hasMore: false)
    }
    var filter = ReviewDiscoveryFilter()
    filter.searchText = "old"
    session.apply(filter, debounceSearch: true)
    filter.searchText = "new"
    session.apply(filter)
    await session.waitForPendingLoad()
    #expect(session.records.isEmpty)
    session.apply(filter, debounceSearch: true)
    session.cancel()
    await session.waitForPendingLoad()
    #expect(!session.isLoading)
    #expect(session.records.isEmpty)
}

@Test @MainActor
func reviewDiscoveryEditingPreservesLegacyMetadataAndFailedSavePreservesReview() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let review = DailyReview(dayKey: "2026-09-17", title: "원래 제목", weather: "맑음", mood: "차분함", content: "기존 본문")
    context.insert(review)
    try context.save()
    _ = try DiaryAttachmentService.saveReview(review: review, dayKey: review.dayKey,
        title: "수정 제목", content: "수정 본문", attachments: [], in: context)
    #expect(review.weather == "맑음" && review.mood == "차분함")
    #expect(review.content == "수정 본문")
    enum Failure: Error { case saving }
    do {
        try PersistenceCommandService.perform(in: context) {
            DailyReviewService.save(review: review, dayKey: review.dayKey, title: "실패할 수정", content: "실패", in: context)
            throw Failure.saving
        }
        Issue.record("실패한 명령이 성공으로 반환됨")
    } catch Failure.saving { }
    let restored = try #require(context.fetch(BoundedQueryService.dailyReviewDescriptor(id: review.id)).first)
    #expect(restored.title == "수정 제목")
    #expect(restored.content == "수정 본문")
    #expect(restored.weather == "맑음" && restored.mood == "차분함")
    _ = DailyReviewService.save(review: restored, dayKey: restored.dayKey,
        title: "", weather: "", mood: "", content: "", in: context)
    #expect(!DailyReviewRules.hasContent(restored))
    #expect(!DailyReviewRules.hasContent(title: "", content: "", imageFileNames: [" ", ""]))
}
