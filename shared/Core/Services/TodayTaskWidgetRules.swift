import Foundation

public enum TodayTaskWidgetRules {
    @MainActor
    public static func eligibleRepresentatives(
        from tasks: [Task],
        dayKey: String
    ) -> [Task] {
        let representatives = Dictionary(
            grouping: tasks.filter {
                $0.supersededAt == nil
                    && $0.archivedAt == nil
                    && $0.plannedDayKey == dayKey
                    && TaskStatus(rawValue: $0.status) != nil
            },
            by: \.id
        ).values.compactMap { candidates in
            BoundedQueryService.representativeTask(from: candidates)
        }
        return representatives.sorted(by: taskSort)
    }

    @MainActor
    public static func representativeTask(
        id: UUID,
        from tasks: [Task],
        dayKey: String
    ) -> Task? {
        eligibleRepresentatives(from: tasks, dayKey: dayKey)
            .first { $0.id == id }
    }

    @MainActor
    public static func currentDoingTask(
        from tasks: [Task],
        dayKey: String
    ) -> Task? {
        eligibleRepresentatives(from: tasks, dayKey: dayKey)
            .first { $0.status == TaskStatus.doing.rawValue }
    }

    @MainActor
    public static func nextTask(
        after currentTaskID: UUID,
        from tasks: [Task],
        dayKey: String
    ) -> Task? {
        let otherTasks = eligibleRepresentatives(from: tasks, dayKey: dayKey)
            .filter { $0.id != currentTaskID }
        return otherTasks.first { $0.status == TaskStatus.doing.rawValue }
            ?? otherTasks.first { $0.status == TaskStatus.todo.rawValue }
    }

    @MainActor
    private static func taskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsRank = statusRank(lhs.status)
        let rhsRank = statusRank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        let lhsTitle = normalizedTitle(lhs.title)
        let rhsTitle = normalizedTitle(rhs.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private static func statusRank(_ rawValue: String) -> Int {
        switch TaskStatus(rawValue: rawValue) {
        case .doing: 0
        case .todo: 1
        case .done: 2
        case .none: 3
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
