import Foundation
import Observation
import SwiftData

public enum ArchivePane: String, CaseIterable, Identifiable {
    case activity, reviews
    public var id: String { rawValue }
    public var title: String { self == .activity ? "활동 기록" : "회고" }
}

public struct ReviewDiscoveryFilter: Equatable {
    public var searchText = ""
    public var period: ArchivePeriod = .all
    public var customStartDate = DayKey.addingDays(-30, to: Date())
    public var customEndDate = Date()
    public init() {}
    public var hasActiveCriteria: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || period != .all
    }
    public mutating func reset() { self = Self() }

    func range(referenceDate: Date) -> ArchiveDayKeyRange {
        if period == .all { return ArchiveDayKeyRange(lowerBound: nil, upperBound: "9999-12-31") }
        return ArchiveQueryRules.dayKeyRange(for: ArchiveFilter(
            period: period, customStartDate: customStartDate, customEndDate: customEndDate
        ), referenceDate: referenceDate)
    }
}

public struct ReviewDiscoveryRecord: Identifiable {
    public var review: DailyReview
    public var attachments: [DiaryAttachment]
    public var legacyFileNames: [String]
    public var bodyText: String
    public var id: String { review.dayKey }
    public var title: String {
        let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "이날의 회고" : title
    }
    public var photoCount: Int { attachments.count + legacyFileNames.count }
}

public struct ReviewDiscoveryPage {
    public var records: [ReviewDiscoveryRecord]
    public var nextBeforeDayKey: String?
    public var hasMore: Bool
}

public enum ReviewDiscoveryRules {
    @MainActor
    public static func records(
        reviews: [DailyReview], attachments: [DiaryAttachment], blocks: [DiaryBlock], query: String
    ) -> [ReviewDiscoveryRecord] {
        // A newer empty review is authoritative. Never revive an older contentful copy.
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
}

/// Pages over existing review dates, not over calendar days or task history.
@MainActor
public final class ReviewDiscoveryQueryService {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func page(
        filter: ReviewDiscoveryFilter, beforeDayKey: String? = nil,
        pageSize: Int = 30, referenceDate: Date = Date()
    ) async throws -> ReviewDiscoveryPage {
        let range = filter.range(referenceDate: referenceDate)
        let lower = range.lowerBound ?? "0000-01-01"
        let upper = range.upperBound
        var cursor = beforeDayKey ?? "9999-99-99"
        var records: [ReviewDiscoveryRecord] = []
        let pageSize = max(1, pageSize)
        while records.count < pageSize {
            try Swift.Task.checkCancellation()
            var descriptor = FetchDescriptor<DailyReview>(predicate: #Predicate {
                $0.supersededAt == nil && $0.dayKey >= lower && $0.dayKey <= upper && $0.dayKey < cursor
            }, sortBy: [SortDescriptor(\DailyReview.dayKey, order: .reverse)])
            descriptor.fetchLimit = 64
            let seed = try context.fetch(descriptor)
            guard let last = seed.last, let first = seed.first else {
                return ReviewDiscoveryPage(records: records, nextBeforeDayKey: nil, hasMore: false)
            }
            // Complete the boundary day so physical duplicates cannot split across pages.
            let reviews = try BoundedQueryService.archiveReviews(from: last.dayKey, through: first.dayKey, in: context)
            let ids = Array(Set(reviews.map(\.id)))
            let attachments = try BoundedQueryService.archiveAttachments(reviewIDs: ids, in: context)
            let blocks = try BoundedQueryService.archiveBlocks(reviewIDs: ids, in: context)
            let found = ReviewDiscoveryRules.records(
                reviews: reviews, attachments: attachments, blocks: blocks, query: filter.searchText
            )
            let remaining = pageSize - records.count
            records += found.prefix(remaining)
            cursor = found.count >= remaining ? found[remaining - 1].id : last.dayKey
            await Swift.Task.yield()
        }
        var probe = FetchDescriptor<DailyReview>(predicate: #Predicate {
            $0.supersededAt == nil && $0.dayKey >= lower && $0.dayKey <= upper && $0.dayKey < cursor
        })
        probe.fetchLimit = 1
        let hasMore = try !context.fetch(probe).isEmpty
        return ReviewDiscoveryPage(records: records, nextBeforeDayKey: hasMore ? cursor : nil, hasMore: hasMore)
    }
}

@MainActor
@Observable
public final class ReviewDiscoverySession {
    public private(set) var records: [ReviewDiscoveryRecord] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public private(set) var errorMessage: String?
    public private(set) var loadedPageCount = 0
    @ObservationIgnored private let page: @MainActor (ReviewDiscoveryFilter, String?) async throws -> ReviewDiscoveryPage
    @ObservationIgnored private var requestedFilter = ReviewDiscoveryFilter()
    @ObservationIgnored private var appliedFilter = ReviewDiscoveryFilter()
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: Swift.Task<Void, Never>?

    public init(context: ModelContext) {
        let service = ReviewDiscoveryQueryService(context: context)
        page = { try await service.page(filter: $0, beforeDayKey: $1) }
    }
    init(page: @escaping @MainActor (ReviewDiscoveryFilter, String?) async throws -> ReviewDiscoveryPage) { self.page = page }
    deinit { pending?.cancel() }

    public func apply(_ filter: ReviewDiscoveryFilter, debounceSearch: Bool = false) {
        requestedFilter = filter
        load(pages: 1, appending: false, debounce: debounceSearch, clearing: true)
    }
    public func refreshPreservingDepth() {
        load(pages: requestedFilter == appliedFilter ? max(1, loadedPageCount) : 1,
             appending: false, clearing: requestedFilter != appliedFilter)
    }
    public func loadNextPage() {
        guard !isLoading, hasMore else { return }
        load(pages: 1, appending: true)
    }
    public func cancel() {
        pending?.cancel()
        generation += 1
        isLoading = false
    }
    func waitForPendingLoad() async { await pending?.value }

    private func load(pages: Int, appending: Bool, debounce: Bool = false, clearing: Bool = false) {
        pending?.cancel()
        generation += 1
        let ticket = generation
        let filter = requestedFilter
        if clearing { records = []; cursor = nil; loadedPageCount = 0; hasMore = false }
        isLoading = true
        errorMessage = nil
        pending = Swift.Task { [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Swift.Task.sleep(for: .milliseconds(300)) }
                var nextCursor = appending ? cursor : nil
                var result: [ReviewDiscoveryRecord] = []
                var more = false
                var count = 0
                for _ in 0..<pages {
                    let next = try await page(filter, nextCursor)
                    try Swift.Task.checkCancellation()
                    result += next.records
                    nextCursor = next.nextBeforeDayKey
                    more = next.hasMore
                    count += 1
                    if !more { break }
                }
                guard ticket == generation else { return }
                if appending {
                    let existing = Set(records.map(\.id))
                    records += result.filter { !existing.contains($0.id) }
                    loadedPageCount += count
                } else {
                    records = result
                    loadedPageCount = count
                }
                appliedFilter = filter
                cursor = nextCursor
                hasMore = more
                isLoading = false
            } catch is CancellationError {
                // The latest generation owns visible state.
            } catch {
                guard ticket == generation else { return }
                errorMessage = "회고를 불러오지 못했어요. 다시 시도해 주세요."
                isLoading = false
            }
        }
    }
}
