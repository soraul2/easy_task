import Foundation
import SwiftData

public enum TaskRules {
    public static func applyStatus(
        _ status: TaskStatus,
        to task: Task,
        now: Date = Date(),
        completionDayKey: String? = nil
    ) {
        let oldStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard oldStatus != status else { return }

        task.status = status.rawValue
        task.updatedAt = now

        switch (oldStatus, status) {
        case (.done, .todo), (.done, .doing):
            task.completedAt = nil
            task.completedDayKey = nil
            task.archivedAt = nil
            task.archivedDayKey = nil
        case (_, .done):
            task.completedAt = now
            task.completedDayKey = completionDayKey ?? DayKey.key(for: now)
        default:
            break
        }
    }

    public static func carryoverTasks(_ tasks: [Task], before dayKey: String = DayKey.today) -> [Task] {
        tasks
            .filter {
                $0.archivedAt == nil &&
                    $0.status != TaskStatus.done.rawValue &&
                    $0.plannedDayKey < dayKey
            }
            .sorted {
                if $0.plannedDayKey == $1.plannedDayKey {
                    return $0.order < $1.order
                }
                return $0.plannedDayKey < $1.plannedDayKey
            }
    }

    public static func move(_ task: Task, to date: Date, order: Double? = nil, now: Date = Date()) {
        let plannedAt = DayKey.startOfDay(for: date)
        task.plannedAt = plannedAt
        task.plannedDayKey = DayKey.key(for: plannedAt)
        if let order {
            task.order = order
        }
        task.updatedAt = now
    }

    public static func completeAll(_ tasks: [Task], now: Date = Date(), completionDayKey: String? = nil) {
        for task in tasks {
            applyStatus(.done, to: task, now: now, completionDayKey: completionDayKey)
        }
    }

    public static func archiveIfNeeded(_ tasks: [Task], todayKey: String = DayKey.today, now: Date = Date()) {
        for task in tasks where task.status == TaskStatus.done.rawValue {
            guard let completedDayKey = task.completedDayKey else { continue }
            guard completedDayKey < todayKey, task.archivedAt == nil else { continue }

            task.archivedAt = now
            task.archivedDayKey = todayKey
            task.updatedAt = now
        }
    }

    public static func nextOrder(in tasks: [Task], status: TaskStatus = .todo) -> Double {
        let maxOrder = tasks
            .filter { $0.status == status.rawValue && $0.archivedAt == nil }
            .map(\.order)
            .max() ?? 0
        return maxOrder + 100
    }

    @MainActor
    public static func delete(
        _ task: Task,
        from context: ModelContext,
        now: Date = Date()
    ) throws {
        if let placementID = task.templatePlacementId {
            var descriptor = FetchDescriptor<TemplatePlacement>(
                predicate: #Predicate { $0.id == placementID }
            )
            descriptor.fetchLimit = 1
            if let placement = try context.fetch(descriptor).first {
                placement.taskIds.removeAll { $0 == task.id }
                placement.updatedAt = now
            }
        }

        context.delete(task)
    }
}
