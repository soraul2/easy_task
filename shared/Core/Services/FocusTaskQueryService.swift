import Foundation
import SwiftData

public struct FocusTaskCandidate: Identifiable {
    public let id: UUID
    public let title: String
    public let dayKey: String
    public let status: TaskStatus
    public let estimatedMinutes: Int?
    public let updatedAt: Date
}

public enum FocusTaskQueryService {
    @MainActor
    public static func candidates(
        selectedTaskID: UUID?,
        in context: ModelContext
    ) throws -> [FocusTaskCandidate] {
        let done = TaskStatus.done.rawValue
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> {
                $0.supersededAt == nil && $0.archivedAt == nil && $0.status != done
            },
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.instanceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 100
        var tasks = try context.fetch(descriptor)
        // The explicitly opened card may be older than the recent-task window.
        if let selectedTaskID {
            tasks.removeAll { $0.id == selectedTaskID }
            if let selected = BoundedQueryService.representativeTask(from: try context.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: selectedTaskID)
            )), selected.archivedAt == nil, selected.status != done {
                tasks.insert(selected, at: 0)
            }
        }
        var seen: Set<UUID> = []
        return tasks.compactMap { task in
            guard seen.insert(task.id).inserted else { return nil }
            return FocusTaskCandidate(
                id: task.id, title: task.title, dayKey: task.plannedDayKey,
                status: TaskStatus(rawValue: task.status) ?? .todo,
                estimatedMinutes: task.estimatedMinutes, updatedAt: task.updatedAt
            )
        }.sorted {
            if $0.status != $1.status { return $0.status == .doing }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
