import Foundation

public struct TaskProgressInterval: Equatable, Sendable {
    public var startedAt: Date
    public var stoppedAt: Date

    public init(startedAt: Date, stoppedAt: Date) {
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
    }

    public var duration: TimeInterval {
        max(0, stoppedAt.timeIntervalSince(startedAt))
    }
}

public struct TaskProgressProjection: Equatable, Sendable {
    public var intervals: [TaskProgressInterval]
    public var currentStartedAt: Date?
    public var hasUnknownDuration: Bool
    public var recordedStarts: [Date]
    public var unknownIntervalStarts: [Date]

    public init(
        intervals: [TaskProgressInterval] = [],
        currentStartedAt: Date? = nil,
        hasUnknownDuration: Bool = false,
        recordedStarts: [Date] = [],
        unknownIntervalStarts: [Date] = []
    ) {
        self.intervals = intervals
        self.currentStartedAt = currentStartedAt
        self.hasUnknownDuration = hasUnknownDuration
        self.recordedStarts = recordedStarts
        self.unknownIntervalStarts = unknownIntervalStarts
    }

    public var recordedDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    public func elapsedDuration(at now: Date) -> TimeInterval {
        guard let currentStartedAt else { return recordedDuration }
        return recordedDuration + max(0, now.timeIntervalSince(currentStartedAt))
    }
}

public enum TaskProgressEventRules {
    public static func eventKind(
        from oldStatus: TaskStatus,
        to newStatus: TaskStatus
    ) -> TaskProgressEventKind? {
        guard oldStatus != newStatus else { return nil }
        switch (oldStatus, newStatus) {
        case (.todo, .doing), (.done, .doing):
            return .started
        case (.doing, .todo), (.doing, .done), (.done, .todo), (.todo, .done):
            return .stopped
        case (.todo, .todo), (.doing, .doing), (.done, .done):
            return nil
        }
    }

    public static func projection(
        for events: [TaskProgressEvent]
    ) -> TaskProgressProjection {
        projection(snapshots: events.map(TaskProgressEventSnapshot.init))
    }

    public static func projection(
        snapshots events: [TaskProgressEventSnapshot]
    ) -> TaskProgressProjection {
        let representatives = Dictionary(grouping: events.filter { $0.supersededAt == nil }, by: \.id)
            .compactMap { _, candidates in
                candidates.max(by: eventIsOlder)
            }
            .filter {
                TaskProgressEventKind(rawValue: $0.kindRawValue) != nil &&
                    TaskProgressEventOrigin(rawValue: $0.originRawValue) != nil
            }
            .sorted(by: eventComesBefore)

        var intervals: [TaskProgressInterval] = []
        var activeStart: Date?
        var hasUnknownDuration = false
        var recordedStarts: [Date] = []
        var unknownIntervalStarts: [Date] = []

        for event in representatives {
            guard let kind = TaskProgressEventKind(rawValue: event.kindRawValue),
                  let origin = TaskProgressEventOrigin(rawValue: event.originRawValue) else {
                continue
            }

            switch kind {
            case .started:
                if activeStart == nil {
                    activeStart = event.occurredAt
                    recordedStarts.append(event.occurredAt)
                }
            case .stopped:
                guard let startedAt = activeStart,
                      event.occurredAt >= startedAt else {
                    continue
                }
                if origin == .compatibilityBoundary {
                    hasUnknownDuration = true
                    unknownIntervalStarts.append(startedAt)
                } else {
                    intervals.append(TaskProgressInterval(
                        startedAt: startedAt,
                        stoppedAt: event.occurredAt
                    ))
                }
                activeStart = nil
            }
        }

        return TaskProgressProjection(
            intervals: intervals,
            currentStartedAt: activeStart,
            hasUnknownDuration: hasUnknownDuration,
            recordedStarts: recordedStarts,
            unknownIntervalStarts: unknownIntervalStarts
        )
    }

    public static func durationText(for duration: TimeInterval) -> String {
        let totalMinutes = Int(max(0, duration) / 60)
        guard totalMinutes > 0 else { return "1분 미만" }

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간"
        }
        return "\(minutes)분"
    }

    public static func startTimeText(
        for date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func detailText(
        projection: TaskProgressProjection,
        status: TaskStatus,
        now: Date = Date(),
        completedAt: Date? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        if status == .doing, let currentStartedAt = projection.currentStartedAt {
            let start = startTimeText(for: currentStartedAt, locale: locale, timeZone: timeZone)
            let duration = durationText(for: projection.elapsedDuration(at: now))
            return "\(start) 시작 · 진행 누적 \(duration)"
        }

        if status == .doing {
            let recorded = projection.recordedDuration
            return recorded > 0
                ? "진행 누적 \(durationText(for: recorded)) · 현재 시작 시각 기록 없음"
                : "진행 시작 시각 기록 없음"
        }

        if projection.hasUnknownDuration {
            if status == .done, let completedAt {
                let completion = startTimeText(
                    for: completedAt,
                    locale: locale,
                    timeZone: timeZone
                )
                return "\(completion) 완료 · 일부 진행 시간 기록 없음"
            }
            return "일부 진행 시간 기록 없음"
        }

        let duration = projection.recordedDuration
        guard let firstInterval = projection.intervals.first,
              let lastInterval = projection.intervals.last else { return nil }
        let ending = status == .done ? "완료" : "진행 중단"
        let start = startTimeText(
            for: firstInterval.startedAt,
            locale: locale,
            timeZone: timeZone
        )
        let completion = startTimeText(
            for: status == .done ? (completedAt ?? lastInterval.stoppedAt) : lastInterval.stoppedAt,
            locale: locale,
            timeZone: timeZone
        )
        return "\(start) 시작 · \(completion) \(ending) · 진행 누적 \(durationText(for: duration))"
    }

    private static func eventIsOlder(
        _ lhs: TaskProgressEventSnapshot,
        _ rhs: TaskProgressEventSnapshot
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    private static func eventComesBefore(
        _ lhs: TaskProgressEventSnapshot,
        _ rhs: TaskProgressEventSnapshot
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        let lhsPriority = lhs.kindRawValue == TaskProgressEventKind.stopped.rawValue ? 0 : 1
        let rhsPriority = rhs.kindRawValue == TaskProgressEventKind.stopped.rawValue ? 0 : 1
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
