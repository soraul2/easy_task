import Foundation

public struct DailyReviewTaskSummaryItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var plannedDayKey: String
    public var isCarryover: Bool

    public init(
        id: UUID,
        title: String,
        plannedDayKey: String,
        isCarryover: Bool
    ) {
        self.id = id
        self.title = title
        self.plannedDayKey = plannedDayKey
        self.isCarryover = isCarryover
    }
}

public struct DailyReviewTaskSummary: Equatable, Sendable {
    public var completed: [DailyReviewTaskSummaryItem]
    public var inProgress: [DailyReviewTaskSummaryItem]
    public var pending: [DailyReviewTaskSummaryItem]

    public init(
        completed: [DailyReviewTaskSummaryItem] = [],
        inProgress: [DailyReviewTaskSummaryItem] = [],
        pending: [DailyReviewTaskSummaryItem] = []
    ) {
        self.completed = completed
        self.inProgress = inProgress
        self.pending = pending
    }

    public var totalCount: Int {
        completed.count + inProgress.count + pending.count
    }

    public var isEmpty: Bool {
        totalCount == 0
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
        let boardTasks = BoardQueryRules.tasksForBoard(
            activeTasks,
            selectedDayKey: selectedDayKey,
            todayKey: todayKey,
            includeCarryoverOnToday: includeCarryoverOnToday
        )

        return DailyReviewTaskSummary(
            completed: items(
                from: BoardQueryRules.tasks(boardTasks, matching: .done),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            ),
            inProgress: items(
                from: BoardQueryRules.tasks(boardTasks, matching: .doing),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            ),
            pending: items(
                from: BoardQueryRules.tasks(boardTasks, matching: .todo),
                selectedDayKey: selectedDayKey,
                todayKey: todayKey
            )
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
            DailyReviewTaskSummaryItem(
                id: task.id,
                title: task.title,
                plannedDayKey: task.plannedDayKey,
                isCarryover: selectedDayKey == todayKey &&
                    task.status != TaskStatus.done.rawValue &&
                    task.plannedDayKey < selectedDayKey
            )
        }
    }
}
