import Foundation

public enum DailyActivityRules {
    /// Visit days containing evidence instead of scanning every day for every task.
    /// Calendar boundaries preserve 23/25-hour days and closed-interval semantics.
    public static func progressEvidenceByDay(
        _ projection: TaskProgressProjection,
        from lowerDate: Date,
        through upperDate: Date,
        calendar: Calendar = DayKey.calendar
    ) -> [Date: DailyActivityEvidence] {
        let lower = calendar.startOfDay(for: lowerDate)
        let last = calendar.startOfDay(for: upperDate)
        guard lower <= last,
              let upper = calendar.date(byAdding: .day, value: 1, to: last) else { return [:] }
        var evidence: [Date: DailyActivityEvidence] = [:]
        for start in projection.recordedStarts where lower <= start && start < upper {
            evidence[calendar.startOfDay(for: start), default: .init()].started = true
        }
        for start in projection.unknownIntervalStarts where lower <= start && start < upper {
            evidence[calendar.startOfDay(for: start), default: .init()].unknownProgress = true
        }
        for interval in projection.intervals {
            let start = max(lower, interval.startedAt)
            let end = min(upper, interval.stoppedAt)
            guard start < end else { continue }
            var day = calendar.startOfDay(for: start)
            while day < end {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                evidence[day, default: .init()].progressSeconds +=
                    min(next, end).timeIntervalSince(max(day, start))
                day = next
            }
        }
        return evidence
    }

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
