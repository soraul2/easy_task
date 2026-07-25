import Foundation

public struct DailyReviewTaskSummaryItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var plannedDayKey: String
    public var completedDayKey: String?
    public var completionDateIsBestEffort: Bool
    public var isCarryover: Bool

    public init(
        id: UUID,
        title: String,
        plannedDayKey: String,
        completedDayKey: String? = nil,
        completionDateIsBestEffort: Bool = false,
        isCarryover: Bool
    ) {
        self.id = id
        self.title = title
        self.plannedDayKey = plannedDayKey
        self.completedDayKey = completedDayKey
        self.completionDateIsBestEffort = completionDateIsBestEffort
        self.isCarryover = isCarryover
    }
}

public struct DailyReviewTaskSummary: Equatable, Sendable {
    public var completed: [DailyReviewTaskSummaryItem]
    public var inProgress: [DailyReviewTaskSummaryItem]
    public var pending: [DailyReviewTaskSummaryItem]
    public var actualCompleted: [DailyReviewTaskSummaryItem]

    public init(
        completed: [DailyReviewTaskSummaryItem] = [],
        inProgress: [DailyReviewTaskSummaryItem] = [],
        pending: [DailyReviewTaskSummaryItem] = [],
        actualCompleted: [DailyReviewTaskSummaryItem] = []
    ) {
        self.completed = completed
        self.inProgress = inProgress
        self.pending = pending
        self.actualCompleted = actualCompleted
    }

    public var totalCount: Int {
        completed.count + inProgress.count + pending.count
    }

    public var isEmpty: Bool {
        totalCount == 0 && actualCompleted.isEmpty
    }
}

public enum DailyReviewTaskSummaryRules {
    public static func summary(
        from tasks: [Task],
        selectedDayKey: String,
        todayKey: String = DayKey.today,
        includeCarryoverOnToday: Bool = true
    ) -> DailyReviewTaskSummary {
        let activeTasks = convergedActiveTasks(tasks)
        let plannedTasks = activeTasks.filter { task in
            if task.plannedDayKey == selectedDayKey {
                return task.status == TaskStatus.done.rawValue ||
                    task.archivedAt == nil
            }
            return selectedDayKey == todayKey &&
                includeCarryoverOnToday &&
                task.archivedAt == nil &&
                task.status != TaskStatus.done.rawValue &&
                task.plannedDayKey < selectedDayKey
        }
        let completedTasks = activeTasks.filter {
            $0.status == TaskStatus.done.rawValue &&
                TaskHistoryDateRules.dayKey(for: $0, basis: .completed) == selectedDayKey
        }

        return DailyReviewTaskSummary(
            completed: items(
                from: sorted(plannedTasks, status: .done),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            ),
            inProgress: items(
                from: sorted(plannedTasks, status: .doing),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            ),
            pending: items(
                from: sorted(plannedTasks, status: .todo),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            ),
            actualCompleted: completedTasks
                .sorted(by: completedNewestFirst)
                .map(item)
        )
    }

    private static func sorted(
        _ tasks: [Task],
        status: TaskStatus
    ) -> [Task] {
        tasks
            .filter { $0.status == status.rawValue }
            .sorted {
                if status == .done {
                    return completedNewestFirst($0, $1)
                }
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    private static func completedNewestFirst(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsDate = lhs.completedAt ?? lhs.archivedAt ?? .distantPast
        let rhsDate = rhs.completedAt ?? rhs.archivedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private static func item(_ task: Task) -> DailyReviewTaskSummaryItem {
        let completion = TaskHistoryDateRules.completionDate(for: task)
        return DailyReviewTaskSummaryItem(
            id: task.id,
            title: task.title,
            plannedDayKey: task.plannedDayKey,
            completedDayKey: task.status == TaskStatus.done.rawValue
                ? completion.dayKey
                : nil,
            completionDateIsBestEffort: completion.isBestEffort,
            isCarryover: false
        )
    }

    private static func convergedActiveTasks(_ tasks: [Task]) -> [Task] {
        var tasksByID: [UUID: Task] = [:]

        for task in tasks where task.supersededAt == nil {
            guard let existing = tasksByID[task.id] else {
                tasksByID[task.id] = task
                continue
            }

            if task.updatedAt > existing.updatedAt ||
                (task.updatedAt == existing.updatedAt &&
                    task.instanceID.uuidString > existing.instanceID.uuidString) {
                tasksByID[task.id] = task
            }
        }

        return Array(tasksByID.values)
    }

    private static func items(
        from tasks: [Task],
        selectedDayKey: String,
        todayKey: String
    ) -> [DailyReviewTaskSummaryItem] {
        tasks.map { task in
            let completion = task.status == TaskStatus.done.rawValue
                ? TaskHistoryDateRules.completionDate(for: task)
                : nil
            return DailyReviewTaskSummaryItem(
                id: task.id,
                title: task.title,
                plannedDayKey: task.plannedDayKey,
                completedDayKey: completion?.dayKey,
                completionDateIsBestEffort: completion?.isBestEffort == true,
                isCarryover: selectedDayKey == todayKey &&
                    task.status != TaskStatus.done.rawValue &&
                    task.plannedDayKey < selectedDayKey
            )
        }
    }
}
