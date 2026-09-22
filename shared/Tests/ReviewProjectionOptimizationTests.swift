import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// The goal's starting implementation is retained only as a result oracle.
/// Benchmarks time the production implementation in separate before/after runs.
@MainActor
private func originalReviewProjection(
    reviews: [DailyReview], attachments: [DiaryAttachment], blocks: [DiaryBlock], query: String
) -> [ReviewDiscoveryRecord] {
    let representatives = Dictionary(grouping: reviews.filter { $0.supersededAt == nil }, by: \.dayKey)
        .values.compactMap { rows in
            rows.max {
                $0.updatedAt != $1.updatedAt ? $0.updatedAt < $1.updatedAt
                    : $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }
    let index = DiaryAttachmentIndex(attachments: attachments, blocks: blocks)
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return representatives.compactMap { review -> ReviewDiscoveryRecord? in
        let activeBlocks = blocks.filter { $0.reviewId == review.id && $0.supersededAt == nil }
            .sorted { $0.order < $1.order }
        let body = review.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let blockText = activeBlocks.map(\.text).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.joined(separator: "\n\n")
        let record = ReviewDiscoveryRecord(
            review: review, attachments: index.activeAttachments(for: review.id),
            legacyFileNames: index.unresolvedLegacyImageFileNames(for: review),
            bodyText: body.isEmpty ? blockText : body
        )
        guard DailyReviewRules.hasContent(review) || !blockText.isEmpty || record.photoCount > 0 else { return nil }
        guard query.isEmpty || ArchiveQueryRules.matchesSearch(review, query: query)
            || ArchiveQueryRules.contains(blockText, query: query) else { return nil }
        return record
    }.sorted { $0.id > $1.id }
}

private struct ReviewProjectionSnapshot: Equatable {
    var dayKey: String
    var instanceID: UUID
    var title: String
    var body: String
    var attachmentIDs: [UUID]
    var legacyNames: [String]

    @MainActor init(_ record: ReviewDiscoveryRecord) {
        dayKey = record.id
        instanceID = record.review.instanceID
        title = record.title
        body = record.bodyText
        attachmentIDs = record.attachments.map(\.instanceID)
        legacyNames = record.legacyFileNames
    }
}

@Test @MainActor
func reviewProjectionMatchesStartingAlgorithmAcrossBlocksDuplicatesAndEdits() throws {
    let now = Date(timeIntervalSince1970: 1_789_430_400)
    let old = DailyReview(dayKey: "2026-09-22", title: "지운 제목", content: "지운 내용", updatedAt: now)
    let empty = DailyReview(dayKey: old.dayKey, content: " \n", updatedAt: now.addingTimeInterval(1))
    let authored = DailyReview(dayKey: "2026-09-21", title: "제목 검색", content: "본문 우선", updatedAt: now)
    let legacy = DailyReview(dayKey: "2026-09-20", content: "", imageFileNames: ["photo.jpg", "photo.jpg"], updatedAt: now)
    let blockOnly = DailyReview(dayKey: "2026-09-19", content: "", updatedAt: now)
    let metadata = DailyReview(dayKey: "2026-09-18", weather: "Sunny", mood: "기쁨", content: "", updatedAt: now)
    let discarded = DailyReview(dayKey: "2026-09-17", content: "대체된 회고", supersededAt: now)
    let tieID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let winnerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let tie = DailyReview(instanceID: tieID, dayKey: "2026-09-16", content: "이전 사본", updatedAt: now)
    let winner = DailyReview(instanceID: winnerID, dayKey: tie.dayKey, content: "최종 사본", updatedAt: now)
    var reviews = [old, empty, authored, legacy, blockOnly, metadata, discarded, tie, winner]
    var blocks = [
        DiaryBlock(reviewId: authored.id, dayKey: authored.dayKey, type: .text, text: "숨은 블록 검색", order: 0),
        DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: "동일 순서 첫째", order: 100),
        DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: "동일 순서 둘째", order: 100),
        DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: "한글 블록", order: -10),
        DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: " \n ", order: -20),
        DiaryBlock(reviewId: blockOnly.id, dayKey: blockOnly.dayKey, type: .text, text: "대체된 블록", order: 0, supersededAt: now),
        DiaryBlock(reviewId: legacy.id, dayKey: legacy.dayKey, type: .image, imageFileName: "block-only.jpg", order: 0),
        DiaryBlock(reviewId: old.id, dayKey: old.dayKey, type: .text, text: "되살리지 않을 블록", order: 0),
        DiaryBlock(reviewId: UUID(), dayKey: blockOnly.dayKey, type: .text, text: "다른 부모", order: 0),
    ]
    let attachments = [DiaryAttachment(reviewId: legacy.id, order: 100, originalFileName: "current.png",
        mimeType: "image/png", byteCount: 0, sha256: "", data: Data())]
    let queries = ["", "한글", "한글".decomposedStringWithCanonicalMapping, "숨은 블록", " SUNNY ", "기쁨", "최종", "불일치"]
    for _ in 0..<2 {
        for query in queries {
            let expected = originalReviewProjection(reviews: reviews, attachments: attachments, blocks: blocks, query: query)
            let actual = ReviewDiscoveryRules.records(reviews: reviews, attachments: attachments, blocks: blocks, query: query)
            #expect(actual.map(ReviewProjectionSnapshot.init) == expected.map(ReviewProjectionSnapshot.init))
            #expect(!actual.contains { $0.id == empty.dayKey })
        }
        reviews.reverse()
        blocks.reverse()
    }
    blockOnly.content = "수정 직후 본문"
    blocks[2].text = "편집된 블록"
    blocks[2].supersededAt = now
    #expect(ReviewDiscoveryRules.records(reviews: reviews, attachments: attachments, blocks: blocks, query: "")
        .map(ReviewProjectionSnapshot.init) == originalReviewProjection(
            reviews: reviews, attachments: attachments, blocks: blocks, query: ""
        ).map(ReviewProjectionSnapshot.init))
}

