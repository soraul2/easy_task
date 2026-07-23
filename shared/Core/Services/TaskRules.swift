import Foundation
import SwiftData

public enum TaskRules {
    public static func applyStatus(
        _ status: TaskStatus,
        to task: Task,
        now: Date = Date(),
        completionDayKey: String? = nil
    ) {
        guard task.supersededAt == nil else { return }
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

    @discardableResult
    public static func setReminder(
        _ reminderAt: Date?,
        on task: Task,
        now: Date = Date()
    ) -> Bool {
        guard task.supersededAt == nil else { return false }
        let normalized = TaskReminderRules.normalizedDate(reminderAt)
        guard task.reminderAt != normalized else { return false }
        task.reminderAt = normalized
        task.updatedAt = now
        return true
    }

    public static func carryoverTasks(_ tasks: [Task], before dayKey: String = DayKey.today) -> [Task] {
        tasks
            .filter {
                $0.supersededAt == nil &&
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
        guard task.supersededAt == nil else { return }
        let plannedAt = DayKey.startOfDay(for: date)
        task.plannedAt = plannedAt
        task.plannedDayKey = DayKey.key(for: plannedAt)
        if let order {
            task.order = order
        }
        task.updatedAt = now
    }

    public static func bringToToday(
        _ task: Task,
        order: Double? = nil,
        now: Date = Date()
    ) {
        guard task.supersededAt == nil else { return }
        applyStatus(.todo, to: task, now: now)
        move(task, to: now, order: order, now: now)
    }

    public static func completeAll(_ tasks: [Task], now: Date = Date(), completionDayKey: String? = nil) {
        for task in tasks where task.supersededAt == nil {
            applyStatus(.done, to: task, now: now, completionDayKey: completionDayKey)
        }
    }

    public static func completeOnPlannedDays(_ tasks: [Task], now: Date = Date()) {
        for task in tasks where task.supersededAt == nil {
            applyStatus(
                .done,
                to: task,
                now: now,
                completionDayKey: task.plannedDayKey
            )
        }
    }

    public static func archiveIfNeeded(_ tasks: [Task], todayKey: String = DayKey.today, now: Date = Date()) {
        for task in tasks where task.supersededAt == nil && task.status == TaskStatus.done.rawValue {
            guard let completedDayKey = task.completedDayKey else { continue }
            guard completedDayKey < todayKey, task.archivedAt == nil else { continue }

            task.archivedAt = now
            task.archivedDayKey = todayKey
            task.updatedAt = now
        }
    }

    public static func nextOrder(in tasks: [Task], status: TaskStatus = .todo) -> Double {
        let maxOrder = tasks
            .filter {
                $0.supersededAt == nil &&
                    $0.status == status.rawValue &&
                    $0.archivedAt == nil
            }
            .map(\.order)
            .max() ?? 0
        return maxOrder + 100
    }

    @MainActor
    public static func delete(
        _ task: Task,
        from context: ModelContext
    ) throws {
        try TaskChecklistService.deleteItems(for: task.id, in: context)
        context.delete(task)
    }
}
