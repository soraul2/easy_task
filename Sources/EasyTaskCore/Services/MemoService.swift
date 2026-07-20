import Foundation
import SwiftData

public struct MemoQueryPage {
    public var memos: [Memo]
    public var nextCursor: MemoQueryCursor?
    public var hasMore: Bool

    public init(memos: [Memo], nextCursor: MemoQueryCursor?, hasMore: Bool) {
        self.memos = memos
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

        while matches.count < pageSize {
            let pinned = cursor.scansPinned
            let offset = pinned ? cursor.pinnedOffset : cursor.regularOffset
            var descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate<Memo> { memo in
                    memo.supersededAt == nil && memo.isPinned == pinned
                },
                sortBy: [
                    SortDescriptor(\Memo.updatedAt, order: .reverse),
                    SortDescriptor(\Memo.createdAt, order: .reverse)
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
                return MemoQueryPage(memos: matches, nextCursor: nil, hasMore: false)
            }

            for memo in batch {
                if cursor.scansPinned {
                    cursor.pinnedOffset += 1
                } else {
                    cursor.regularOffset += 1
                }
                if MemoRules.matches(memo, query: query) {
                    matches.append(memo)
                    if matches.count == pageSize {
                        return MemoQueryPage(
                            memos: matches,
                            nextCursor: cursor,
                            hasMore: true
                        )
                    }
                }
            }

            if batch.count < scanBatchSize {
                if cursor.scansPinned {
                    cursor.scansPinned = false
                } else {
                    return MemoQueryPage(memos: matches, nextCursor: nil, hasMore: false)
                }
            }
        }

        return MemoQueryPage(
            memos: matches,
            nextCursor: cursor,
            hasMore: true
        )
    }
}
