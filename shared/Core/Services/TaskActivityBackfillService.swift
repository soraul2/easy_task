import Foundation
import SwiftData

public struct TaskActivityBackfillReport: Equatable, Sendable {
    public var scannedTasks: Int
    public var insertedActivities: Int

    public init(scannedTasks: Int = 0, insertedActivities: Int = 0) {
        self.scannedTasks = scannedTasks
        self.insertedActivities = insertedActivities
    }
}

public enum TaskActivityBackfillService {
    public static let batchSize = 200

    @MainActor
    @discardableResult
    public static func backfillLegacyCompletions(
        in context: ModelContext,
        createdAt: Date = Date(),
        isCancelled: () -> Bool = { false }
    ) throws -> TaskActivityBackfillReport {
        let doneStatus = TaskStatus.done.rawValue
        let pendingModels = context.insertedModelsArray +
            context.changedModelsArray +
            context.deletedModelsArray
        let pendingIdentifiers = Set(
            pendingModels.compactMap { ($0 as? Task)?.persistentModelID }
        )
        var seenPending: Set<PersistentIdentifier> = []
        let pendingTasks = (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? Task }
            .filter { seenPending.insert($0.persistentModelID).inserted }
        var offset = 0
        var report = TaskActivityBackfillReport()

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<Task>(
                predicate: #Predicate<Task> { task in
                    task.supersededAt == nil &&
                        task.status == doneStatus &&
                        task.completedAt != nil
                },
                sortBy: [SortDescriptor(\Task.instanceID)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            for task in batch where
                !pendingIdentifiers.contains(task.persistentModelID) &&
                task.supersededAt == nil &&
                task.status == doneStatus {
                if isCancelled() { throw CancellationError() }
                guard let completedAt = task.completedAt else { continue }
                try backfill(
                    task: task,
                    completedAt: completedAt,
                    createdAt: createdAt,
                    context: context,
                    report: &report
                )
            }

            guard batch.count == batchSize else { break }
            offset += batch.count
        }

        for task in pendingTasks where
            task.supersededAt == nil &&
            task.status == doneStatus {
            if isCancelled() { throw CancellationError() }
            guard let completedAt = task.completedAt else { continue }
            try backfill(
                task: task,
                completedAt: completedAt,
                createdAt: createdAt,
                context: context,
                report: &report
            )
        }
        return report
    }
}

private extension TaskActivityBackfillService {
    @MainActor
    static func backfill(
        task: Task,
        completedAt: Date,
        createdAt: Date,
        context: ModelContext,
        report: inout TaskActivityBackfillReport
    ) throws {
        report.scannedTasks += 1
        if try TaskActivityService.record(
            taskID: task.id,
            activityDayKey: TaskActivityRules.legacyDayKey(for: completedAt),
            occurredAt: completedAt,
            origin: .legacyBackfill,
            createdAt: createdAt,
            in: context
        ) != nil {
            report.insertedActivities += 1
        }
    }
}
