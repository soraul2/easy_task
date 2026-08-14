import Foundation
import SwiftData

public enum TaskActivityService {
    @MainActor
    @discardableResult
    public static func recordCapturedCompletion(
        taskID: UUID,
        occurredAt: Date,
        in context: ModelContext
    ) throws -> TaskCompletionActivity? {
        try record(
            taskID: taskID,
            activityDayKey: DayKey.key(for: occurredAt),
            occurredAt: occurredAt,
            origin: .captured,
            createdAt: occurredAt,
            in: context
        )
    }

    @MainActor
    @discardableResult
    public static func record(
        taskID: UUID,
        activityDayKey: String,
        occurredAt: Date,
        origin: TaskCompletionActivityOrigin,
        createdAt: Date = Date(),
        in context: ModelContext
    ) throws -> TaskCompletionActivity? {
        let existing = try context.fetch(activeDescriptor(
            taskID: taskID,
            activityDayKey: activityDayKey
        ))
        if existing.contains(where: {
            TaskActivityRules.origin(for: $0.originRawValue) == .captured
        }) || origin == .legacyBackfill && !existing.isEmpty {
            return nil
        }

        let activity = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(
                taskID: taskID,
                activityDayKey: activityDayKey
            ),
            taskId: taskID,
            activityDayKey: activityDayKey,
            occurredAt: occurredAt,
            origin: origin,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        context.insert(activity)
        return activity
    }

    public static func activeDescriptor(
        taskID: UUID,
        activityDayKey: String
    ) -> FetchDescriptor<TaskCompletionActivity> {
        FetchDescriptor(
            predicate: #Predicate<TaskCompletionActivity> { activity in
                activity.supersededAt == nil &&
                    activity.taskId == taskID &&
                    activity.activityDayKey == activityDayKey
            },
            sortBy: [
                SortDescriptor(\TaskCompletionActivity.updatedAt, order: .reverse),
                SortDescriptor(\TaskCompletionActivity.instanceID, order: .reverse)
            ]
        )
    }
}
