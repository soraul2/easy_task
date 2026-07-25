import Foundation

public struct ArchiveRecordSummary: Equatable, Sendable {
    public var dayCount: Int
    public var reviewCount: Int
    public var completedTaskCount: Int

    public init(
        dayCount: Int,
        reviewCount: Int,
        completedTaskCount: Int
    ) {
        self.dayCount = dayCount
        self.reviewCount = reviewCount
        self.completedTaskCount = completedTaskCount
    }

    public init(records: [ArchiveDayRecord]) {
        dayCount = records.count
        reviewCount = records.lazy.filter { $0.review != nil }.count
        completedTaskCount = records.lazy.reduce(0) { $0 + $1.tasks.count }
    }
}

public struct TaskHistoryDatePresentation: Equatable, Sendable {
    public var text: String
    public var accessibilityLabel: String
    public var bestEffortExplanation: String?

    public init(task: Task, calendar: Calendar = DayKey.calendar) {
        let plannedText = Self.shortDate(task.plannedDayKey, calendar: calendar)
        let completion = TaskHistoryDateRules.completionDate(
            for: task,
            calendar: calendar
        )

        guard completion.isRecordedCompletionDate else {
            text = "계획 \(plannedText) · 완료일 기록 없음"
            accessibilityLabel = "계획일 \(plannedText), 완료일 기록 없음"
            bestEffortExplanation = nil
            return
        }

        let completedText = Self.shortDate(completion.dayKey, calendar: calendar)
        if task.plannedDayKey == completion.dayKey {
            text = "계획·완료 \(completedText)"
        } else {
            text = "계획 \(plannedText) · 완료 \(completedText)"
        }
        accessibilityLabel = "계획일 \(plannedText), 완료일 \(completedText)"
        bestEffortExplanation = completion.isBestEffort
            ? TaskHistoryDateRules.completedAtFallbackExplanation
            : nil
    }

    private static func shortDate(_ dayKey: String, calendar: Calendar) -> String {
        guard let date = date(from: dayKey, calendar: calendar) else {
            return dayKey
        }
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else {
            return dayKey
        }
        return "\(month)월 \(day)일"
    }

    private static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }
}
