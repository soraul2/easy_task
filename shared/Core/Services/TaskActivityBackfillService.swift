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
        in context: ModelContext, createdAt: Date = Date()
    ) throws -> TaskActivityBackfillReport {
        try backfillLegacyCompletions(in: context, createdAt: createdAt,
                                      isCancelled: { false }, stablePendingScope: true)
    }

    @MainActor
    @discardableResult
    public static func backfillLegacyCompletions(
        in context: ModelContext,
        createdAt: Date = Date(),
        isCancelled: () -> Bool
    ) throws -> TaskActivityBackfillReport {
        // Caller callbacks can edit/delete/save pending activities even when
        // they return false; keep the fully dynamic record path for this API.
        try backfillLegacyCompletions(in: context, createdAt: createdAt,
                                      isCancelled: isCancelled, stablePendingScope: false)
    }

    @MainActor
    private static func backfillLegacyCompletions(
        in context: ModelContext, createdAt: Date,
        isCancelled: () -> Bool, stablePendingScope: Bool
    ) throws -> TaskActivityBackfillReport {
        let stablePending = stablePendingScope
            ? TaskActivityService.StableLegacyPendingProof(in: context) : nil
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
        var savedReader: ModelContext?

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
            // A saved-only fetch in a dirty context can replace pending model
            // fields with stored values. Keep that read graph separate, without
            // saving, restoring, or discarding the caller's pending changes.
            let pageContext: ModelContext
            if context.hasChanges {
                if let savedReader {
                    pageContext = savedReader
                } else {
                    let reader = ModelContext(context.container)
                    reader.autosaveEnabled = false
                    savedReader = reader
                    pageContext = reader
                }
            } else {
                pageContext = context
            }
            let batch = try pageContext.fetch(descriptor).map(SavedCompletionCandidate.init)
            var knownCompletions: Set<PersistentIdentifier>?

            for task in batch where
                !pendingIdentifiers.contains(task.persistentModelID) &&
                task.supersededAt == nil &&
                task.status == doneStatus {
                if isCancelled() { throw CancellationError() }
                guard let completedAt = task.completedAt else { continue }
                // Advisory positive proof only. A miss or a newly dirty context
                // still uses record(), which owns pending activity semantics.
                if knownCompletions == nil {
                    knownCompletions = knownRecordedCompletions(
                        in: context, candidates: batch, excluding: pendingIdentifiers, doneStatus: doneStatus)
                }
                if !context.hasChanges, knownCompletions?.contains(task.persistentModelID) == true {
                    report.scannedTasks += 1
                    continue
                }
                try backfill(
                    taskID: task.id,
                    completedAt: completedAt,
                    createdAt: createdAt,
                    context: context,
                    stablePending: stablePending,
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
                taskID: task.id,
                completedAt: completedAt,
                createdAt: createdAt,
                context: context,
                stablePending: stablePending,
                report: &report
            )
        }
        return report
    }
}

private extension TaskActivityBackfillService {
    struct SavedCompletionCandidate {
        let persistentModelID: PersistentIdentifier
        let id: UUID
        let status: String
        let completedAt: Date?
        let supersededAt: Date?

        init(_ task: Task) {
            persistentModelID = task.persistentModelID
            id = task.id
            status = task.status
            completedAt = task.completedAt
            supersededAt = task.supersededAt
        }
    }

    struct CompletionProofTarget {
        let persistentModelID: PersistentIdentifier
        let key: TaskActivitySnapshot
        let activityID: UUID
    }

    @MainActor
    static func knownRecordedCompletions(
        in context: ModelContext, candidates: [SavedCompletionCandidate],
        excluding pendingIdentifiers: Set<PersistentIdentifier>, doneStatus: String
    ) -> Set<PersistentIdentifier> {
        guard !context.hasChanges else { return [] }
        let targets = candidates.compactMap { task -> CompletionProofTarget? in
            guard !pendingIdentifiers.contains(task.persistentModelID), task.supersededAt == nil,
                  task.status == doneStatus, let completion = task.completedAt,
                  completion.timeIntervalSinceReferenceDate.isFinite else { return nil }
            let day = TaskActivityRules.legacyDayKey(for: completion)
            guard DayKey.date(from: day) != nil else { return nil }
            return CompletionProofTarget(
                persistentModelID: task.persistentModelID,
                key: TaskActivitySnapshot(taskID: task.id, activityDayKey: day),
                activityID: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day))
        }
        guard !targets.isEmpty else { return [] }
        let byActivityID = Dictionary(grouping: targets, by: \.activityID)
        let ids = Array(byActivityID.keys)
        var descriptor = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate { $0.supersededAt == nil && ids.contains($0.id) },
            sortBy: [SortDescriptor(\TaskCompletionActivity.instanceID)])
        descriptor.fetchLimit = batchSize
        descriptor.includePendingChanges = false
        // A failed advisory read proves nothing; let the unchanged record path
        // perform the authoritative natural-key query and propagate its errors.
        guard let rows = try? context.fetch(descriptor), !context.hasChanges else { return [] }
        var proven: Set<PersistentIdentifier> = []
        for row in rows {
            guard row.supersededAt == nil, TaskActivityRules.origin(for: row.originRawValue) != nil,
                  row.occurredAt.timeIntervalSinceReferenceDate.isFinite,
                  row.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  row.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  TaskActivityRules.legacyDayKey(for: row.occurredAt) == row.activityDayKey,
                  let matches = byActivityID[row.id] else { continue }
            for target in matches where row.taskId == target.key.taskID && row.activityDayKey == target.key.activityDayKey {
                proven.insert(target.persistentModelID)
            }
        }
        return proven
    }

    @MainActor
    static func backfill(
        taskID: UUID,
        completedAt: Date,
        createdAt: Date,
        context: ModelContext,
        stablePending: TaskActivityService.StableLegacyPendingProof?,
        report: inout TaskActivityBackfillReport
    ) throws {
        report.scannedTasks += 1
        let activityDayKey = TaskActivityRules.legacyDayKey(for: completedAt)
        let inserted: TaskCompletionActivity?
        if let stablePending {
            inserted = try TaskActivityService.recordLegacyCompletion(
                taskID: taskID, activityDayKey: activityDayKey, occurredAt: completedAt,
                createdAt: createdAt, in: context, pending: stablePending)
        } else {
            inserted = try TaskActivityService.record(
                taskID: taskID, activityDayKey: activityDayKey, occurredAt: completedAt,
                origin: .legacyBackfill, createdAt: createdAt, in: context)
        }
        if inserted != nil { report.insertedActivities += 1 }
    }
}
