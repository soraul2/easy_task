import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class MemoQuerySession {
    public private(set) var memos: [Memo] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var nextCursor: MemoQueryCursor?
    @ObservationIgnored private var pendingSearch: Swift.Task<Void, Never>?

    public init(context: ModelContext) {
        self.context = context
    }

    deinit {
        pendingSearch?.cancel()
    }

    public func apply(query: String, debounce: Bool) {
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
            let page = try MemoService.page(
                in: context,
                query: query,
                cursor: nextCursor
            )
            let existingIDs = Set(memos.map(\.instanceID))
            memos.append(contentsOf: page.memos.filter { !existingIDs.contains($0.instanceID) })
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = "메모를 불러오지 못했습니다."
            hasMore = false
        }
    }

    public func refresh() {
        resetAndLoad(query: query)
    }

    public func retry() {
        refresh()
    }
}

private extension MemoQuerySession {
    func resetAndLoad(query: String) {
        self.query = query
        memos = []
        nextCursor = nil
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }
}
