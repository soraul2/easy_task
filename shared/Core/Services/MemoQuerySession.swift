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
    @ObservationIgnored private var pendingLoad: Swift.Task<Void, Never>?
    @ObservationIgnored private var cooperativeLoader: MemoCooperativePageLoader?
    @ObservationIgnored private var readValidity: MemoReadValidity?
    @ObservationIgnored private var publishedVersion: MemoReadVersion?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingDepth = 0

    public init(context: ModelContext, loadPage: PageLoader? = nil) {
        self.context = context
        self.loadPage = loadPage ?? { context, query, cursor in
            try MemoService.page(in: context, query: query, cursor: cursor)
        }
    }

    /// Explicit UI opt-in. The existing initializer and PageLoader remain synchronous.
    public convenience init(context: ModelContext, cooperative: Bool) {
        self.init(context: context)
        if cooperative {
            cooperativeLoader = { context, query, cursor, checkpoint in
                try await MemoService.cooperativePage(in: context, query: query, cursor: cursor,
                                                      checkpoint: checkpoint)
            }
            readValidity = MemoReadValidity(context: context)
        }
    }

    convenience init(context: ModelContext, cooperativeLoader: @escaping MemoCooperativePageLoader,
                     additionalRevision: @escaping @MainActor () -> Int = { 0 }) {
        self.init(context: context)
        self.cooperativeLoader = cooperativeLoader
        readValidity = MemoReadValidity(context: context, additionalRevision: additionalRevision)
    }

    deinit {
        pendingSearch?.cancel()
        pendingLoad?.cancel()
    }

    public func apply(query: String, debounce: Bool) {
        requestedQuery = query
        pendingSearch?.cancel()
        if cooperativeLoader != nil { cancelRead() }
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
        if cooperativeLoader != nil {
            guard query == requestedQuery else {
                resetAndLoad(query: requestedQuery)
                return
            }
            startCooperativeRead(appending: true, depth: max(loadedPageCount + 1, 1))
            return
        }
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
        if cooperativeLoader != nil {
            startCooperativeRead(appending: false, depth: max(max(loadedPageCount, pendingDepth), 1))
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

    /// Retains published rows and refresh depth; editor drafts are owned separately.
    public func cancel() {
        pendingSearch?.cancel()
        cancelRead()
    }

    var readPosition: (depth: Int, cursor: MemoQueryCursor?) { (loadedPageCount, nextCursor) }
}

private extension MemoQuerySession {
    func resetAndLoad(query: String) {
        if cooperativeLoader != nil { cancelRead() }
        self.query = query
        loadedPageCount = 0
        pendingDepth = 0
        publishedVersion = nil
        retryRefresh = false
        memos = []
        summaries = [:]
        nextCursor = nil
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }

    func cancelRead() {
        pendingLoad?.cancel()
        pendingLoad = nil
        generation &+= 1
        isLoading = false
    }

    func startCooperativeRead(appending: Bool, depth: Int) {
        guard let loader = cooperativeLoader, let validity = readValidity else { return }
        cancelRead()
        let requestGeneration = generation
        let requestQuery = query
        let context = context
        let targetDepth = max(depth, 1)
        let published: MemoCooperativeReadResult?
        if appending, let version = publishedVersion {
            published = MemoCooperativeReadResult(memos: memos, summaries: summaries,
                nextCursor: nextCursor, hasMore: hasMore, depth: loadedPageCount, version: version)
        } else { published = nil }
        pendingDepth = targetDepth
        isLoading = true
        errorMessage = nil
        // No strong session reference spans an await; dropping the session cancels this task.
        pendingLoad = Swift.Task { [weak self] in
            do {
                let result = try await MemoCooperativeRead.run(context: context, query: requestQuery,
                    targetDepth: targetDepth, appendTo: published, validity: validity, loader: loader)
                self?.finishCooperativeRead(result, generation: requestGeneration)
            } catch is CancellationError {
                // Only the current generation can publish rows, errors or loading state.
            } catch {
                self?.failCooperativeRead(generation: requestGeneration, appending: appending)
            }
        }
    }

    func finishCooperativeRead(_ result: MemoCooperativeReadResult, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        guard readValidity?.capture() == result.version else {
            startCooperativeRead(appending: false, depth: max(result.depth, pendingDepth))
            return
        }
        memos = result.memos
        summaries = result.summaries
        nextCursor = result.nextCursor
        hasMore = result.hasMore
        loadedPageCount = result.depth
        publishedVersion = result.version
        pendingDepth = 0
        errorMessage = nil
        retryRefresh = false
        isLoading = false
        pendingLoad = nil
    }

    func failCooperativeRead(generation requestGeneration: Int, appending: Bool) {
        guard requestGeneration == generation else { return }
        errorMessage = "메모를 불러오지 못했습니다."
        retryRefresh = !appending
        if appending { hasMore = false }
        isLoading = false
        pendingLoad = nil
    }
}