@MainActor
private struct ReviewProjectionFixture {
    let container: ModelContainer
    let reviews: [DailyReview]
    let blocks: [DiaryBlock]

    init(blocksPerReview: Int, boundaryDuplicates: Int = 0) throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let start = try #require(DayKey.date(from: "2026-09-22"))
        let fixedTime = Date(timeIntervalSince1970: 1_789_430_400)
        var reviews: [DailyReview] = []
        var blocks: [DiaryBlock] = []
        for index in 0..<64 {
            let review = DailyReview(dayKey: DayKey.key(for: DayKey.addingDays(-index, to: start)),
                content: "", createdAt: fixedTime, updatedAt: fixedTime)
            context.insert(review)
            reviews.append(review)
            for child in 0..<blocksPerReview {
                let text = index == 63 && child == 0 ? "희소한 검색어" : "회고 \(index)의 블록 \(child)"
                let block = DiaryBlock(reviewId: review.id, dayKey: review.dayKey, type: .text,
                    text: text, order: Double(blocksPerReview - child), createdAt: fixedTime, updatedAt: fixedTime)
                context.insert(block)
                blocks.append(block)
            }
        }
        for index in 0..<boundaryDuplicates {
            let duplicate = DailyReview(dayKey: reviews[63].dayKey, content: "이전 사본 \(index)",
                createdAt: fixedTime, updatedAt: fixedTime.addingTimeInterval(-Double(index + 1)))
            context.insert(duplicate)
            reviews.append(duplicate)
            let block = DiaryBlock(reviewId: duplicate.id, dayKey: duplicate.dayKey, type: .text,
                text: "채택하지 않는 사본 블록", order: 0, createdAt: fixedTime, updatedAt: fixedTime)
            context.insert(block)
            blocks.append(block)
        }
        try context.save()
        self.container = container
        self.reviews = reviews
        self.blocks = blocks
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_REVIEW_PROJECTION_PERFORMANCE"] == "1"))
@MainActor
func reviewProjectionOptimizationPerformance() throws {
    // 64 is the production discovery seed batch; duplicates complete the final day.
    for (name, blocksPerReview, duplicateCount) in [
        ("ordinary-64x3", 3, 0), ("large-blocks-64x100", 100, 0), ("boundary-64plus80x3", 3, 80)
    ] {
        let fixture = try ReviewProjectionFixture(blocksPerReview: blocksPerReview, boundaryDuplicates: duplicateCount)
        for (search, query, expectedCount) in [("all", "", 64), ("sparse", "희소한 검색어", 1), ("none", "없는 검색어", 0)] {
            let operation = {
                ReviewDiscoveryRules.records(reviews: fixture.reviews, attachments: [], blocks: fixture.blocks, query: query)
            }
            let expected = operation().map(ReviewProjectionSnapshot.init)
            #expect(expected.count == expectedCount)
            var samples: [Double] = []
            for _ in 0..<7 {
                let start = DispatchTime.now().uptimeNanoseconds
                let records = operation()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                #expect(records.map(ReviewProjectionSnapshot.init) == expected)
            }
            let sorted = samples.sorted()
            print("REVIEW_PROJECTION_BENCHMARK name=\(name)-\(search) unit=ms reviews=\(fixture.reviews.count) blocks=\(fixture.blocks.count) n=7 p50=\(sorted[3]) count=\(expected.count) samples=\(samples)")
            withExtendedLifetime(fixture.container) {}
        }
    }
}

@MainActor
private final class ReviewRefreshProbe {
    var calls = 0
    var searches: [String] = []
    var suspends = false
    private var response: CheckedContinuation<Void, Never>?
    private var resumedPage: ReviewDiscoveryPage?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func suspendedPage() async throws -> ReviewDiscoveryPage {
        await withCheckedContinuation { continuation in
            response = continuation
            started = true
            startedWaiter?.resume()
            startedWaiter = nil
        }
        return try #require(resumedPage)
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func resume(with page: ReviewDiscoveryPage) {
        resumedPage = page
        response?.resume()
        response = nil
    }
}

@MainActor
private func reviewRefreshRecord(dayKey: String, content: String) -> ReviewDiscoveryRecord {
    ReviewDiscoveryRecord(review: DailyReview(dayKey: dayKey, content: content),
        attachments: [], legacyFileNames: [], bodyText: content)
}

@Test @MainActor
func reviewDiscoveryRefreshIgnoresIrrelevantAndInactiveEvents() async {
    let first = reviewRefreshRecord(dayKey: "2026-09-22", content: "첫 페이지")
    let second = reviewRefreshRecord(dayKey: "2026-09-21", content: "둘째 페이지")
    let probe = ReviewRefreshProbe()
    let session = ReviewDiscoverySession { _, cursor in
        probe.calls += 1
        return ReviewDiscoveryPage(records: cursor == nil ? [first] : [second],
            nextBeforeDayKey: cursor == nil ? first.id : nil, hasMore: cursor == nil)
    }
    session.apply(ReviewDiscoveryFilter())
    await session.waitForPendingLoad()
    session.loadNextPage()
    await session.waitForPendingLoad()
    #expect(probe.calls == 2)
    #expect(session.loadedPageCount == 2)

    for visible in [false, true] {
        for active in [false, true] {
            for kind in [CloudKitSyncEventKind.setup, .export, .unknown, .import] {
                for completed in [false, true] {
                    for succeeded in [false, true] {
                        let summary = CloudKitSyncEventSummary(kind: kind, isCompleted: completed, succeeded: succeeded)
                        let before = probe.calls
                        session.refreshForCloudKitEvent(summary, isVisible: visible, isSceneActive: active)
                        await session.waitForPendingLoad()
                        let expectedCalls = visible && active && kind == .import && completed && succeeded ? 2 : 0
                        #expect(probe.calls - before == expectedCalls)
                        #expect(session.loadedPageCount == 2)
                        #expect(session.records.map(\.id) == [first.id, second.id])
                    }
                }
            }
            let before = probe.calls
            session.refreshForChange(isVisible: visible, isSceneActive: active)
            await session.waitForPendingLoad()
            #expect(probe.calls - before == (visible && active ? 2 : 0))
        }
    }
    let beforeUnknown = probe.calls
    session.refreshForCloudKitEvent(nil, isVisible: true, isSceneActive: true)
    await session.waitForPendingLoad()
    #expect(probe.calls == beforeUnknown)

    // Reappearance explicitly refreshes accumulated depth even after hidden imports.
    session.refreshForChange(isVisible: true, isSceneActive: true)
    await session.waitForPendingLoad()
    #expect(probe.calls == beforeUnknown + 2)
    #expect(session.loadedPageCount == 2)
    #expect(session.records.map(\.id) == [first.id, second.id])
}

@Test @MainActor
func reviewDiscoveryCancelledRefreshDoesNotPublishLatePage() async {
    let original = reviewRefreshRecord(dayKey: "2026-09-22", content: "기존 결과")
    let stale = reviewRefreshRecord(dayKey: "2026-09-21", content: "늦게 도착한 결과")
    let probe = ReviewRefreshProbe()
    let session = ReviewDiscoverySession { _, _ in
        probe.calls += 1
        if probe.suspends { return try await probe.suspendedPage() }
        return ReviewDiscoveryPage(records: [original], nextBeforeDayKey: nil, hasMore: false)
    }
    session.apply(ReviewDiscoveryFilter())
    await session.waitForPendingLoad()
    probe.suspends = true
    session.refreshPreservingDepth()
    await probe.waitUntilStarted()
    session.cancel()
    #expect(!session.isLoading)
    probe.resume(with: ReviewDiscoveryPage(records: [stale], nextBeforeDayKey: nil, hasMore: false))
    await session.waitForPendingLoad()
    #expect(session.records.map(\.id) == [original.id])
    #expect(session.loadedPageCount == 1)
    #expect(session.errorMessage == nil)

    probe.suspends = false
    session.refreshForChange(isVisible: true, isSceneActive: true)
    await session.waitForPendingLoad()
    #expect(session.records.map(\.id) == [original.id])
    #expect(probe.calls == 3)
    #expect(!session.isLoading)
}

@Test @MainActor
func reviewDiscoveryReappearanceAppliesDeferredFilterThenPreservesItsDepth() async {
    let first = reviewRefreshRecord(dayKey: "2026-09-22", content: "첫 페이지")
    let second = reviewRefreshRecord(dayKey: "2026-09-21", content: "둘째 페이지")
    let probe = ReviewRefreshProbe()
    let session = ReviewDiscoverySession { filter, cursor in
        probe.calls += 1
        probe.searches.append(filter.searchText)
        return ReviewDiscoveryPage(records: cursor == nil ? [first] : [second],
            nextBeforeDayKey: cursor == nil ? first.id : nil, hasMore: cursor == nil)
    }
    session.refreshForChange(isVisible: true, isSceneActive: true, filter: ReviewDiscoveryFilter())
    await session.waitForPendingLoad()
    session.loadNextPage()
    await session.waitForPendingLoad()
    #expect(probe.calls == 2)
    #expect(session.loadedPageCount == 2)

    var deferred = ReviewDiscoveryFilter()
    deferred.searchText = "복귀 후 검색"
    session.refreshForChange(isVisible: false, isSceneActive: true, filter: deferred)
    session.refreshForChange(isVisible: true, isSceneActive: false, filter: deferred)
    await session.waitForPendingLoad()
    #expect(probe.calls == 2)
    #expect(probe.searches == ["", ""])
    #expect(session.loadedPageCount == 2)

    session.refreshForChange(isVisible: true, isSceneActive: true, filter: deferred)
    await session.waitForPendingLoad()
    #expect(probe.calls == 3)
    #expect(probe.searches.last == deferred.searchText)
    #expect(session.loadedPageCount == 1)
    #expect(session.records.map(\.id) == [first.id])
    session.loadNextPage()
    await session.waitForPendingLoad()
    #expect(session.loadedPageCount == 2)
    session.cancel()
    session.refreshForChange(isVisible: true, isSceneActive: true, filter: deferred)
    await session.waitForPendingLoad()
    #expect(probe.calls == 6)
    #expect(probe.searches.suffix(4).allSatisfy { $0 == deferred.searchText })
    #expect(session.loadedPageCount == 2)
    #expect(session.records.map(\.id) == [first.id, second.id])
}
