import Foundation

public struct TaskHistoryStatistics: Equatable, Sendable {
    public var plannedTaskCount: Int
    public var completedTaskCount: Int
    public var completedOnOrBeforePlannedDayCount: Int
    public var delayedCompletionCount: Int
    public var incompleteCount: Int

    public init(
        plannedTaskCount: Int = 0,
        completedTaskCount: Int = 0,
        completedOnOrBeforePlannedDayCount: Int = 0,
        delayedCompletionCount: Int = 0,
        incompleteCount: Int = 0
    ) {
        self.plannedTaskCount = plannedTaskCount
        self.completedTaskCount = completedTaskCount
        self.completedOnOrBeforePlannedDayCount = completedOnOrBeforePlannedDayCount
        self.delayedCompletionCount = delayedCompletionCount
        self.incompleteCount = incompleteCount
    }

    public var plannedCompletionRate: Double? {
        guard plannedTaskCount > 0 else { return nil }
        let completedCohortCount =
            completedOnOrBeforePlannedDayCount + delayedCompletionCount
        return Double(completedCohortCount) / Double(plannedTaskCount)
    }
}

public struct TaskHistoryStatisticsPresentation: Equatable, Sendable {
    public var periodTitle: String
    public var populationTitle: String
    public var meaningDescription: String

    public init(
        filter: ArchiveFilter,
        referenceDate: Date = Date()
    ) {
        let range = ArchiveQueryRules.dayKeyRange(
            for: filter,
            referenceDate: referenceDate
        )
        switch filter.period {
        case .all:
            periodTitle = "전체 기간"
        case .last7Days, .last30Days, .custom:
            let lower = range.lowerBound ?? range.upperBound
            let lowerText = DayKey.date(from: lower).map(DayKey.display) ?? lower
            let upperText = DayKey.date(from: range.upperBound).map(DayKey.display)
                ?? range.upperBound
            periodTitle = lower == range.upperBound
                ? lowerText
                : "\(lowerText)–\(upperText)"
        }
        populationTitle = "\(periodTitle) 전체 작업 · 목록은 \(filter.dateBasis.title)"
        meaningDescription =
            "계획 작업과 계획 대비 완료율은 계획일 기준, 완료 작업은 완료일 기준입니다."
    }
}

public enum TaskHistoryStatisticsRules {
    public static func statistics(
        from tasks: [Task],
        lowerBound: String,
        upperBound: String
    ) -> TaskHistoryStatistics {
        let lower = min(lowerBound, upperBound)
        let upper = max(lowerBound, upperBound)
        let representatives = activeRepresentatives(tasks)
        let plannedCohort = representatives.filter {
            lower <= $0.plannedDayKey && $0.plannedDayKey <= upper
        }
        let completedInPeriod = representatives.filter {
            guard $0.status == TaskStatus.done.rawValue else { return false }
            let completionKey = TaskHistoryDateRules.dayKey(
                for: $0,
                basis: .completed
            )
            return lower <= completionKey && completionKey <= upper
        }

        var onTime = 0
        var delayed = 0
        var incomplete = 0
        for task in plannedCohort {
            guard task.status == TaskStatus.done.rawValue else {
                incomplete += 1
                continue
            }
            let completionKey = TaskHistoryDateRules.dayKey(
                for: task,
                basis: .completed
            )
            if completionKey <= task.plannedDayKey {
                onTime += 1
            } else {
                delayed += 1
            }
        }

        return TaskHistoryStatistics(
            plannedTaskCount: plannedCohort.count,
            completedTaskCount: completedInPeriod.count,
            completedOnOrBeforePlannedDayCount: onTime,
            delayedCompletionCount: delayed,
            incompleteCount: incomplete
        )
    }

    private static func activeRepresentatives(_ tasks: [Task]) -> [Task] {
        var representatives: [UUID: Task] = [:]
        for task in tasks where task.supersededAt == nil {
            guard let existing = representatives[task.id] else {
                representatives[task.id] = task
                continue
            }
            if task.updatedAt > existing.updatedAt ||
                (task.updatedAt == existing.updatedAt &&
                    task.instanceID.uuidString > existing.instanceID.uuidString) {
                representatives[task.id] = task
            }
        }
        return Array(representatives.values)
    }
}
