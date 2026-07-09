import Foundation

public enum ArchivePeriod: String, CaseIterable, Identifiable {
    case all
    case last7Days
    case last30Days
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "전체"
        case .last7Days: "최근 7일"
        case .last30Days: "최근 30일"
        case .custom: "직접 설정"
        }
    }
}

public enum ArchiveScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case reviews

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "전체"
        case .tasks: "작업"
        case .reviews: "회고"
        }
    }

    var includesTasks: Bool {
        self == .all || self == .tasks
    }

    var includesReviews: Bool {
        self == .all || self == .reviews
    }
}

public struct ArchiveFilter: Equatable {
    public var searchText: String
    public var period: ArchivePeriod
    public var scope: ArchiveScope
    public var customStartDate: Date
    public var customEndDate: Date

    public init(
        searchText: String = "",
        period: ArchivePeriod = .all,
        scope: ArchiveScope = .all,
        customStartDate: Date = DayKey.addingDays(-30, to: DayKey.startOfDay(for: Date())),
        customEndDate: Date = DayKey.startOfDay(for: Date())
    ) {
        self.searchText = searchText
        self.period = period
        self.scope = scope
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
    }

    public var hasActiveCriteria: Bool {
        !normalizedSearchText.isEmpty || period != .all || scope != .all
    }

    public mutating func reset(referenceDate: Date = Date()) {
        searchText = ""
        period = .all
        scope = .all
        customStartDate = DayKey.addingDays(-30, to: DayKey.startOfDay(for: referenceDate))
        customEndDate = DayKey.startOfDay(for: referenceDate)
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ArchiveDayRecord: Identifiable {
    public var dayKey: String
    public var tasks: [Task]
    public var review: DailyReview?

    public var id: String { dayKey }

    public init(dayKey: String, tasks: [Task], review: DailyReview?) {
        self.dayKey = dayKey
        self.tasks = tasks
        self.review = review
    }
}

public enum ArchiveQueryRules {
    public static func records(
        tasks: [Task],
        reviews: [DailyReview],
        filter: ArchiveFilter,
        referenceDate: Date = Date()
    ) -> [ArchiveDayRecord] {
        let completedTasks = tasks
            .filter { $0.status == TaskStatus.done.rawValue }
            .filter { matchesPeriod(dayKey(for: $0), filter: filter, referenceDate: referenceDate) }
        let nonEmptyReviews = reviews
            .filter(DailyReviewRules.hasContent)
            .filter { matchesPeriod($0.dayKey, filter: filter, referenceDate: referenceDate) }

        let tasksByDay = Dictionary(grouping: completedTasks, by: dayKey)
        let reviewsByDay = Dictionary(grouping: nonEmptyReviews, by: \DailyReview.dayKey)
            .compactMapValues { records in
                records.max { $0.updatedAt < $1.updatedAt }
            }

        let dayKeys: Set<String>
        if filter.normalizedSearchText.isEmpty {
            let taskKeys = filter.scope.includesTasks ? Set(tasksByDay.keys) : Set<String>()
            let reviewKeys = filter.scope.includesReviews ? Set(reviewsByDay.keys) : Set<String>()
            dayKeys = taskKeys.union(reviewKeys)
        } else {
            let taskKeys = filter.scope.includesTasks
                ? completedTasks.filter { matchesSearch($0, query: filter.normalizedSearchText) }.map(dayKey)
                : []
            let reviewKeys = filter.scope.includesReviews
                ? nonEmptyReviews.filter { matchesSearch($0, query: filter.normalizedSearchText) }.map(\.dayKey)
                : []
            dayKeys = Set(taskKeys).union(reviewKeys)
        }

        return dayKeys
            .sorted(by: >)
            .map { key in
                ArchiveDayRecord(
                    dayKey: key,
                    tasks: (tasksByDay[key] ?? []).sorted(by: tasksNewestFirst),
                    review: reviewsByDay[key]
                )
            }
            .filter { !$0.tasks.isEmpty || $0.review != nil }
    }

    public static func dayKey(for task: Task) -> String {
        task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey
    }

    private static func matchesPeriod(
        _ dayKey: String,
        filter: ArchiveFilter,
        referenceDate: Date
    ) -> Bool {
        let referenceDay = DayKey.startOfDay(for: referenceDate)
        let referenceKey = DayKey.key(for: referenceDay)

        switch filter.period {
        case .all:
            return true
        case .last7Days:
            let startKey = DayKey.key(for: DayKey.addingDays(-6, to: referenceDay))
            return startKey <= dayKey && dayKey <= referenceKey
        case .last30Days:
            let startKey = DayKey.key(for: DayKey.addingDays(-29, to: referenceDay))
            return startKey <= dayKey && dayKey <= referenceKey
        case .custom:
            let startKey = DayKey.key(for: min(filter.customStartDate, filter.customEndDate))
            let endKey = DayKey.key(for: max(filter.customStartDate, filter.customEndDate))
            return startKey <= dayKey && dayKey <= endKey
        }
    }

    private static func matchesSearch(_ task: Task, query: String) -> Bool {
        contains(task.title, query: query) ||
            contains(task.note, query: query) ||
            contains(task.completedDayKey, query: query) ||
            contains(task.archivedDayKey, query: query) ||
            contains(task.plannedDayKey, query: query)
    }

    private static func matchesSearch(_ review: DailyReview, query: String) -> Bool {
        contains(review.title, query: query) ||
            contains(review.content, query: query) ||
            contains(review.weather, query: query) ||
            contains(review.mood, query: query) ||
            contains(review.dayKey, query: query)
    }

    private static func contains(_ value: String?, query: String) -> Bool {
        guard let value else { return false }
        return value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private static func tasksNewestFirst(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsDate = lhs.completedAt ?? lhs.archivedAt ?? .distantPast
        let rhsDate = rhs.completedAt ?? rhs.archivedAt ?? .distantPast
        return lhsDate > rhsDate
    }
}
