import Foundation

enum TaskRules {
    static func applyStatus(_ status: TaskStatus, to task: Task, now: Date = Date()) {
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
            task.completedDayKey = DayKey.key(for: now)
        default:
            break
        }
    }

    static func archiveIfNeeded(_ tasks: [Task], todayKey: String = DayKey.today, now: Date = Date()) {
        for task in tasks where task.status == TaskStatus.done.rawValue {
            guard let completedDayKey = task.completedDayKey else { continue }
            guard completedDayKey < todayKey, task.archivedAt == nil else { continue }

            task.archivedAt = now
            task.archivedDayKey = todayKey
            task.updatedAt = now
        }
    }

    static func nextOrder(in tasks: [Task], status: TaskStatus = .todo) -> Double {
        let maxOrder = tasks
            .filter { $0.status == status.rawValue && $0.archivedAt == nil }
            .map(\.order)
            .max() ?? 0
        return maxOrder + 100
    }
}
