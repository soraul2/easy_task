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

        private enum CodingKeys: String, CodingKey {
            case taskSessionID
            case taskID
            case title
            case completedCount
            case totalCount
            case hasNextTask
            case requiresCompletionConfirmation

            // build 44 used this wire key for the current session start.
            // Keeping it allows an in-flight Live Activity to survive an app update.
            case elapsedTimerStartedAt = "updatedAt"
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
