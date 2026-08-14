import CryptoKit
import Foundation

public struct TaskActivitySnapshot: Equatable, Hashable, Sendable {
    public var taskID: UUID
    public var activityDayKey: String

    public init(taskID: UUID, activityDayKey: String) {
        self.taskID = taskID
        self.activityDayKey = activityDayKey
    }
}

public enum ActivityIntensityLevel: Int, CaseIterable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case veryHigh = 4
}

public enum ActivityTodayState: Equatable, Sendable {
    case completed
    case waitingToContinue
    case readyToStart
    case readyToRestart

    public var message: String {
        switch self {
        case .completed:
            "오늘도 기록을 이어갔어요"
        case .waitingToContinue:
            "오늘 작업을 완료하면 이어져요"
        case .readyToStart:
            "작업을 완료하면 활동 기록이 시작돼요"
        case .readyToRestart:
            "오늘부터 다시 시작할 수 있어요"
        }
    }
}

public struct ActivityHeatmapRange: Equatable, Sendable {
    public var weekCount: Int
    public var startDayKey: String
    public var endDayKey: String
    public var todayDayKey: String

    public init(
        weekCount: Int,
        startDayKey: String,
        endDayKey: String,
        todayDayKey: String
    ) {
        self.weekCount = weekCount
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.todayDayKey = todayDayKey
    }
}

public struct ActivityDaySummary: Equatable, Sendable {
    public var dayKey: String
    public var completedTaskCount: Int
    public var intensity: ActivityIntensityLevel
    public var isFuture: Bool
    public var isInCurrentStreak: Bool

    public init(
        dayKey: String,
        completedTaskCount: Int,
        intensity: ActivityIntensityLevel,
        isFuture: Bool,
        isInCurrentStreak: Bool
    ) {
        self.dayKey = dayKey
        self.completedTaskCount = completedTaskCount
        self.intensity = intensity
        self.isFuture = isFuture
        self.isInCurrentStreak = isInCurrentStreak
    }
}

public struct ActivityWeekSummary: Equatable, Sendable {
    public var startDayKey: String
    public var days: [ActivityDaySummary]

    public init(startDayKey: String, days: [ActivityDaySummary]) {
        self.startDayKey = startDayKey
        self.days = days
    }
}

public struct ActivityOverview: Equatable, Sendable {
    public var range: ActivityHeatmapRange?
    public var weeks: [ActivityWeekSummary]
    public var currentStreak: Int
    public var bestStreakInLastYear: Int
    public var todayState: ActivityTodayState
    public var activeDayCount: Int

    public init(
        range: ActivityHeatmapRange? = nil,
        weeks: [ActivityWeekSummary] = [],
        currentStreak: Int = 0,
        bestStreakInLastYear: Int = 0,
        todayState: ActivityTodayState = .readyToStart,
        activeDayCount: Int = 0
    ) {
        self.range = range
        self.weeks = weeks
        self.currentStreak = currentStreak
        self.bestStreakInLastYear = bestStreakInLastYear
        self.todayState = todayState
        self.activeDayCount = activeDayCount
    }

    public var days: [ActivityDaySummary] {
        weeks.flatMap(\.days)
    }
}

public enum TaskActivityRules {
    public static let compactWeekCount = 26
    public static let regularWeekCount = 52
    public static let bestStreakDayCount = 365

