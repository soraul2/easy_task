import Foundation
import SwiftData

extension BoundedQueryService {
@MainActor
    public static func taskActivitySnapshots(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext,
        isCancelled: () -> Bool = { false }
    ) throws -> [TaskActivitySnapshot] {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        let pendingModels = context.insertedModelsArray +
            context.changedModelsArray +
            context.deletedModelsArray
        let pendingIdentifiers = Set(
            pendingModels.compactMap {
                ($0 as? TaskCompletionActivity)?.persistentModelID
            }
        )
        var seenPending: Set<PersistentIdentifier> = []
        let pendingActivities = (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? TaskCompletionActivity }
            .filter { seenPending.insert($0.persistentModelID).inserted }

        var snapshots: [TaskActivitySnapshot] = []
        var offset = 0
        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate<TaskCompletionActivity> { activity in
                    activity.supersededAt == nil &&
                        activity.activityDayKey >= lowerBound &&
                        activity.activityDayKey <= upperBound
                },
                sortBy: [
                    SortDescriptor(\TaskCompletionActivity.activityDayKey),
                    SortDescriptor(\TaskCompletionActivity.taskId),
                    SortDescriptor(\TaskCompletionActivity.instanceID)
                ]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = taskActivityBatchSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            snapshots.append(contentsOf: batch.compactMap { activity in
                guard activity.supersededAt == nil,
                      lowerBound <= activity.activityDayKey,
                      activity.activityDayKey <= upperBound,
                      !pendingIdentifiers.contains(activity.persistentModelID) else {
                    return nil
                }
                return TaskActivitySnapshot(
                    taskID: activity.taskId,
                    activityDayKey: activity.activityDayKey
                )
            })
            guard batch.count == taskActivityBatchSize else { break }
            offset += batch.count
        }

        snapshots.append(contentsOf: pendingActivities.compactMap { activity in
            guard activity.supersededAt == nil,
                  lowerBound <= activity.activityDayKey,
                  activity.activityDayKey <= upperBound else {
                return nil
            }
            return TaskActivitySnapshot(
                taskID: activity.taskId,
                activityDayKey: activity.activityDayKey
            )
        })
        return Array(Set(snapshots)).sorted {
            if $0.activityDayKey != $1.activityDayKey {
                return $0.activityDayKey < $1.activityDayKey
            }
            return $0.taskID.uuidString < $1.taskID.uuidString
        }
    }

    @MainActor
    public static func hasTaskActivity(
        before dayKey: String,
        in context: ModelContext
    ) throws -> Bool {
        if (context.insertedModelsArray + context.changedModelsArray)
            .compactMap({ $0 as? TaskCompletionActivity })
            .contains(where: {
                $0.supersededAt == nil && $0.activityDayKey < dayKey
            }) {
            return true
        }
        var descriptor = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate<TaskCompletionActivity> { activity in
                activity.supersededAt == nil && activity.activityDayKey < dayKey
            },
            sortBy: [SortDescriptor(\TaskCompletionActivity.activityDayKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = false
        return try context.fetch(descriptor).contains { activity in
            activity.supersededAt == nil && activity.activityDayKey < dayKey
        }
    }
}
