import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class ArchiveQuerySession {
    public private(set) var records: [ArchiveDayRecord] = []
    public private(set) var attachments: [DiaryAttachment] = []
    public private(set) var blocks: [DiaryBlock] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public private(set) var errorMessage: String?
    public private(set) var loadedPageCount = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var appliedFilter = ArchiveFilter()
    @ObservationIgnored private var nextBeforeDayKey: String?
    @ObservationIgnored private var pendingSearch: Swift.Task<Void, Never>?

    public init(context: ModelContext) {
        self.context = context
    }

    deinit {
        pendingSearch?.cancel()
    }

    public func apply(
        _ filter: ArchiveFilter,
        debounceSearch: Bool
    ) {
        pendingSearch?.cancel()

        guard debounceSearch else {
            resetAndLoad(filter)
            return
        }

        pendingSearch = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: .milliseconds(300))
                guard !Swift.Task.isCancelled else { return }
                self?.resetAndLoad(filter)
            } catch {
                // A newer search superseded this request.
            }
        }
    }

    public func loadNextPage() {
        guard !isLoading, loadedPageCount == 0 || hasMore else { return }
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }
        do {
            let page = try BoundedQueryService.archivePage(
                in: context,
                filter: appliedFilter,
                beforeDayKey: nextBeforeDayKey
            )
            append(page)
            nextBeforeDayKey = page.nextBeforeDayKey
            hasMore = page.hasMore
            if !page.records.isEmpty {
                loadedPageCount += 1
            }
        } catch {
            errorMessage = "기록을 불러오지 못했습니다."
            hasMore = false
        }
    }

    public func refreshPreservingDepth() {
        pendingSearch?.cancel()
        let pagesToReload = max(loadedPageCount, 1)
        clearResults()

        for _ in 0..<pagesToReload {
            loadNextPage()
            if !hasMore { break }
        }
    }

    public func retry() {
        if records.isEmpty {
            clearResults()
            loadNextPage()
        } else {
            refreshPreservingDepth()
        }
    }
}

private extension ArchiveQuerySession {
    func resetAndLoad(_ filter: ArchiveFilter) {
        appliedFilter = filter
        clearResults()
        loadNextPage()
    }

    func clearResults() {
        records = []
        attachments = []
        blocks = []
        nextBeforeDayKey = nil
        hasMore = true
        errorMessage = nil
        loadedPageCount = 0
    }

    func append(_ page: ArchiveQueryPage) {
        let existingDayKeys = Set(records.map(\.dayKey))
        records.append(contentsOf: page.records.filter {
            !existingDayKeys.contains($0.dayKey)
        })
        attachments = merged(
            current: attachments,
            incoming: page.attachments,
            keyPath: \.instanceID
        )
        blocks = merged(
            current: blocks,
            incoming: page.blocks,
            keyPath: \.instanceID
        )
    }

    func merged<Model, Key: Hashable>(
        current: [Model],
        incoming: [Model],
        keyPath: KeyPath<Model, Key>
    ) -> [Model] {
        var seen = Set(current.map { $0[keyPath: keyPath] })
        return current + incoming.filter {
            seen.insert($0[keyPath: keyPath]).inserted
        }
    }
}
