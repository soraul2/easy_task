import Foundation

public enum TaskHistoryDateBasis: String, CaseIterable, Identifiable, Sendable {
    case completed
    case planned

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .completed: "완료일 기준"
        case .planned: "계획일 기준"
        }
    }

    public var taskSectionTitle: String {
        switch self {
        case .completed: "그날 완료한 일"
        case .planned: "그날 계획한 일"
        }
    }
}

public enum TaskHistoryCompletionDateSource: String, Equatable, Sendable {
    case completedDayKey
    case completedAt
    case archivedDayKey
    case plannedDayKey
}

public struct TaskHistoryCompletionDate: Equatable, Sendable {
    public var dayKey: String
    public var source: TaskHistoryCompletionDateSource

    public init(dayKey: String, source: TaskHistoryCompletionDateSource) {
        self.dayKey = dayKey
        self.source = source
    }

    public var isRecordedCompletionDate: Bool {
        source == .completedDayKey || source == .completedAt
    }

    public var isBestEffort: Bool {
        source == .completedAt
    }
}

public enum TaskHistoryDateRules {
    public static let completedAtFallbackExplanation =
        "저장된 완료일이 없는 이전 작업은 현재 시간대 기준으로 완료 처리 시각을 해석한 날짜입니다."

    public static func completionDate(
        for task: Task,
        calendar: Calendar = DayKey.calendar
    ) -> TaskHistoryCompletionDate {
        if let completedDayKey = nonEmpty(task.completedDayKey) {
            return TaskHistoryCompletionDate(
                dayKey: completedDayKey,
                source: .completedDayKey
            )
        }
        if let completedAt = task.completedAt {
            return TaskHistoryCompletionDate(
                dayKey: DayKey.key(for: completedAt, calendar: calendar),
                source: .completedAt
            )
        }
        if let archivedDayKey = nonEmpty(task.archivedDayKey) {
            return TaskHistoryCompletionDate(
                dayKey: archivedDayKey,
                source: .archivedDayKey
            )
        }
        return TaskHistoryCompletionDate(
            dayKey: task.plannedDayKey,
            source: .plannedDayKey
        )
    }

    public static func dayKey(
        for task: Task,
        basis: TaskHistoryDateBasis,
        calendar: Calendar = DayKey.calendar
    ) -> String {
        switch basis {
        case .completed:
            completionDate(for: task, calendar: calendar).dayKey
        case .planned:
            task.plannedDayKey
        }
    }

