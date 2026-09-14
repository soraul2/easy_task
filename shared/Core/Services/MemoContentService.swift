import Foundation
import SwiftData

public enum MemoDrawingPreviewRules {
    public static let maximumPixelDimension = 1_800.0

    public static func scale(width: Double, height: Double) -> Double? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return min(2, maximumPixelDimension / max(width, height))
    }
}

public struct MemoChecklistDraft: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var order: Double

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        order: Double
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
    }

    public init(item: MemoChecklistItem) {
        self.init(
            id: item.id,
            title: item.title,
            isCompleted: item.isCompleted,
            order: item.order
        )
    }
}

public enum MemoDrawingService {
    public static let maximumDrawingSizeBytes = 10 * 1_024 * 1_024

    public enum DrawingError: LocalizedError, Equatable {
        case tooLarge(actualBytes: Int, maximumBytes: Int)

        public var errorDescription: String? {
            switch self {
            case .tooLarge(let actualBytes, let maximumBytes):
                "필기 데이터가 너무 큽니다. size=\(actualBytes), max=\(maximumBytes)"
            }
        }
    }

    public static func descriptor(memoID: UUID) -> FetchDescriptor<MemoDrawing> {
        FetchDescriptor(
            predicate: #Predicate<MemoDrawing> { drawing in
                drawing.memoId == memoID && drawing.supersededAt == nil
            },
            sortBy: [
                SortDescriptor(\MemoDrawing.updatedAt, order: .reverse),
                SortDescriptor(\MemoDrawing.instanceID)
            ]
        )
    }

    @MainActor
    public static func data(
        for memoID: UUID,
        in context: ModelContext
    ) throws -> Data {
        try context.fetch(descriptor(memoID: memoID)).first?.drawingData ?? Data()
    }

    @MainActor
    @discardableResult
    static func replace(
        for memoID: UUID,
        with data: Data,
        in context: ModelContext,
        now: Date
    ) throws -> Bool {
        guard data.count <= maximumDrawingSizeBytes else {
            throw DrawingError.tooLarge(
                actualBytes: data.count,
                maximumBytes: maximumDrawingSizeBytes
            )
        }

        let targetID = memoID
        let candidates = try context.fetch(FetchDescriptor<MemoDrawing>(
            predicate: #Predicate<MemoDrawing> { drawing in
                drawing.memoId == targetID
            }
        ))
        let active = candidates
            .filter { $0.supersededAt == nil }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }

        guard !data.isEmpty else {
            guard !candidates.isEmpty else { return false }
            for drawing in candidates {
                context.delete(drawing)
            }
            return true
        }

        if let winner = active.first {
            var changed = winner.drawingData != data
            if changed {
                winner.drawingData = data
                winner.updatedAt = now
            }
            for drawing in active where drawing !== winner {
                drawing.supersededAt = now
                changed = true
            }
            return changed
        }

        context.insert(MemoDrawing(
            memoId: memoID,
            drawingData: data,
            createdAt: now,
            updatedAt: now
        ))
        return true
    }
}

public enum MemoChecklistService {
    public static func descriptor(memoID: UUID) -> FetchDescriptor<MemoChecklistItem> {
        FetchDescriptor(
            predicate: #Predicate<MemoChecklistItem> { item in
                item.memoId == memoID && item.supersededAt == nil
            },
            sortBy: [
                SortDescriptor(\MemoChecklistItem.order),
                SortDescriptor(\MemoChecklistItem.createdAt),
                SortDescriptor(\MemoChecklistItem.instanceID)
            ]
        )
    }

    public static func descriptor(memoIDs: [UUID]) -> FetchDescriptor<MemoChecklistItem> {
        FetchDescriptor(
            predicate: #Predicate<MemoChecklistItem> { item in
                memoIDs.contains(item.memoId) && item.supersededAt == nil
            },
            sortBy: [
                SortDescriptor(\MemoChecklistItem.memoId),
                SortDescriptor(\MemoChecklistItem.order),
                SortDescriptor(\MemoChecklistItem.createdAt),
                SortDescriptor(\MemoChecklistItem.instanceID)
            ]
        )
    }

    @MainActor
    public static func drafts(
        for memoID: UUID,
        in context: ModelContext
    ) throws -> [MemoChecklistDraft] {
        try context.fetch(descriptor(memoID: memoID)).map(MemoChecklistDraft.init(item:))
    }

    public static func progress(in drafts: [MemoChecklistDraft]) -> ChecklistProgress {
        let normalized = normalizedDrafts(drafts)
        return ChecklistProgress(
            completedCount: normalized.filter(\.isCompleted).count,
            totalCount: normalized.count
        )
    }

    @MainActor
    @discardableResult
    static func replace(
        for memoID: UUID,
        with drafts: [MemoChecklistDraft],
        in context: ModelContext,
        now: Date
    ) throws -> Bool {
        let normalized = normalizedDrafts(drafts)
        let targetID = memoID
        let existing = try context.fetch(FetchDescriptor<MemoChecklistItem>(
            predicate: #Predicate<MemoChecklistItem> { item in
                item.memoId == targetID
            }
        ))
        let active = existing.filter { $0.supersededAt == nil }
        let existingByID = active.reduce(into: [UUID: MemoChecklistItem]()) { result, item in
            guard let current = result[item.id] else {
                result[item.id] = item
                return
            }
            if current.updatedAt < item.updatedAt ||
                (current.updatedAt == item.updatedAt &&
                    current.instanceID.uuidString > item.instanceID.uuidString) {
                result[item.id] = item
            }
        }
        let retainedIDs = Set(normalized.map(\.id))
        var changed = false

        for item in existing where !retainedIDs.contains(item.id) {
            context.delete(item)
            changed = true
        }

        for item in active where retainedIDs.contains(item.id) && existingByID[item.id] !== item {
            item.supersededAt = now
            changed = true
        }

        for (index, draft) in normalized.enumerated() {
            let order = Double(index + 1) * 100
            if let item = existingByID[draft.id] {
                var itemChanged = false
                if item.title != draft.title {
                    item.title = draft.title
                    itemChanged = true
                }
                if item.isCompleted != draft.isCompleted {
                    item.isCompleted = draft.isCompleted
                    itemChanged = true
                }
                if item.order != order {
                    item.order = order
                    itemChanged = true
                }
                let completedAt = draft.isCompleted ? (item.completedAt ?? now) : nil
                if item.completedAt != completedAt {
                    item.completedAt = completedAt
                    itemChanged = true
                }
                if itemChanged {
                    item.updatedAt = now
                    changed = true
                }
            } else {
                context.insert(MemoChecklistItem(
                    id: draft.id,
                    memoId: memoID,
                    title: draft.title,
                    isCompleted: draft.isCompleted,
                    order: order,
                    completedAt: draft.isCompleted ? now : nil,
                    createdAt: now,
                    updatedAt: now
                ))
                changed = true
            }
        }
        return changed
    }

    static func normalizedDrafts(_ drafts: [MemoChecklistDraft]) -> [MemoChecklistDraft] {
        var seen = Set<UUID>()
        return drafts
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.uuidString < $1.id.uuidString
            }
            .compactMap { draft in
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, seen.insert(draft.id).inserted else { return nil }
                return MemoChecklistDraft(
                    id: draft.id,
                    title: title,
                    isCompleted: draft.isCompleted,
                    order: draft.order
                )
            }
    }


}
