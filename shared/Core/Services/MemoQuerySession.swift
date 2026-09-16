import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class MemoQuerySession {
    public typealias PageLoader = @MainActor (ModelContext, String, MemoQueryCursor?) throws -> MemoQueryPage
    public private(set) var memos: [Memo] = []
    public private(set) var summaries: [UUID: MemoListSummary] = [:]
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let loadPage: PageLoader
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var requestedQuery = ""
    @ObservationIgnored private var loadedPageCount = 0
    @ObservationIgnored private var retryRefresh = false
    @ObservationIgnored private var nextCursor: MemoQueryCursor?
    @ObservationIgnored private var pendingSearch: Swift.Task<Void, Never>?

    public init(context: ModelContext, loadPage: PageLoader? = nil) {
        self.context = context
        self.loadPage = loadPage ?? { context, query, cursor in
            try MemoService.page(in: context, query: query, cursor: cursor)
        }
    }

    deinit {
        pendingSearch?.cancel()
    }

    public func apply(query: String, debounce: Bool) {
        requestedQuery = query
        pendingSearch?.cancel()
        guard debounce else {
            resetAndLoad(query: query)
            return
        }

        pendingSearch = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: .milliseconds(300))
                guard !Swift.Task.isCancelled else { return }
                self?.resetAndLoad(query: query)
            } catch {
                // A newer query superseded this request.
            }
        }
    }

    public func loadNextPage() {
        guard !isLoading, memos.isEmpty || hasMore else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try loadPage(context, query, nextCursor)
            let existingIDs = Set(memos.map(\.instanceID))
            memos.append(contentsOf: page.memos.filter { !existingIDs.contains($0.instanceID) })
            summaries.merge(page.summaries) { _, new in new }
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            loadedPageCount += 1
            retryRefresh = false
        } catch {
            errorMessage = "메모를 불러오지 못했습니다."
            hasMore = false
        }
    }

    public func refresh() {
        pendingSearch?.cancel()
        guard query == requestedQuery else {
            resetAndLoad(query: requestedQuery)
            return
        }
        // Keep the published rows until every requested page has loaded.
        // Refreshing an autosaved memo must not collapse a scrolled list.
        isLoading = true
        defer { isLoading = false }
        do {
            var rows: [Memo] = []
            var summaries: [UUID: MemoListSummary] = [:]
            var seen = Set<UUID>()
            var cursor: MemoQueryCursor?
            var more = true
            var pages = 0
            for _ in 0..<max(loadedPageCount, 1) {
                let page = try loadPage(context, query, cursor)
                rows.append(contentsOf: page.memos.filter { seen.insert($0.instanceID).inserted })
                summaries.merge(page.summaries) { _, new in new }
                cursor = page.nextCursor
                more = page.hasMore
                pages += 1
                if !more { break }
            }
            memos = rows
            self.summaries = summaries
            nextCursor = cursor
            hasMore = more
            loadedPageCount = pages
            errorMessage = nil
            retryRefresh = false
        } catch {
            errorMessage = "메모를 불러오지 못했습니다."
            retryRefresh = true
        }
    }

    public func retry() {
        if retryRefresh {
            refresh()
            return
        }
        hasMore = true
        loadNextPage()
    }
}

private extension MemoQuerySession {
    func resetAndLoad(query: String) {
        self.query = query
        loadedPageCount = 0
        retryRefresh = false
        memos = []
        summaries = [:]
        nextCursor = nil
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }
}
