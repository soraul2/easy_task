import Foundation
import SwiftData

public struct MemoQueryPage {
    public var memos: [Memo]
    public var summaries: [UUID: MemoListSummary]
    public var nextCursor: MemoQueryCursor?
    public var hasMore: Bool

    public init(memos: [Memo], nextCursor: MemoQueryCursor?, hasMore: Bool,
                summaries: [UUID: MemoListSummary] = [:]) {
        self.memos = memos
        self.summaries = summaries
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct MemoQueryCursor: Equatable, Sendable {
    public var scansPinned: Bool
    public var pinnedOffset: Int
    public var regularOffset: Int

    public init(
        scansPinned: Bool = true,
        pinnedOffset: Int = 0,
        regularOffset: Int = 0
    ) {
        self.scansPinned = scansPinned
        self.pinnedOffset = pinnedOffset
        self.regularOffset = regularOffset
    }
}

public enum MemoService {
    public static let pageSize = 40
    static let scanBatchSize = 100
    // Start with the small fetch for dense results. Sparse searches amortize
    // relationship reads after actually examining an initial batch of rows.
    static let searchScanBatchSize = 512

    @MainActor
    @discardableResult
    public static func save(
        memo: Memo?,
        content: String,
        now: Date = Date(),
        in context: ModelContext
    ) throws -> Memo? {
        if memo == nil, MemoRules.isBlank(content) {
            return nil
        }
        if let memo, memo.content == content {
            return memo
        }

        return try PersistenceCommandService.perform(in: context) {
            if let memo {
                memo.content = content
                memo.updatedAt = now
                return memo
            }

            let memo = Memo(content: content, createdAt: now, updatedAt: now)
            context.insert(memo)
            return memo
        }
    }

    @MainActor
    @discardableResult
    public static func saveComposite(
        memo: Memo?,
        content: String,
        preferredMode: MemoEditorMode,
        drawingData: Data,
        checklistDrafts: [MemoChecklistDraft],
        now: Date = Date(),
        in context: ModelContext
    ) throws -> Memo? {
        let normalizedChecklist = MemoChecklistService.normalizedDrafts(checklistDrafts)
        let hasContent = !MemoRules.isBlank(content) ||
            !drawingData.isEmpty ||
            !normalizedChecklist.isEmpty
        guard memo != nil || hasContent else { return nil }

        return try PersistenceCommandService.perform(in: context) {
            let target: Memo
            if let memo {
                target = memo
            } else {
                target = Memo(
                    content: content,
                    preferredMode: preferredMode,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(target)
            }

            var changed = false
            if target.content != content {
                target.content = content
                changed = true
            }
            if target.preferredModeRawValue != preferredMode.rawValue {
                target.preferredModeRawValue = preferredMode.rawValue
                changed = true
            }
            changed = try MemoDrawingService.replace(
                for: target.id,
                with: drawingData,
                in: context,
                now: now
            ) || changed
            changed = try MemoChecklistService.replace(
                for: target.id,
                with: normalizedChecklist,
                in: context,
                now: now
            ) || changed
            if changed {
                target.updatedAt = now
            }
            return target
        }
    }

    @MainActor
    public static func setPinned(
        _ isPinned: Bool,
        for memo: Memo,
        now: Date = Date(),
        in context: ModelContext
    ) throws {
        guard memo.isPinned != isPinned else { return }
        try PersistenceCommandService.perform(in: context) {
            memo.isPinned = isPinned
            memo.updatedAt = now
        }
    }

    @MainActor
    public static func delete(_ memo: Memo, in context: ModelContext) throws {
        try PersistenceCommandService.perform(in: context) {
            let memoID = memo.id
            for drawing in try context.fetch(FetchDescriptor<MemoDrawing>(
                predicate: #Predicate<MemoDrawing> { drawing in
                    drawing.memoId == memoID
                }
            )) {
                context.delete(drawing)
            }
            for item in try context.fetch(FetchDescriptor<MemoChecklistItem>(
                predicate: #Predicate<MemoChecklistItem> { item in
                    item.memoId == memoID
                }
            )) {
                context.delete(item)
            }
            context.delete(memo)
        }
    }

    @MainActor
    public static func page(
        in context: ModelContext,
        query: String,
        cursor: MemoQueryCursor? = nil
    ) throws -> MemoQueryPage {
        var scan = PageScan(query: query, cursor: cursor, in: context)
        while true {
            if let page = try scan.step(in: context) { return page }
        }
    }

    /// Internal opt-in reader. The session owns a version spanning all its pages.
    @MainActor
    static func cooperativePage(in context: ModelContext, query: String, cursor: MemoQueryCursor?,
                                checkpoint: MemoReadCheckpoint) async throws -> MemoQueryPage {
        try await checkpoint()
        var scan = PageScan(query: query, cursor: cursor, in: context, separatesFetchWork: true)
        while true {
            try await checkpoint()
            if let page = try scan.step(in: context) {
                try await checkpoint()
                return page
            }
        }
    }

    @MainActor
    private static func makePage(
        memos: [Memo], nextCursor: MemoQueryCursor?, hasMore: Bool, in context: ModelContext
    ) throws -> MemoQueryPage {
        let ids = memos.map(\.id)
        guard !ids.isEmpty else { return MemoQueryPage(memos: [], nextCursor: nextCursor, hasMore: hasMore) }
        let checklists = Dictionary(grouping: try checklistItems(memoIDs: ids, in: context), by: \.memoId)
        let drawings = Dictionary(grouping: try drawingMetadata(memoIDs: ids, in: context), by: \.memoID)
        let summaries = Dictionary(uniqueKeysWithValues: memos.map { memo in
            (memo.instanceID, MemoListSummary(content: memo.content, preferred: MemoRules.mode(for: memo),
                checklist: (checklists[memo.id] ?? []).map(MemoChecklistDraft.init(item:)),
                drawingUpdatedAt: drawings[memo.id]?.map(\.updatedAt).max()))
        })
        return MemoQueryPage(memos: memos, nextCursor: nextCursor, hasMore: hasMore, summaries: summaries)
    }

    @MainActor
    private static func pendingModels<Model: PersistentModel>(in context: ModelContext) -> [PersistentIdentifier: Model] {
        var result: [PersistentIdentifier: Model] = [:]
        for model in context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray {
            if let model = model as? Model { result[model.persistentModelID] = model }
        }
        return result
    }

    @MainActor
    private static func deletedIDs<Model: PersistentModel>(of type: Model.Type, in context: ModelContext) -> Set<PersistentIdentifier> {
        Set(context.deletedModelsArray.compactMap { ($0 as? Model)?.persistentModelID })
    }

    private struct DrawingSummaryMetadata {
        let physicalID: PersistentIdentifier
        let memoID: UUID
        let updatedAt: Date
    }

    @MainActor
    private static func drawingMetadata(memoIDs: [UUID], in context: ModelContext) throws -> [DrawingSummaryMetadata] {
        let pending: [PersistentIdentifier: MemoDrawing] = pendingModels(in: context)
        let deleted = deletedIDs(of: MemoDrawing.self, in: context)
        var descriptor = FetchDescriptor<MemoDrawing>(predicate: #Predicate {
            memoIDs.contains($0.memoId) && $0.supersededAt == nil
        })
        descriptor.propertiesToFetch = [\.memoId, \.updatedAt]
        // A dirty identifier reader's model(for:) fallback cannot carry this projection.
        // Use a short-lived clean context, and copy only metadata values out of it.
        let saved: [DrawingSummaryMetadata]
        if context.hasChanges {
            let metadataContext = ModelContext(context.container)
            metadataContext.autosaveEnabled = false
            saved = try SavedModelPageReader.read(descriptor, in: metadataContext,
                excluding: Set(pending.keys).union(deleted)).rows.map {
                DrawingSummaryMetadata(physicalID: $0.persistentModelID, memoID: $0.memoId, updatedAt: $0.updatedAt)
            }
            withExtendedLifetime(metadataContext) {}
        } else {
            saved = try SavedModelPageReader.read(descriptor, in: context).rows.map {
                DrawingSummaryMetadata(physicalID: $0.persistentModelID, memoID: $0.memoId, updatedAt: $0.updatedAt)
            }
        }
        let overlay = pending.values.filter {
            !deleted.contains($0.persistentModelID) && $0.supersededAt == nil && memoIDs.contains($0.memoId)
        }.map {
            DrawingSummaryMetadata(physicalID: $0.persistentModelID, memoID: $0.memoId, updatedAt: $0.updatedAt)
        }
        return saved + overlay
    }

