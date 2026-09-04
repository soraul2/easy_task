import Foundation

public enum ArchiveContentMode: String, CaseIterable, Identifiable, Sendable {
    case dailyActivity
    case completionHistory

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dailyActivity: "하루 활동"
        case .completionHistory: "완료 작업"
        }
    }
}

public struct DailyActivityEvidence: Equatable, Sendable {
    public var completed = false
    public var legacyCompletion = false
    public var started = false
    public var progressSeconds: TimeInterval = 0
    public var unknownProgress = false
    public var focusSeconds = 0
    public var focusSessionCount = 0

    public init() {}

    public var hasActivity: Bool {
        completed || legacyCompletion || started || progressSeconds > 0 || focusSessionCount > 0
    }

    public var summary: String {
        var parts: [String] = []
        if completed { parts.append("이날 완료") } else if legacyCompletion { parts.append("이전 완료 기록") }
        if progressSeconds > 0 {
            parts.append("진행 상태 \(TaskProgressEventRules.durationText(for: progressSeconds))")
        } else if started {
            parts.append("진행 시작")
        }
        if unknownProgress { parts.append("일부 시간 기록 없음") }
        if focusSessionCount > 0 {
            parts.append("집중 \(TaskProgressEventRules.durationText(for: TimeInterval(focusSeconds)))")
        }
        return parts.joined(separator: " · ")
    }
}

public struct DailyActivityEntry: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var evidence: DailyActivityEvidence
    public var canOpenTask: Bool
    public var matchingChecklistTitles: [String]
    public var searchQuery: String

    public init(
        id: UUID,
        title: String,
        note: String? = nil,
        evidence: DailyActivityEvidence,
        canOpenTask: Bool = true,
        matchingChecklistTitles: [String] = [],
        searchQuery: String = ""
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.evidence = evidence
        self.canOpenTask = canOpenTask
        self.matchingChecklistTitles = matchingChecklistTitles
        self.searchQuery = searchQuery
    }
}

/// Detached values let the archive index events without retaining a table of SwiftData models.
public struct TaskProgressEventSnapshot: Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var taskId: UUID
    public var kindRawValue: String
    public var originRawValue: String
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var supersededAt: Date?

    public init(_ event: TaskProgressEvent) {
        id = event.id
        instanceID = event.instanceID
        taskId = event.taskId
        kindRawValue = event.kindRawValue
        originRawValue = event.originRawValue
        occurredAt = event.occurredAt
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        supersededAt = event.supersededAt
    }
}
