import Foundation
import SwiftData

public struct TaskLifecycleTransitionResult: Equatable, Sendable {
    public var didChange: Bool
    public var didComplete: Bool
    public var activityInserted: Bool
    public var progressEventKind: TaskProgressEventKind?

    public init(
        didChange: Bool,
        didComplete: Bool,
        activityInserted: Bool,
        progressEventKind: TaskProgressEventKind? = nil
    ) {
        self.didChange = didChange
        self.didComplete = didComplete
        self.activityInserted = activityInserted
        self.progressEventKind = progressEventKind
    }

    public static let unchanged = TaskLifecycleTransitionResult(
        didChange: false,
        didComplete: false,
        activityInserted: false,
        progressEventKind: nil
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
        let progressEvent = TaskProgressEventService.recordTransition(
            taskID: task.id,
            from: oldStatus,
            to: status,
            occurredAt: now,
            in: context
        )
        return TaskLifecycleTransitionResult(
            didChange: true,
            didComplete: didComplete,
            activityInserted: activity != nil,
            progressEventKind: progressEvent.flatMap {
                TaskProgressEventKind(rawValue: $0.kindRawValue)
            }
        )
    }

    @MainActor
    @discardableResult
    public static func bringToToday(
        _ task: Task,
        in context: ModelContext,
        order: Double? = nil,
        now: Date = Date()
    ) throws -> TaskLifecycleTransitionResult {
        guard task.supersededAt == nil else { return .unchanged }
        let status = TaskStatus(rawValue: task.status) ?? .todo
        let transition = status == .doing
            ? try applyStatus(.todo, to: task, in: context, now: now)
            : .unchanged
        let previousDayKey = task.plannedDayKey
        let previousOrder = task.order
        TaskRules.move(task, to: now, order: order, now: now)
        guard previousDayKey != task.plannedDayKey || previousOrder != task.order else {
            return transition
        }
        return TaskLifecycleTransitionResult(
            didChange: true,
            didComplete: transition.didComplete,
            activityInserted: transition.activityInserted,
            progressEventKind: transition.progressEventKind
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