    @MainActor
    private static func checklistItems(memoIDs: [UUID], in context: ModelContext) throws -> [MemoChecklistItem] {
        guard !memoIDs.isEmpty else { return [] }
        let pending: [PersistentIdentifier: MemoChecklistItem] = pendingModels(in: context)
        let deleted = deletedIDs(of: MemoChecklistItem.self, in: context)
        let saved = try SavedModelPageReader.read(MemoChecklistService.descriptor(memoIDs: memoIDs),
            in: context, excluding: Set(pending.keys)).rows
        let overlay = pending.values.filter {
            !deleted.contains($0.persistentModelID) && $0.supersededAt == nil && memoIDs.contains($0.memoId)
        }
        guard !overlay.isEmpty else { return saved }
        // Search joins child titles with newlines, so descriptor order is meaningful.
        return (saved + overlay).sorted {
            if $0.memoId != $1.memoId { return $0.memoId.uuidString < $1.memoId.uuidString }
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.instanceID.uuidString < $1.instanceID.uuidString
        }
    }

    private static func precedes(_ lhs: Memo, _ rhs: Memo) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private struct PageScan {
        let normalizedQuery: String
        var cursor: MemoQueryCursor
        let pendingParents: [Memo]
        let excludedParentIDs: Set<PersistentIdentifier>
        let replaysMergedOffset: Bool
        let separatesFetchWork: Bool
        var needsChecklistFetch = false
        var phasePending: [Memo]
        var pendingIndex = 0
        var savedOffset: Int
        var remainingSkip: Int
        var savedFinished = false
        var matches: [Memo] = []
        var inspectedCount = 0
        var batch: [Memo] = []
        var batchIndex = 0
        var checklistByMemoID: [UUID: [MemoChecklistItem]] = [:]

        @MainActor
        init(query: String, cursor: MemoQueryCursor?, in context: ModelContext,
             separatesFetchWork: Bool = false) {
            self.separatesFetchWork = separatesFetchWork
            normalizedQuery = MemoRules.normalizedSearchText(query)
            let cursor = cursor ?? MemoQueryCursor()
            self.cursor = cursor
            let pending: [PersistentIdentifier: Memo] = MemoService.pendingModels(in: context)
            let deleted = MemoService.deletedIDs(of: Memo.self, in: context)
            excludedParentIDs = Set(pending.keys)
            let activeParents = pending.values.filter {
                !deleted.contains($0.persistentModelID) && $0.supersededAt == nil
            }.sorted(by: MemoService.precedes)
            pendingParents = activeParents
            phasePending = activeParents.filter { $0.isPinned == cursor.scansPinned }
            let replay = !pending.isEmpty
            replaysMergedOffset = replay
            let offset = cursor.scansPinned ? cursor.pinnedOffset : cursor.regularOffset
            savedOffset = replay ? 0 : offset
            remainingSkip = replay ? offset : 0
        }

        /// Fetches at most one saved batch and consumes at most 100 merged rows.
        /// Dirty parent offsets describe the merged order, so replay its bounded prefix.
        /// Clean/child-only reads retain the direct saved-offset fast path.
        @MainActor
        mutating func step(in context: ModelContext) throws -> MemoQueryPage? {
            if batchIndex == batch.count && !savedFinished {
                let requestedBatchSize = !normalizedQuery.isEmpty && inspectedCount >= MemoService.scanBatchSize
                    ? MemoService.searchScanBatchSize : MemoService.scanBatchSize
                let pinned = cursor.scansPinned
                var descriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate<Memo> { $0.supersededAt == nil && $0.isPinned == pinned },
                    sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse),
                             SortDescriptor(\Memo.createdAt, order: .reverse), SortDescriptor(\Memo.instanceID)])
                descriptor.fetchOffset = savedOffset
                descriptor.fetchLimit = requestedBatchSize
                let saved = try SavedModelPageReader.read(descriptor, in: context, excluding: excludedParentIDs)
                savedOffset += saved.fetchedCount
                savedFinished = saved.fetchedCount < requestedBatchSize
                batch = saved.rows
                batchIndex = 0
                if !normalizedQuery.isEmpty {
                    if separatesFetchWork {
                        needsChecklistFetch = !batch.isEmpty
                        // A saved parent fetch, its child fetch and matching must
                        // not all share one cooperative main-actor slice.
                        if needsChecklistFetch { return nil }
                    } else {
                        let ids = batch.map(\.id)
                        checklistByMemoID = Dictionary(grouping: try MemoService.checklistItems(memoIDs: ids, in: context), by: \.memoId)
                    }
                }
                // All rows may have been excluded pending parents. Advance by the raw
                // saved count and yield before fetching again; EOF is not rows.count.
                if batch.isEmpty && !savedFinished { return nil }
            }

            if needsChecklistFetch {
                let ids = batch.map(\.id)
                checklistByMemoID = Dictionary(grouping: try MemoService.checklistItems(memoIDs: ids, in: context), by: \.memoId)
                needsChecklistFetch = false
                return nil
            }

            if !normalizedQuery.isEmpty {
                // Only the next 100 pending parents can be consumed in this step.
                // Do not expand the child descriptor to every remaining pending parent.
                let ids = phasePending.dropFirst(pendingIndex).prefix(MemoService.scanBatchSize).map(\.id)
                    .filter { checklistByMemoID[$0] == nil }
                if !ids.isEmpty {
                    let groups = Dictionary(grouping: try MemoService.checklistItems(memoIDs: ids, in: context), by: \.memoId)
                    for id in ids { checklistByMemoID[id] = groups[id] ?? [] }
                }
            }

            for _ in 0..<MemoService.scanBatchSize {
                // A later saved batch may precede pending rows. Fetch it before choosing.
                if batchIndex == batch.count && !savedFinished { break }
                let saved = batchIndex < batch.count ? batch[batchIndex] : nil
                let pending = pendingIndex < phasePending.count ? phasePending[pendingIndex] : nil
                let memo: Memo
                if let pending, saved == nil || MemoService.precedes(pending, saved!) {
                    memo = pending
                    pendingIndex += 1
                } else if let saved {
                    memo = saved
                    batchIndex += 1
                } else {
                    return try finishPhase(in: context)
                }
                inspectedCount += 1
                if remainingSkip > 0 {
                    remainingSkip -= 1
                    continue
                }
                if cursor.scansPinned { cursor.pinnedOffset += 1 } else { cursor.regularOffset += 1 }
                if MemoRules.matches(memo,
                    checklistTitles: (checklistByMemoID[memo.id] ?? []).map(\.title),
                    normalizedQuery: normalizedQuery) {
                    matches.append(memo)
                    if matches.count == MemoService.pageSize {
                        return try MemoService.makePage(memos: matches, nextCursor: cursor, hasMore: true, in: context)
                    }
                }
            }
            if batchIndex == batch.count && savedFinished && pendingIndex == phasePending.count {
                return try finishPhase(in: context)
            }
            return nil
        }

        @MainActor
        private mutating func finishPhase(in context: ModelContext) throws -> MemoQueryPage? {
            guard cursor.scansPinned else {
                return try MemoService.makePage(memos: matches, nextCursor: nil, hasMore: false, in: context)
            }
            cursor.scansPinned = false
            phasePending = pendingParents.filter { !$0.isPinned }
            pendingIndex = 0
            savedOffset = replaysMergedOffset ? 0 : cursor.regularOffset
            remainingSkip = replaysMergedOffset ? cursor.regularOffset : 0
            savedFinished = false
            batch = []
            batchIndex = 0
            checklistByMemoID = [:]
            needsChecklistFetch = false
            return nil
        }
    }
}
