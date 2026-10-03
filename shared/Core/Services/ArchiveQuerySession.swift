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

    @ObservationIgnored private let changes: PersistenceViewRevision
    @ObservationIgnored private var loadedRevision: Int?
    @ObservationIgnored private var loadedDayKey: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let dailyService: DailyActivityQueryService
    @ObservationIgnored private var appliedFilter = ArchiveFilter()
    @ObservationIgnored private var requestedFilter = ArchiveFilter()
    @ObservationIgnored private var nextBeforeDayKey: String?
    @ObservationIgnored private var pendingSearch: Swift.Task<Void, Never>?
    @ObservationIgnored private var pendingLoad: Swift.Task<Void, Never>?
    @ObservationIgnored private var generation = 0
#if DEBUG
    @ObservationIgnored private var failNextPreviewLoad =
        ProcessInfo.processInfo.arguments.contains("--ui-testing-archive-fail-once")
    private enum PreviewFailure: Error { case unavailable }
#endif

    public init(context: ModelContext, dailyService: DailyActivityQueryService? = nil) {
        self.changes = PersistenceViewRevision(context: context, domains: [.tasks, .reviews])
        self.context = context
        self.dailyService = dailyService ?? DailyActivityQueryService(context: context)
    }

    deinit {
        pendingSearch?.cancel()
        pendingLoad?.cancel()
    }

    public func apply(
        _ filter: ArchiveFilter,
        debounceSearch: Bool
    ) {
        requestedFilter = filter
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
        if appliedFilter.contentMode == .dailyActivity {
            loadDaily(pages: 1, appending: true)
            return
        }
        if loadedPageCount == 0 { rememberRevision() }
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

    public func refreshIfNeeded() {
        guard loadedRevision != changes.value || loadedDayKey != DayKey.today
                || requestedFilter != appliedFilter || errorMessage != nil
                || (appliedFilter.contentMode == .dailyActivity && context.hasChanges) else { return }
        refreshPreservingDepth()
    }

    public func refreshPreservingDepth() {
        pendingSearch?.cancel()
        if requestedFilter != appliedFilter {
            resetAndLoad(requestedFilter)
            return
        }
        let pagesToReload = max(loadedPageCount, 1)
        if appliedFilter.contentMode == .dailyActivity {
            loadDaily(pages: pagesToReload, appending: false)
            return
        }
        let previousRecords = records
        let previousAttachments = attachments
        let previousBlocks = blocks
        let previousCursor = nextBeforeDayKey
        let previousHasMore = hasMore
        let previousPageCount = loadedPageCount
        clearResults()

        for _ in 0..<pagesToReload {
            loadNextPage()
            if !hasMore { break }
        }
        if errorMessage != nil, !previousRecords.isEmpty {
            records = previousRecords
            attachments = previousAttachments
            blocks = previousBlocks
            nextBeforeDayKey = previousCursor
            hasMore = previousHasMore
            loadedPageCount = previousPageCount
        }
    }

    public func retry() {
        refreshPreservingDepth()
    }

    public func cancel() {
        if isLoading { loadedRevision = nil }
        pendingSearch?.cancel()
        pendingLoad?.cancel()
        generation += 1
        isLoading = false
    }

    public func makeDaySession() -> ArchiveQuerySession {
        ArchiveQuerySession(context: context, dailyService: dailyService)
    }
}

private extension ArchiveQuerySession {
    func rememberRevision() {
        loadedRevision = changes.value
        loadedDayKey = DayKey.today
    }

    func resetAndLoad(_ filter: ArchiveFilter) {
        pendingLoad?.cancel()
        generation += 1
        isLoading = false
        appliedFilter = filter
        clearResults()
        loadNextPage()
    }

    func loadDaily(pages: Int, appending: Bool) {
        pendingLoad?.cancel()
        generation += 1
        let requestGeneration = generation
        let requestRevision = changes.value
        let requestDayKey = DayKey.today
        let filter = appliedFilter
        let canAppend = appending && loadedRevision == requestRevision && loadedDayKey == requestDayKey
        let before = canAppend ? nextBeforeDayKey : nil
        let pagesToRead = appending && !canAppend ? max(loadedPageCount + 1, 1) : pages
        isLoading = true
        errorMessage = nil
        pendingLoad = Swift.Task { [weak self] in
            guard let self else { return }
            do {
#if DEBUG
                if failNextPreviewLoad {
                    failNextPreviewLoad = false
                    throw PreviewFailure.unavailable
                }
#endif
                var result: [ArchiveQueryPage] = []
                var cursor = before
                for _ in 0..<pagesToRead {
                    let page = try await dailyService.page(filter: filter, beforeDayKey: cursor)
                    try Swift.Task.checkCancellation()
                    result.append(page)
                    cursor = page.nextBeforeDayKey
                    if !page.hasMore { break }
                }
                guard requestGeneration == generation else { return }
                guard requestRevision == changes.value, requestDayKey == DayKey.today
                else { throw DailyActivityReadInvalidated.changed }
                if !canAppend { clearResults() }
                for page in result {
                    append(page)
                    nextBeforeDayKey = page.nextBeforeDayKey
                    hasMore = page.hasMore
                    if !page.records.isEmpty { loadedPageCount += 1 }
                }
                // A dirty overlay must be reread after rollback even without a save notification.
                loadedRevision = context.hasChanges ? nil : requestRevision
                loadedDayKey = requestDayKey
                isLoading = false
                pendingLoad = nil
            } catch is CancellationError {
                guard requestGeneration == generation else { return }
                loadedRevision = nil
                isLoading = false
                pendingLoad = nil
            } catch {
                guard requestGeneration == generation else { return }
                loadedRevision = nil
                errorMessage = "하루 기록을 불러오지 못했습니다. 다시 시도해 주세요."
                if records.isEmpty { hasMore = false }
                isLoading = false
                pendingLoad = nil
            }
        }
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