    public static func recordedCompletionDayKey(
        for task: Task,
        calendar: Calendar = DayKey.calendar
    ) -> String? {
        let value = completionDate(for: task, calendar: calendar)
        return value.isRecordedCompletionDate ? value.dayKey : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

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
    public var dateBasis: TaskHistoryDateBasis
    public var customStartDate: Date
    public var customEndDate: Date

    public init(
        searchText: String = "",
        period: ArchivePeriod = .all,
        scope: ArchiveScope = .all,
        dateBasis: TaskHistoryDateBasis = .completed,
        customStartDate: Date = DayKey.addingDays(-30, to: DayKey.startOfDay(for: Date())),
        customEndDate: Date = DayKey.startOfDay(for: Date())
    ) {
        self.searchText = searchText
        self.period = period
        self.scope = scope
        self.dateBasis = dateBasis
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
    }

    public var hasActiveCriteria: Bool {
        !normalizedSearchText.isEmpty ||
            period != .all ||
            scope != .all ||
            dateBasis != .completed
    }

    public mutating func reset(referenceDate: Date = Date()) {
        searchText = ""
        period = .all
        scope = .all
        dateBasis = .completed
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
    public var matchedTaskIDs: Set<UUID>
    public var matchedChecklistItemIDs: Set<UUID>
    public var reviewMatchesSearch: Bool
    public var hasSearchQuery: Bool

    public var id: String { dayKey }

    public init(
        dayKey: String,
        tasks: [Task],
        review: DailyReview?,
        matchedTaskIDs: Set<UUID> = [],
        matchedChecklistItemIDs: Set<UUID> = [],
        reviewMatchesSearch: Bool = false,
        hasSearchQuery: Bool = false
    ) {
        self.dayKey = dayKey
        self.tasks = tasks
        self.review = review
        self.matchedTaskIDs = matchedTaskIDs
        self.matchedChecklistItemIDs = matchedChecklistItemIDs
        self.reviewMatchesSearch = reviewMatchesSearch
        self.hasSearchQuery = hasSearchQuery
    }
}

public struct ArchiveDayPresentation: Equatable {
    public var dayKey: String
    public var title: String
    public var displayDate: String
    public var taskCount: Int
    public var hasReview: Bool
    public var matchedTaskIDs: Set<UUID>
    public var matchedChecklistItemIDs: Set<UUID>
    public var reviewMatchesSearch: Bool
    public var hasSearchQuery: Bool

    public init(record: ArchiveDayRecord) {
        let reviewTitle = record.review?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        dayKey = record.dayKey
        title = reviewTitle.isEmpty
            ? (record.review == nil ? "작업 기록" : "하루 회고")
            : reviewTitle
        displayDate = DayKey.date(from: record.dayKey).map(DayKey.display) ?? record.dayKey
        taskCount = record.tasks.count
        hasReview = record.review != nil
        matchedTaskIDs = record.matchedTaskIDs
        matchedChecklistItemIDs = record.matchedChecklistItemIDs
        reviewMatchesSearch = record.reviewMatchesSearch
        hasSearchQuery = record.hasSearchQuery
    }

    public var summaryText: String {
        var parts: [String] = []
        if taskCount > 0 {
            parts.append("작업 \(taskCount)")
        }
        if hasReview {
            parts.append("회고")
        }
        return parts.joined(separator: " · ")
    }

    public var shouldExpandTaskListForSearch: Bool {
        hasSearchQuery && !matchedTaskIDs.isEmpty
    }

    public func taskMatchesSearch(_ taskID: UUID) -> Bool {
        matchedTaskIDs.contains(taskID)
    }

    public func checklistItemMatchesSearch(_ itemID: UUID) -> Bool {
        matchedChecklistItemIDs.contains(itemID)
    }
}

public struct ArchiveDayKeyRange: Equatable, Sendable {
    public var lowerBound: String?
    public var upperBound: String

    public init(lowerBound: String?, upperBound: String) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

public enum ArchiveQueryRules {
    public static func records(
        tasks: [Task],
        reviews: [DailyReview],
        filter: ArchiveFilter,
        checklistItems: [TaskChecklistItem] = [],
        reviewIDsWithContent: Set<UUID> = [],
        referenceDate: Date = Date()
    ) -> [ArchiveDayRecord] {
        let completedTasks = representativeTasks(tasks)
            .filter { $0.status == TaskStatus.done.rawValue }
            .filter {
                matchesPeriod(
                    dayKey(for: $0, basis: filter.dateBasis),
                    filter: filter,
                    referenceDate: referenceDate
                )
            }
        let nonEmptyReviews = reviews
            .filter { $0.supersededAt == nil }
            .filter {
                DailyReviewRules.hasContent($0) || reviewIDsWithContent.contains($0.id)
            }
            .filter { matchesPeriod($0.dayKey, filter: filter, referenceDate: referenceDate) }

        let tasksByDay = Dictionary(grouping: completedTasks) {
            dayKey(for: $0, basis: filter.dateBasis)
        }
        let reviewsByDay = Dictionary(grouping: nonEmptyReviews, by: \DailyReview.dayKey)
            .compactMapValues { records in
                records.max {
                    if $0.updatedAt != $1.updatedAt {
                        return $0.updatedAt < $1.updatedAt
                    }
                    return $0.instanceID.uuidString < $1.instanceID.uuidString
                }
            }
        let activeChecklistItems = checklistItems.filter { $0.supersededAt == nil }
        let checklistItemsByTaskID = Dictionary(
            grouping: activeChecklistItems,
            by: \.taskId
        )
        let searchQuery = filter.normalizedSearchText
        let hasSearchQuery = !searchQuery.isEmpty
        let completedTaskIDs = Set(completedTasks.map(\.id))
        let matchingChecklistItemIDs = hasSearchQuery && filter.scope.includesTasks
            ? Set(activeChecklistItems.filter {
                completedTaskIDs.contains($0.taskId) && contains($0.title, query: searchQuery)
            }.map(\.id))
            : []
        let matchingTasks = hasSearchQuery && filter.scope.includesTasks
            ? completedTasks.filter {
                matchesSearch(
                    $0,
                    checklistItems: checklistItemsByTaskID[$0.id] ?? [],
                    query: searchQuery
                )
            }
            : []
        let matchingTaskIDs = Set(matchingTasks.map(\.id))
        let matchingReviewIDs = hasSearchQuery && filter.scope.includesReviews
            ? Set(reviewsByDay.values.filter {
                matchesSearch($0, query: searchQuery)
            }.map(\.id))
            : []

        let dayKeys: Set<String>
        if !hasSearchQuery {
            let taskKeys = filter.scope.includesTasks ? Set(tasksByDay.keys) : Set<String>()
            let reviewKeys = filter.scope.includesReviews ? Set(reviewsByDay.keys) : Set<String>()
            dayKeys = taskKeys.union(reviewKeys)
        } else {
            let taskKeys = matchingTasks.map {
                dayKey(for: $0, basis: filter.dateBasis)
            }
            let reviewKeys = reviewsByDay.values
                .filter { matchingReviewIDs.contains($0.id) }
                .map(\.dayKey)
            dayKeys = Set(taskKeys).union(reviewKeys)
        }

        return dayKeys
            .sorted(by: >)
            .map { key in
                ArchiveDayRecord(
                    dayKey: key,
                    tasks: (tasksByDay[key] ?? []).sorted(by: tasksNewestFirst),
                    review: reviewsByDay[key],
                    matchedTaskIDs: Set(
                        (tasksByDay[key] ?? [])
                            .map(\.id)
                            .filter(matchingTaskIDs.contains)
                    ),
                    matchedChecklistItemIDs: Set(
                        (tasksByDay[key] ?? [])
                            .flatMap { checklistItemsByTaskID[$0.id] ?? [] }
                            .map(\.id)
                            .filter(matchingChecklistItemIDs.contains)
                    ),
                    reviewMatchesSearch: reviewsByDay[key]
                        .map { matchingReviewIDs.contains($0.id) } ?? false,
                    hasSearchQuery: hasSearchQuery
                )
            }
            .filter { !$0.tasks.isEmpty || $0.review != nil }
    }

    public static func dayKeyRange(
        for filter: ArchiveFilter,
        referenceDate: Date = Date()
    ) -> ArchiveDayKeyRange {
        let referenceDay = DayKey.startOfDay(for: referenceDate)
        let referenceKey = DayKey.key(for: referenceDay)

        switch filter.period {
        case .all:
            return ArchiveDayKeyRange(lowerBound: nil, upperBound: referenceKey)
        case .last7Days:
            return ArchiveDayKeyRange(
                lowerBound: DayKey.key(for: DayKey.addingDays(-6, to: referenceDay)),
                upperBound: referenceKey
            )
        case .last30Days:
            return ArchiveDayKeyRange(
                lowerBound: DayKey.key(for: DayKey.addingDays(-29, to: referenceDay)),
                upperBound: referenceKey
            )
        case .custom:
            return ArchiveDayKeyRange(
                lowerBound: DayKey.key(for: min(filter.customStartDate, filter.customEndDate)),
                upperBound: DayKey.key(for: max(filter.customStartDate, filter.customEndDate))
            )
        }
    }

    public static func dayKey(for task: Task) -> String {
        dayKey(for: task, basis: .completed)
    }

    public static func dayKey(
        for task: Task,
        basis: TaskHistoryDateBasis
    ) -> String {
        TaskHistoryDateRules.dayKey(for: task, basis: basis)
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

    private static func matchesSearch(
        _ task: Task,
        checklistItems: [TaskChecklistItem],
        query: String
    ) -> Bool {
        contains(task.title, query: query) ||
            contains(task.note, query: query) ||
            contains(task.completedDayKey, query: query) ||
            contains(task.archivedDayKey, query: query) ||
            contains(task.plannedDayKey, query: query) ||
            checklistItems.contains { contains($0.title, query: query) }
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
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private static func representativeTasks(_ tasks: [Task]) -> [Task] {
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
