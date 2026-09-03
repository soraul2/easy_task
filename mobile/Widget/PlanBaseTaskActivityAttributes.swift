#if os(iOS)
import ActivityKit
import Foundation

struct PlanBaseTaskActivityAttributes: ActivityAttributes {
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
            self.focusSessionID = focusSessionID
            self.focusRevision = focusRevision
            self.focusPhaseRawValue = focusPhaseRawValue
            self.focusRunStateRawValue = focusRunStateRawValue
            self.focusDeadline = focusDeadline
            self.focusRemainingSecondsAtPause = focusRemainingSecondsAtPause
        }

        var isFocusSession: Bool {
            focusSessionID != nil && focusRevision != nil
        }

        var isFocusPaused: Bool {
            focusRunStateRawValue == "paused"
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
}
#endif
