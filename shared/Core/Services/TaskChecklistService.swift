import Foundation
import SwiftData

public struct ChecklistItemDraft: Equatable, Identifiable, Sendable {
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

    public init(item: TaskChecklistItem) {
        self.init(
            id: item.id,
            title: item.title,
            isCompleted: item.isCompleted,
            order: item.order
        )
    }
}

public struct ChecklistProgress: Equatable, Sendable {
    public var completedCount: Int
    public var totalCount: Int

    public init(completedCount: Int, totalCount: Int) {
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    public var isEmpty: Bool { totalCount == 0 }
    public var isComplete: Bool { totalCount > 0 && completedCount == totalCount }
}

public enum TaskChecklistService {
    public static func descriptor(taskID: UUID) -> FetchDescriptor<TaskChecklistItem> {
        FetchDescriptor(
            predicate: #Predicate<TaskChecklistItem> { item in
                item.supersededAt == nil && item.taskId == taskID
            },
            sortBy: [
                SortDescriptor(\TaskChecklistItem.order),
                SortDescriptor(\TaskChecklistItem.createdAt),
                SortDescriptor(\TaskChecklistItem.instanceID)
            ]
        )
    }

    public static func descriptor(taskIDs: [UUID]) -> FetchDescriptor<TaskChecklistItem> {
        FetchDescriptor(
            predicate: #Predicate<TaskChecklistItem> { item in
                item.supersededAt == nil && taskIDs.contains(item.taskId)
            },
            sortBy: [
                SortDescriptor(\TaskChecklistItem.taskId),
                SortDescriptor(\TaskChecklistItem.order),
                SortDescriptor(\TaskChecklistItem.createdAt),
                SortDescriptor(\TaskChecklistItem.instanceID)
            ]
        )
    }

    @MainActor
    public static func items(
        for taskID: UUID,
        in context: ModelContext
    ) throws -> [TaskChecklistItem] {
        try context.fetch(descriptor(taskID: taskID))
    }

    @MainActor
    public static func items(
        for taskIDs: [UUID],
        in context: ModelContext
    ) throws -> [TaskChecklistItem] {
        guard !taskIDs.isEmpty else { return [] }
        return try context.fetch(descriptor(taskIDs: taskIDs))
    }

    public static func drafts(from items: [TaskChecklistItem]) -> [ChecklistItemDraft] {
        activeItems(items)
            .sorted(by: itemSort)
            .map(ChecklistItemDraft.init(item:))
    }

    public static func progress(in items: [TaskChecklistItem]) -> ChecklistProgress {
        let active = activeItems(items)
        return ChecklistProgress(
            completedCount: active.filter(\.isCompleted).count,
            totalCount: active.count
        )
    }

    public static func titles(in items: [TaskChecklistItem]) -> [String] {
        activeItems(items)
            .sorted(by: itemSort)
            .compactMap { normalizedTitle($0.title) }
    }

    @MainActor
    @discardableResult
    public static func setCompletion(
        _ isCompleted: Bool,
        for item: TaskChecklistItem,
        now: Date = Date()
    ) -> Bool {
        guard item.supersededAt == nil, item.isCompleted != isCompleted else {
            return false
        }

        item.isCompleted = isCompleted
        item.completedAt = isCompleted ? now : nil
        item.updatedAt = now
        return true
    }

    @MainActor
    @discardableResult
    public static func replaceItems(
        for taskID: UUID,
        drafts: [ChecklistItemDraft],
        existingItems: [TaskChecklistItem],
        in context: ModelContext,
        now: Date = Date()
    ) -> [TaskChecklistItem] {
        let normalizedDrafts = normalizedDrafts(drafts)
        let activeExisting = activeItems(existingItems).filter { $0.taskId == taskID }
        let existingByID = activeExisting.reduce(into: [UUID: TaskChecklistItem]()) { result, item in
            guard let current = result[item.id] else {
                result[item.id] = item
                return
            }
            if current.updatedAt < item.updatedAt ||
                (current.updatedAt == item.updatedAt &&
                    current.instanceID.uuidString < item.instanceID.uuidString) {
                result[item.id] = item
            }
        }
        let retainedIDs = Set(normalizedDrafts.map(\.id))
        var result: [TaskChecklistItem] = []

        for item in activeExisting where !retainedIDs.contains(item.id) {
            context.delete(item)
        }

        for (index, draft) in normalizedDrafts.enumerated() {
            let order = Double(index + 1) * 100
            if let item = existingByID[draft.id] {
                var changed = false
                changed = assign(&item.title, draft.title) || changed
                changed = assign(&item.isCompleted, draft.isCompleted) || changed
                changed = assign(&item.order, order) || changed
                let completedAt = draft.isCompleted ? (item.completedAt ?? now) : nil
                changed = assign(&item.completedAt, completedAt) || changed
                if changed {
                    item.updatedAt = now
                }
                result.append(item)
            } else {
                let item = TaskChecklistItem(
                    id: draft.id,
                    taskId: taskID,
                    title: draft.title,
                    isCompleted: draft.isCompleted,
                    order: order,
                    createdAt: now,
                    updatedAt: now,
                    completedAt: draft.isCompleted ? now : nil
                )
                context.insert(item)
                result.append(item)
            }
        }

        return result
    }

    @MainActor
    public static func deleteItems(
        for taskID: UUID,
        in context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor<TaskChecklistItem>(
            predicate: #Predicate<TaskChecklistItem> { item in
                item.taskId == taskID
            }
        ))
        for item in items {
            context.delete(item)
        }
    }

    private static func normalizedDrafts(_ drafts: [ChecklistItemDraft]) -> [ChecklistItemDraft] {
        var seen = Set<UUID>()
        return drafts
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.uuidString < $1.id.uuidString
            }
            .compactMap { draft in
                guard seen.insert(draft.id).inserted,
                      let title = normalizedTitle(draft.title) else { return nil }
                return ChecklistItemDraft(
                    id: draft.id,
                    title: title,
                    isCompleted: draft.isCompleted,
                    order: draft.order
                )
            }
    }

    private static func activeItems(_ items: [TaskChecklistItem]) -> [TaskChecklistItem] {
        items.filter { $0.supersededAt == nil }
    }

    private static func normalizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func itemSort(_ lhs: TaskChecklistItem, _ rhs: TaskChecklistItem) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private static func assign<Value: Equatable>(_ target: inout Value, _ value: Value) -> Bool {
        guard target != value else { return false }
        target = value
        return true
    }
}
