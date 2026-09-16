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
        var cursor = cursor ?? MemoQueryCursor()
        var matches: [Memo] = []

        let normalizedQuery = MemoRules.normalizedSearchText(query)
        while matches.count < pageSize {
            let pinned = cursor.scansPinned
            let offset = pinned ? cursor.pinnedOffset : cursor.regularOffset
            var descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { memo in
                    memo.supersededAt == nil && memo.isPinned == pinned
                },
                sortBy: [
                    SortDescriptor(\Memo.updatedAt, order: .reverse),
                    SortDescriptor(\Memo.createdAt, order: .reverse),
                    SortDescriptor(\Memo.instanceID)
                ]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = scanBatchSize
            let batch: [Memo] = try context.fetch(descriptor)

            if batch.isEmpty {
                if cursor.scansPinned {
                    cursor.scansPinned = false
                    continue
                }
                return try makePage(memos: matches, nextCursor: nil, hasMore: false, in: context)
            }

            let checklistByMemoID: [UUID: [MemoChecklistItem]]
            if normalizedQuery.isEmpty {
                checklistByMemoID = [:]
            } else {
                let memoIDs = batch.map(\.id)
                checklistByMemoID = Dictionary(
                    grouping: try context.fetch(
                        MemoChecklistService.descriptor(memoIDs: memoIDs)
                    ),
                    by: \.memoId
                )
            }

            for memo in batch {
                if cursor.scansPinned {
                    cursor.pinnedOffset += 1
                } else {
                    cursor.regularOffset += 1
                }
                if MemoRules.matches(
                    memo,
                    checklistTitles: (checklistByMemoID[memo.id] ?? []).map(\.title),
                    normalizedQuery: normalizedQuery
                ) {
                    matches.append(memo)
                    if matches.count == pageSize {
                        return try makePage(memos: matches, nextCursor: cursor, hasMore: true, in: context)
                    }
                }
            }

            if batch.count < scanBatchSize {
                if cursor.scansPinned {
                    cursor.scansPinned = false
                } else {
                    return try makePage(memos: matches, nextCursor: nil, hasMore: false, in: context)
                }
            }
        }

        return try makePage(memos: matches, nextCursor: cursor, hasMore: true, in: context)
    }

    @MainActor
    private static func makePage(
        memos: [Memo], nextCursor: MemoQueryCursor?, hasMore: Bool, in context: ModelContext
    ) throws -> MemoQueryPage {
        let ids = memos.map(\.id)
        guard !ids.isEmpty else { return MemoQueryPage(memos: [], nextCursor: nextCursor, hasMore: hasMore) }
        let checklists = Dictionary(grouping: try context.fetch(
            MemoChecklistService.descriptor(memoIDs: ids)
        ), by: \.memoId)
        var drawingDescriptor = FetchDescriptor<MemoDrawing>(predicate: #Predicate {
            ids.contains($0.memoId) && $0.supersededAt == nil
        })
        // Only load metadata for this page. Visible rows rasterize their drawing
        // on demand instead of loading every original canvas into the list.
        drawingDescriptor.propertiesToFetch = [\.memoId, \.updatedAt]
        let drawings = Dictionary(grouping: try context.fetch(drawingDescriptor), by: \.memoId)
        let summaries = Dictionary(uniqueKeysWithValues: memos.map { memo in
            (memo.instanceID, MemoListSummary(content: memo.content, preferred: MemoRules.mode(for: memo),
                checklist: (checklists[memo.id] ?? []).map(MemoChecklistDraft.init(item:)),
                drawingUpdatedAt: drawings[memo.id]?.map(\.updatedAt).max()))
        })
        return MemoQueryPage(memos: memos, nextCursor: nextCursor, hasMore: hasMore, summaries: summaries)
    }

}
