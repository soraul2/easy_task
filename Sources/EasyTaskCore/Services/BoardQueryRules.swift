import Foundation

public enum BoardQueryRules {
    public static func tasksForBoard(
        _ tasks: [Task],
        selectedDayKey: String,
        todayKey: String = DayKey.today,
        includeCarryoverOnToday: Bool = false
    ) -> [Task] {
        let visibleTasks: [Task]
        if selectedDayKey == todayKey {
            visibleTasks = tasks.filter { task in
                guard task.supersededAt == nil else { return false }
                guard task.archivedAt == nil else { return false }
                if task.status == TaskStatus.done.rawValue {
                    return task.completedDayKey == todayKey
                }
                if task.plannedDayKey == todayKey {
                    return true
                }
                return includeCarryoverOnToday && task.plannedDayKey < selectedDayKey
            }
        } else {
            visibleTasks = tasks.filter { task in
                guard task.supersededAt == nil else { return false }
                if task.status == TaskStatus.done.rawValue {
                    return (task.completedDayKey ?? task.plannedDayKey) == selectedDayKey
                }
                return task.archivedAt == nil && task.plannedDayKey == selectedDayKey
            }
        }

        return visibleTasks.sorted(by: boardSort)
    }

    public static func tasks(_ tasks: [Task], matching status: TaskStatus) -> [Task] {
        let filtered = tasks.filter { $0.supersededAt == nil && $0.status == status.rawValue }
        if status == .done {
            return filtered.sorted(by: doneSort)
        }
        return filtered.sorted(by: openTaskSort)
    }

    public static func nextOrder(
        in tasks: [Task],
        dayKey: String,
        status: TaskStatus = .todo
    ) -> Double {
        TaskRules.nextOrder(
            in: tasks.filter { $0.plannedDayKey == dayKey },
            status: status
        )
    }

    private static func boardSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.status == TaskStatus.done.rawValue, rhs.status == TaskStatus.done.rawValue {
            return doneSort(lhs, rhs)
        }
        if lhs.status == rhs.status {
            return openTaskSort(lhs, rhs)
        }
        return statusRank(lhs.status) < statusRank(rhs.status)
    }

    private static func openTaskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        if lhs.plannedDayKey != rhs.plannedDayKey {
            return lhs.plannedDayKey < rhs.plannedDayKey
        }
        return lhs.title < rhs.title
    }

    private static func doneSort(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsCompletedAt = lhs.completedAt ?? .distantPast
        let rhsCompletedAt = rhs.completedAt ?? .distantPast
        if lhsCompletedAt != rhsCompletedAt {
            return lhsCompletedAt > rhsCompletedAt
        }
        return openTaskSort(lhs, rhs)
    }

    private static func statusRank(_ status: String) -> Int {
        switch TaskStatus(rawValue: status) {
        case .some(.todo): 0
        case .some(.doing): 1
        case .some(.done): 2
        case .none: 3
        }
    }
}
