import Foundation

public enum LockScreenWidgetFocusKind: String, Codable, Equatable, Sendable {
    case doingTask
    case event
    case todoTask
}

public struct LockScreenWidgetDaySummary: Codable, Equatable, Sendable {
    public let dayKey: String
    public let todoCount: Int
    public let doingCount: Int
    public let doneCount: Int
    public let eventCount: Int
    public let focusTitle: String?
    public let focusKind: LockScreenWidgetFocusKind?

    public init(
        dayKey: String,
        todoCount: Int,
        doingCount: Int,
        doneCount: Int,
        eventCount: Int,
        focusTitle: String? = nil,
        focusKind: LockScreenWidgetFocusKind? = nil
    ) {
        self.dayKey = dayKey
        self.todoCount = max(0, todoCount)
        self.doingCount = max(0, doingCount)
        self.doneCount = max(0, doneCount)
        self.eventCount = max(0, eventCount)

        let normalizedTitle = focusTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTitle, !normalizedTitle.isEmpty, let focusKind {
            self.focusTitle = normalizedTitle
            self.focusKind = focusKind
        } else {
            self.focusTitle = nil
            self.focusKind = nil
        }
    }

    public var remainingTaskCount: Int {
        todoCount + doingCount
    }

    public var hasContent: Bool {
        remainingTaskCount > 0 || doneCount > 0 || eventCount > 0
    }
}

public enum LockScreenWidgetRules {
    public static let coverageDayCount = 8

    public static func coverageDayKeys(
        for referenceDate: Date
    ) -> (startDayKey: String, endDayKey: String) {
        let startDate = DayKey.startOfDay(for: referenceDate)
        return (
            DayKey.key(for: startDate),
            DayKey.key(for: DayKey.addingDays(coverageDayCount - 1, to: startDate))
        )
    }

    @MainActor
    public static func makeDaySummaries(
        tasks: [Task],
        events: [CalendarEvent],
        referenceDate: Date = Date()
    ) -> [LockScreenWidgetDaySummary] {
        let startDate = DayKey.startOfDay(for: referenceDate)
        let endDate = DayKey.addingDays(coverageDayCount - 1, to: startDate)
        let startDayKey = DayKey.key(for: startDate)
        let endDayKey = DayKey.key(for: endDate)
        let activeTasks = representativeTasks(
            from: tasks.filter {
                $0.supersededAt == nil
                    && $0.archivedAt == nil
                    && TaskStatus(rawValue: $0.status) != nil
            }
        )
        let activeEvents = representativeEvents(
            from: events.filter {
                $0.supersededAt == nil
                    && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && DayKey.date(from: $0.startDayKey) != nil
                    && DayKey.date(from: $0.endDayKey) != nil
                    && $0.startDayKey <= $0.endDayKey
                    && $0.startDayKey <= endDayKey
                    && $0.endDayKey >= startDayKey
            }
        )

        return (0..<coverageDayCount).map { offset in
            let dayKey = DayKey.key(for: DayKey.addingDays(offset, to: startDate))
            return summary(dayKey: dayKey, tasks: activeTasks, events: activeEvents)
        }
    }

    @MainActor
    private static func summary(
        dayKey: String,
        tasks: [Task],
        events: [CalendarEvent]
    ) -> LockScreenWidgetDaySummary {
        let todoTasks = tasks
            .filter {
                $0.status == TaskStatus.todo.rawValue && $0.plannedDayKey == dayKey
            }
            .sorted(by: taskSort)
        let doingTasks = tasks
            .filter {
                $0.status == TaskStatus.doing.rawValue && $0.plannedDayKey == dayKey
            }
            .sorted(by: taskSort)
        let doneTasks = tasks.filter {
            $0.status == TaskStatus.done.rawValue && $0.completedDayKey == dayKey
        }
        let dayEvents = events
            .filter { $0.startDayKey <= dayKey && dayKey <= $0.endDayKey }
            .sorted(by: eventSort)

        let focus = firstTitledTask(in: doingTasks).map {
            ($0, LockScreenWidgetFocusKind.doingTask)
        } ?? firstTitledEvent(in: dayEvents).map {
            ($0, LockScreenWidgetFocusKind.event)
        } ?? firstTitledTask(in: todoTasks).map {
            ($0, LockScreenWidgetFocusKind.todoTask)
        }

        return LockScreenWidgetDaySummary(
            dayKey: dayKey,
            todoCount: todoTasks.count,
            doingCount: doingTasks.count,
            doneCount: doneTasks.count,
            eventCount: dayEvents.count,
            focusTitle: focus?.0,
            focusKind: focus?.1
        )
    }

    @MainActor
    private static func representativeTasks(from tasks: [Task]) -> [Task] {
        Dictionary(grouping: tasks, by: \.id).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.instanceID.uuidString < rhs.instanceID.uuidString
            }
        }
    }

    @MainActor
    private static func representativeEvents(from events: [CalendarEvent]) -> [CalendarEvent] {
        Dictionary(grouping: events, by: \.id).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.instanceID.uuidString < rhs.instanceID.uuidString
            }
        }
    }

    @MainActor
    private static func taskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        let lhsTitle = normalizedTitle(lhs.title)
        let rhsTitle = normalizedTitle(rhs.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    @MainActor
    private static func eventSort(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDayKey != rhs.startDayKey {
            return lhs.startDayKey < rhs.startDayKey
        }
        if lhs.endDayKey != rhs.endDayKey {
            return lhs.endDayKey > rhs.endDayKey
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

    @MainActor
    private static func firstTitledTask(in tasks: [Task]) -> String? {
        tasks.lazy
            .map { normalizedTitle($0.title) }
            .first(where: { !$0.isEmpty })
    }

    @MainActor
    private static func firstTitledEvent(in events: [CalendarEvent]) -> String? {
        events.lazy
            .map { normalizedTitle($0.title) }
            .first(where: { !$0.isEmpty })
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
