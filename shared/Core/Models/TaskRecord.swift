import Foundation

public struct TaskRecordSelection: Identifiable, Hashable, Sendable {
    public let taskID: UUID
    public let dayKey: String
    public var id: String { "\(taskID.uuidString)-\(dayKey)" }

    public init(taskID: UUID, dayKey: String) {
        self.taskID = taskID
        self.dayKey = dayKey
    }
}

struct TaskRecord {
    var title: String
    var hasCurrentTask: Bool
    var currentStatus: String?
    var createdAt: Date?
    var plannedDayKey: String?
    var recordedCompletionDayKey: String?
    var firstStartedAt: Date?
    var latestCompletedAt: Date?
    var selectedDay: DailyActivityEvidence
    var progress: TaskProgressProjection
    var focusedSeconds: Int
    var focusSessionCount: Int
    var checklist: ChecklistProgress
    var note: String?
    var timeline: [TaskRecordEvent]
}

struct TaskRecordEvent: Identifiable {
    enum Kind { case created, progress, focus, completed, legacyCompletion, openProgress, unknownProgress }

    var id: String
    var kind: Kind
    var dayKey: String
    var startedAt: Date?
    var endedAt: Date?
    var duration: TimeInterval?
    var focusOutcome: FocusSessionOutcome?

    var sortDate: Date { endedAt ?? startedAt ?? DayKey.date(from: dayKey) ?? .distantPast }
}
