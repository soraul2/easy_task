import Foundation
import SwiftData

public struct TaskLifecycleTransitionResult: Equatable, Sendable {
    public var didChange: Bool
    public var didComplete: Bool
    public var activityInserted: Bool

    public init(
        didChange: Bool,
        didComplete: Bool,
        activityInserted: Bool
    ) {
        self.didChange = didChange
        self.didComplete = didComplete
        self.activityInserted = activityInserted
    }

    public static let unchanged = TaskLifecycleTransitionResult(
        didChange: false,
        didComplete: false,
        activityInserted: false
    )
}

public enum TaskLifecycleService {
    @MainActor
    @discardableResult
    public static func applyStatus(
        _ status: TaskStatus,
        to task: Task,
        in context: ModelContext,
        now: Date = Date(),
        completionDayKey: String? = nil
    ) throws -> TaskLifecycleTransitionResult {
        guard task.supersededAt == nil else { return .unchanged }
        let oldStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard oldStatus != status else { return .unchanged }

        TaskRules.applyStatus(
            status,
            to: task,
            now: now,
            completionDayKey: completionDayKey
        )
        let didComplete = oldStatus != .done && status == .done
        let activity = didComplete
            ? try TaskActivityService.recordCapturedCompletion(
                taskID: task.id,
                occurredAt: now,
                in: context
            )
            : nil
        return TaskLifecycleTransitionResult(
            didChange: true,
            didComplete: didComplete,
            activityInserted: activity != nil
        )
    }

    @MainActor
    @discardableResult
    public static func completeOnPlannedDays(
        _ tasks: [Task],
        in context: ModelContext,
        now: Date = Date()
    ) throws -> [TaskLifecycleTransitionResult] {
        try tasks.map { task in
            try applyStatus(
                .done,
                to: task,
                in: context,
                now: now,
                completionDayKey: task.plannedDayKey
            )
        }
    }
}