    public static func logicalID(
        taskID: UUID,
        activityDayKey: String
    ) -> UUID {
        let canonical = taskID.uuidString.lowercased() + "|" + activityDayKey
        var bytes = Array(SHA256.hash(data: Data(canonical.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func origin(
        for rawValue: String
    ) -> TaskCompletionActivityOrigin? {
        TaskCompletionActivityOrigin(rawValue: rawValue)
    }

    public static func legacyDayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return DayKey.key(for: date, calendar: calendar)
    }

    public static func representsSameCompletion(
        _ lhs: Date,
        _ rhs: Date,
        tolerance: TimeInterval = 1
    ) -> Bool {
        guard lhs.timeIntervalSinceReferenceDate.isFinite,
              rhs.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        return abs(lhs.timeIntervalSince(rhs)) <= tolerance
    }

    public static func intensity(for completedTaskCount: Int) -> ActivityIntensityLevel {
        switch completedTaskCount {
        case ...0:
            .none
        case 1:
            .low
        case 2:
            .medium
        case 3...4:
            .high
        default:
            .veryHigh
        }
    }

    public static func heatmapRange(
        weekCount: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = DayKey.calendar
    ) -> ActivityHeatmapRange {
        let resolvedWeekCount = max(1, weekCount)
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: today
        ) ?? today
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -(resolvedWeekCount - 1) * 7,
            to: currentWeekStart
        ) ?? currentWeekStart
        let rangeEnd = calendar.date(
            byAdding: .day,
            value: 6,
            to: currentWeekStart
        ) ?? today
        return ActivityHeatmapRange(
            weekCount: resolvedWeekCount,
            startDayKey: DayKey.key(for: rangeStart, calendar: calendar),
            endDayKey: DayKey.key(for: rangeEnd, calendar: calendar),
            todayDayKey: DayKey.key(for: today, calendar: calendar)
        )
    }

    public static func overview(
        from snapshots: [TaskActivitySnapshot],
        weekCount: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = DayKey.calendar,
        hasEarlierActivity: Bool = false
    ) -> ActivityOverview {
        let range = heatmapRange(
            weekCount: weekCount,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let counts = uniqueTaskCountsByDay(snapshots)
        let activeDayKeys = Set(counts.compactMap { key, count in
            count > 0 && key <= range.todayDayKey ? key : nil
        })
        let yesterdayKey = addingDays(
            -1,
            to: range.todayDayKey,
            calendar: calendar
        )
        let currentAnchor: String?
        let todayState: ActivityTodayState
        if activeDayKeys.contains(range.todayDayKey) {
            currentAnchor = range.todayDayKey
            todayState = .completed
        } else if let yesterdayKey, activeDayKeys.contains(yesterdayKey) {
            currentAnchor = yesterdayKey
            todayState = .waitingToContinue
        } else {
            currentAnchor = nil
            todayState = activeDayKeys.isEmpty && !hasEarlierActivity
                ? .readyToStart
                : .readyToRestart
        }

        let currentStreakKeys = streakKeys(
            endingAt: currentAnchor,
            activeDayKeys: activeDayKeys,
            calendar: calendar
        )
        let bestStreakStart = addingDays(
            -(bestStreakDayCount - 1),
            to: range.todayDayKey,
            calendar: calendar
        ) ?? range.todayDayKey
        let bestStreak = longestStreak(
            activeDayKeys: activeDayKeys,
            from: bestStreakStart,
            through: range.todayDayKey,
            calendar: calendar
        )

        var weeks: [ActivityWeekSummary] = []
        guard let startDate = date(from: range.startDayKey, calendar: calendar) else {
            return ActivityOverview(
                range: range,
                currentStreak: currentStreakKeys.count,
                bestStreakInLastYear: bestStreak,
                todayState: todayState
            )
        }
        for weekOffset in 0..<range.weekCount {
            var days: [ActivityDaySummary] = []
            for dayOffset in 0..<7 {
                let offset = weekOffset * 7 + dayOffset
                let date = calendar.date(byAdding: .day, value: offset, to: startDate)
                    ?? startDate
                let dayKey = DayKey.key(for: date, calendar: calendar)
                let count = counts[dayKey, default: 0]
                days.append(ActivityDaySummary(
                    dayKey: dayKey,
                    completedTaskCount: count,
                    intensity: intensity(for: count),
                    isFuture: dayKey > range.todayDayKey,
                    isInCurrentStreak: currentStreakKeys.contains(dayKey)
                ))
            }
            weeks.append(ActivityWeekSummary(
                startDayKey: days.first?.dayKey ?? range.startDayKey,
                days: days
            ))
        }

        let visibleActiveDays = weeks.flatMap(\.days).filter {
            !$0.isFuture && $0.completedTaskCount > 0
        }.count
        return ActivityOverview(
            range: range,
            weeks: weeks,
            currentStreak: currentStreakKeys.count,
            bestStreakInLastYear: bestStreak,
            todayState: todayState,
            activeDayCount: visibleActiveDays
        )
    }

    public static func uniqueTaskCountsByDay(
        _ snapshots: [TaskActivitySnapshot]
    ) -> [String: Int] {
        var taskIDsByDay: [String: Set<UUID>] = [:]
        for snapshot in snapshots {
            taskIDsByDay[snapshot.activityDayKey, default: []].insert(snapshot.taskID)
        }
        return taskIDsByDay.mapValues(\.count)
    }

    public static func dayKey(
        byAddingDays value: Int,
        to dayKey: String,
        calendar: Calendar = DayKey.calendar
    ) -> String? {
        addingDays(value, to: dayKey, calendar: calendar)
    }
}

private extension TaskActivityRules {
    static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
              )),
              DayKey.key(for: date, calendar: calendar) == dayKey else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    static func addingDays(
        _ value: Int,
        to dayKey: String,
        calendar: Calendar
    ) -> String? {
        guard let date = date(from: dayKey, calendar: calendar),
              let result = calendar.date(byAdding: .day, value: value, to: date) else {
            return nil
        }
        return DayKey.key(for: result, calendar: calendar)
    }

    static func streakKeys(
        endingAt endDayKey: String?,
        activeDayKeys: Set<String>,
        calendar: Calendar
    ) -> Set<String> {
        guard var cursor = endDayKey else { return [] }
        var result: Set<String> = []
        while activeDayKeys.contains(cursor) {
            result.insert(cursor)
            guard let previous = addingDays(-1, to: cursor, calendar: calendar) else {
                break
            }
            cursor = previous
        }
        return result
    }

    static func longestStreak(
        activeDayKeys: Set<String>,
        from lowerBound: String,
        through upperBound: String,
        calendar: Calendar
    ) -> Int {
        guard var cursor = date(from: lowerBound, calendar: calendar),
              let end = date(from: upperBound, calendar: calendar) else {
            return 0
        }
        var current = 0
        var best = 0
        while cursor <= end {
            let dayKey = DayKey.key(for: cursor, calendar: calendar)
            if activeDayKeys.contains(dayKey) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return best
    }
}
