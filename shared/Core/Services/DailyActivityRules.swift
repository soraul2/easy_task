import Foundation

public enum DailyActivityRules {
    /// Closed intervals are clipped to a calendar day; open intervals only establish a start fact.
    public static func progressEvidence(
        _ projection: TaskProgressProjection,
        on date: Date,
        calendar: Calendar = DayKey.calendar
    ) -> DailyActivityEvidence {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return DailyActivityEvidence()
        }
        var result = DailyActivityEvidence()
        result.started = projection.recordedStarts.contains { start <= $0 && $0 < end }
        result.unknownProgress = projection.unknownIntervalStarts.contains { start <= $0 && $0 < end }
        result.progressSeconds = projection.intervals.reduce(0) { sum, interval in
            sum + max(0, min(end, interval.stoppedAt).timeIntervalSince(max(start, interval.startedAt)))
        }
        return result
    }
}
