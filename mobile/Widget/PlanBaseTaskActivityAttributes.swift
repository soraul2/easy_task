#if os(iOS)
import ActivityKit
import Foundation

/// Derived presentation only: never encoded into the ActivityKit payload or persisted.
enum TaskActivityTimerPresentation: Hashable, Sendable {
    case todo
    case elapsed(startedAt: Date)
    case countdown(interval: ClosedRange<Date>)
    case paused(remainingSeconds: TimeInterval)
    case invalid(Reason)

    enum Reason: String, Hashable, Sendable {
        case invalidStart, incompleteFocus, invalidFocusState, invalidDeadline, invalidRemainingTime
    }
}

struct TaskActivityTimerIdentity: Hashable {
    let taskSessionID: String
    let taskID: UUID
    let focusSessionID: UUID?
    let focusRevision: Int?
    let presentation: TaskActivityTimerPresentation
}

struct PlanBaseTaskActivityAttributes: ActivityAttributes {
#if DEBUG
    // A test-only attribute marker lets the extension show a native control
    // beside the real timer without adding fields to the production payload.
    static let timerAuditActivityID = UUID(uuidString: "27A00000-0000-4000-8000-000000000001")!
#endif
    struct ContentState: Codable, Hashable, Sendable {
        let taskSessionID: String
        let taskID: UUID
        let title: String
        let completedCount: Int
        let totalCount: Int
        let hasNextTask: Bool
        let requiresCompletionConfirmation: Bool
        let elapsedTimerStartedAt: Date
        let themeID: String?
        let taskStatusRawValue: String?
        let focusSessionID: UUID?
        let focusRevision: Int?
        let focusPhaseRawValue: String?
        let focusRunStateRawValue: String?
        let focusDeadline: Date?
        let focusRemainingSecondsAtPause: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case taskSessionID
            case taskID
            case title
            case completedCount
            case totalCount
            case hasNextTask
            case requiresCompletionConfirmation
            case themeID
            case taskStatusRawValue
            case focusSessionID
            case focusRevision
            case focusPhaseRawValue
            case focusRunStateRawValue
            case focusDeadline
            case focusRemainingSecondsAtPause

            // build 44 used this wire key for the current session start.
            // Keeping it allows an in-flight Live Activity to survive an app update.
            case elapsedTimerStartedAt = "updatedAt"
        }

        init(
            taskSessionID: String,
            taskID: UUID,
            title: String,
            completedCount: Int,
            totalCount: Int,
            hasNextTask: Bool,
            requiresCompletionConfirmation: Bool,
            elapsedTimerStartedAt: Date,
            themeID: String? = nil,
            taskStatusRawValue: String? = nil,
            focusSessionID: UUID? = nil,
            focusRevision: Int? = nil,
            focusPhaseRawValue: String? = nil,
            focusRunStateRawValue: String? = nil,
            focusDeadline: Date? = nil,
            focusRemainingSecondsAtPause: TimeInterval? = nil
        ) {
            self.taskSessionID = taskSessionID
            self.taskID = taskID
            self.title = title
            self.completedCount = completedCount
            self.totalCount = totalCount
            self.hasNextTask = hasNextTask
            self.requiresCompletionConfirmation = requiresCompletionConfirmation
            self.elapsedTimerStartedAt = elapsedTimerStartedAt
            self.themeID = themeID
            self.taskStatusRawValue = taskStatusRawValue
            self.focusSessionID = focusSessionID
            self.focusRevision = focusRevision
            self.focusPhaseRawValue = focusPhaseRawValue
            self.focusRunStateRawValue = focusRunStateRawValue
            self.focusDeadline = focusDeadline
            self.focusRemainingSecondsAtPause = focusRemainingSecondsAtPause
        }

        var isTodo: Bool { !isFocusSession && taskStatusRawValue == "todo" }

        var isFocusSession: Bool {
            focusSessionID != nil && focusRevision != nil
        }

        var isFocusPaused: Bool {
            focusRunStateRawValue == "paused"
        }

        var timerPresentation: TaskActivityTimerPresentation {
            // Partially decoded Focus metadata must not silently become an ordinary stopwatch.
            let hasFocusMetadata = focusSessionID != nil || focusRevision != nil
                || focusPhaseRawValue != nil || focusRunStateRawValue != nil
                || focusDeadline != nil || focusRemainingSecondsAtPause != nil
            if !hasFocusMetadata, isTodo { return .todo }
            guard elapsedTimerStartedAt.timeIntervalSinceReferenceDate.isFinite else {
                return .invalid(.invalidStart)
            }
            guard hasFocusMetadata else { return .elapsed(startedAt: elapsedTimerStartedAt) }
            guard focusSessionID != nil, let focusRevision, focusRevision > 0,
                  focusPhaseRawValue == "focus" || focusPhaseRawValue == "breakTime" else {
                return .invalid(.incompleteFocus)
            }
            switch focusRunStateRawValue {
            case "running":
                guard let focusDeadline, focusDeadline.timeIntervalSinceReferenceDate.isFinite,
                      focusDeadline >= elapsedTimerStartedAt,
                      focusRemainingSecondsAtPause == nil else {
                    return .invalid(.invalidDeadline)
                }
                // The native countdown clamps at the upper bound, even after the deadline.
                return .countdown(interval: elapsedTimerStartedAt...focusDeadline)
            case "paused":
                guard focusDeadline == nil, let remaining = focusRemainingSecondsAtPause,
                      remaining.isFinite, remaining >= 0, remaining < Double(Int64.max) else {
                    return .invalid(.invalidRemainingTime)
                }
                return .paused(remainingSeconds: remaining)
            default:
                return .invalid(.invalidFocusState)
            }
        }

        var timerIdentity: TaskActivityTimerIdentity {
            TaskActivityTimerIdentity(taskSessionID: taskSessionID, taskID: taskID,
                                      focusSessionID: focusSessionID, focusRevision: focusRevision,
                                      presentation: timerPresentation)
        }

        var progressValue: Double {
            guard totalCount > 0 else { return 0 }
            return min(1, max(0, Double(completedCount) / Double(totalCount)))
        }

        var progressText: String {
            "\(completedCount)/\(totalCount)"
        }
    }

    let activityID: UUID
    let dayKey: String
    let createdAt: Date?

    init(activityID: UUID, dayKey: String, createdAt: Date? = nil) {
        self.activityID = activityID
        self.dayKey = dayKey
        self.createdAt = createdAt
    }
}
#endif
