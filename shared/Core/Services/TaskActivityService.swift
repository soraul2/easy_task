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
        if try hasBlockingActivity(
            taskID: taskID, activityDayKey: activityDayKey, origin: origin, in: context
        ) {
            return nil
        }

        return insertActivity(taskID: taskID, activityDayKey: activityDayKey,
                              occurredAt: occurredAt, origin: origin,
                              createdAt: createdAt, in: context)
    }

    /// Invocation-local pending values for synchronous backfill without a caller
    /// callback, await, or save. Never reused by public record() or across calls.
    @MainActor
    final class StableLegacyPendingProof {
        let contextID: ObjectIdentifier
        private(set) var physicalIDs: Set<PersistentIdentifier>
        private(set) var activeKeys: Set<TaskActivitySnapshot>

        init(in context: ModelContext) {
            contextID = ObjectIdentifier(context)
            let deleted = Set(context.deletedModelsArray.compactMap {
                ($0 as? TaskCompletionActivity)?.persistentModelID
            })
            let pending = (context.insertedModelsArray + context.changedModelsArray)
                .compactMap { $0 as? TaskCompletionActivity }
            physicalIDs = Set(pending.map(\.persistentModelID)).union(deleted)
            activeKeys = Set(pending.compactMap { activity in
                guard !deleted.contains(activity.persistentModelID),
                      activity.supersededAt == nil else { return nil }
                // Any active origin blocks legacy backfill, including unknown
                // origins. Keep the original raw natural key, not logical ID.
                return TaskActivitySnapshot(taskID: activity.taskId,
                                            activityDayKey: activity.activityDayKey)
            })
        }

        func inserted(_ activity: TaskCompletionActivity, key: TaskActivitySnapshot) {
            physicalIDs.insert(activity.persistentModelID)
            activeKeys.insert(key)
        }
    }

    @MainActor
    static func recordLegacyCompletion(
        taskID: UUID, activityDayKey: String, occurredAt: Date, createdAt: Date,
        in context: ModelContext, pending: StableLegacyPendingProof
    ) throws -> TaskCompletionActivity? {
        assert(pending.contextID == ObjectIdentifier(context))
        var descriptor = activeDescriptor(taskID: taskID, activityDayKey: activityDayKey)
        descriptor.includePendingChanges = false
        descriptor.sortBy = []
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        // Always query the entire saved key first. No saved absence/positive
        // cache is introduced here, and authoritative errors still propagate.
        let savedIDs = try reader.fetchIdentifiers(descriptor)
        let key = TaskActivitySnapshot(taskID: taskID, activityDayKey: activityDayKey)
        if savedIDs.contains(where: { !pending.physicalIDs.contains($0) }) ||
            pending.activeKeys.contains(key) {
            return nil
        }
        let activity = insertActivity(taskID: taskID, activityDayKey: activityDayKey,
                                      occurredAt: occurredAt, origin: .legacyBackfill,
                                      createdAt: createdAt, in: context)
        // Insert immediately, preserving pending/partial-error semantics. A
        // reference owner avoids copying growing Set storage on each insert.
        pending.inserted(activity, key: key)
        return activity
    }

    @MainActor
    private static func insertActivity(
        taskID: UUID, activityDayKey: String, occurredAt: Date,
        origin: TaskCompletionActivityOrigin, createdAt: Date,
        in context: ModelContext
    ) -> TaskCompletionActivity {
        let activity = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: activityDayKey),
            taskId: taskID, activityDayKey: activityDayKey, occurredAt: occurredAt,
            origin: origin, createdAt: createdAt, updatedAt: createdAt
        )
        context.insert(activity)
        return activity
    }


    @MainActor
    private static func hasBlockingActivity(
        taskID: UUID,
        activityDayKey: String,
        origin: TaskCompletionActivityOrigin,
        in context: ModelContext
    ) throws -> Bool {
        if !context.hasChanges {
            let existing = try context.fetch(activeDescriptor(
                taskID: taskID, activityDayKey: activityDayKey
            ))
            return existing.contains {
                TaskActivityRules.origin(for: $0.originRawValue) == .captured
            } || origin == .legacyBackfill && !existing.isEmpty
        }

        let capturedOrigin = TaskCompletionActivityOrigin.captured.rawValue
        var descriptor = activeDescriptor(taskID: taskID, activityDayKey: activityDayKey)
        if origin == .captured {
            descriptor.predicate = #Predicate<TaskCompletionActivity> { activity in
                activity.supersededAt == nil &&
                    activity.taskId == taskID &&
                    activity.activityDayKey == activityDayKey &&
                    activity.originRawValue == capturedOrigin
            }
        }
        descriptor.includePendingChanges = false
        descriptor.sortBy = []
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        // The complete saved natural key is queried on every call. A separate
        // read graph avoids hydrating or evaluating the caller's pending models.
        let savedIDs = try reader.fetchIdentifiers(descriptor)
        let pending = (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? TaskCompletionActivity }
        let deletedIDs = Set(context.deletedModelsArray.compactMap {
            ($0 as? TaskCompletionActivity)?.persistentModelID
        })
        if !savedIDs.isEmpty {
            // A pending row moved out of this key must still exclude its saved
            // physical copy. No current-key filter is applied to this overlay.
            let excludedIDs = Set(pending.map(\.persistentModelID)).union(deletedIDs)
            if savedIDs.contains(where: { !excludedIDs.contains($0) }) { return true }
        }
        return pending.contains { activity in
            activity.taskId == taskID &&
                activity.activityDayKey == activityDayKey &&
                activity.supersededAt == nil &&
                (origin == .legacyBackfill || activity.originRawValue == capturedOrigin) &&
                !deletedIDs.contains(activity.persistentModelID)
        }
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
