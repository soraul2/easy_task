import Foundation
import SwiftData

public struct TaskActivityIntegrityReport: Equatable, Sendable {
    public var scannedRecords: Int
    public var mergedRecords: Int
    public var normalizedFields: Int
    public var supersededRecords: Int

    public init(
        scannedRecords: Int = 0,
        mergedRecords: Int = 0,
        normalizedFields: Int = 0,
        supersededRecords: Int = 0
    ) {
        self.scannedRecords = scannedRecords
        self.mergedRecords = mergedRecords
        self.normalizedFields = normalizedFields
        self.supersededRecords = supersededRecords
    }

    public var hasChanges: Bool {
        mergedRecords > 0 || normalizedFields > 0 || supersededRecords > 0
    }
}

public enum TaskActivityIntegrityService {
    public static let batchSize = 200

    fileprivate struct NaturalKey: Hashable {
        var taskID: UUID
        var dayKey: String
    }

    @MainActor
    @discardableResult
    public static func reconcile(
        in context: ModelContext,
        pageSize: Int = batchSize,
        isCancelled: () -> Bool = { false }
    ) throws -> TaskActivityIntegrityReport {
        let resolvedPageSize = max(1, pageSize)
        var report = TaskActivityIntegrityReport()
        let pendingActivities = pendingActivities(in: context)
        let pendingIdentifiers = Set(pendingActivities.map(\.persistentModelID))
        var offset = 0
        var pendingKey: NaturalKey?
        var pendingGroup: [TaskCompletionActivity] = []

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<TaskCompletionActivity>(sortBy: [
                SortDescriptor(\TaskCompletionActivity.taskId),
                SortDescriptor(\TaskCompletionActivity.activityDayKey),
                SortDescriptor(\TaskCompletionActivity.instanceID)
            ])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = resolvedPageSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            for activity in batch where
                activity.supersededAt == nil &&
                !pendingIdentifiers.contains(activity.persistentModelID) {
                if isCancelled() { throw CancellationError() }
                guard let key = normalize(
                    activity,
                    report: &report
                ) else {
                    continue
                }
                if pendingKey == key {
                    pendingGroup.append(activity)
                } else {
                    try reconcileNaturalAndCrossDayGroup(
                        pendingGroup,
                        in: context,
                        report: &report
                    )
                    pendingKey = key
                    pendingGroup = [activity]
                }
            }

            guard batch.count == resolvedPageSize else { break }
            offset += batch.count
        }
        try reconcileNaturalAndCrossDayGroup(
            pendingGroup,
            in: context,
            report: &report
        )
        try reconcilePendingNaturalGroups(
            pendingActivities,
            in: context,
            isCancelled: isCancelled,
            report: &report
        )
        return report
    }
}

private extension TaskActivityIntegrityService {
    @MainActor
    static func pendingActivities(
        in context: ModelContext
    ) -> [TaskCompletionActivity] {
        var seen: Set<PersistentIdentifier> = []
        return (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? TaskCompletionActivity }
            .filter { seen.insert($0.persistentModelID).inserted }
    }

    @MainActor
    static func normalize(
        _ activity: TaskCompletionActivity,
        report: inout TaskActivityIntegrityReport
    ) -> NaturalKey? {
        report.scannedRecords += 1
        report.normalizedFields += DataIntegrityService.normalizeTimestamps(activity)

        guard DataIntegrityService.validDayKey(activity.activityDayKey) != nil,
              DataIntegrityService.isFinite(activity.occurredAt),
              TaskActivityRules.origin(for: activity.originRawValue) != nil else {
            supersede(activity, at: activity.updatedAt, report: &report)
            return nil
        }

        let canonicalID = TaskActivityRules.logicalID(
            taskID: activity.taskId,
            activityDayKey: activity.activityDayKey
        )
        report.normalizedFields += DataIntegrityService.assign(
            &activity.id,
            canonicalID
        )
        return NaturalKey(
            taskID: activity.taskId,
            dayKey: activity.activityDayKey
        )
    }

    @MainActor
    static func reconcilePendingNaturalGroups(
        _ pendingActivities: [TaskCompletionActivity],
        in context: ModelContext,
        isCancelled: () -> Bool,
        report: inout TaskActivityIntegrityReport
    ) throws {
        var groups: [NaturalKey: [TaskCompletionActivity]] = [:]
        for activity in pendingActivities where activity.supersededAt == nil {
            if isCancelled() { throw CancellationError() }
            guard let key = normalize(activity, report: &report) else { continue }
            groups[key, default: []].append(activity)
        }

        for (key, pendingGroup) in groups {
            if isCancelled() { throw CancellationError() }
            let taskID = key.taskID
            let dayKey = key.dayKey
            let descriptor = FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate<TaskCompletionActivity> { activity in
                    activity.taskId == taskID &&
                        activity.activityDayKey == dayKey
                }
            )
            var seen: Set<PersistentIdentifier> = []
            let fullGroup = try context.fetch(descriptor).filter { activity in
                activity.supersededAt == nil &&
                    activity.taskId == taskID &&
                    activity.activityDayKey == dayKey &&
                    seen.insert(activity.persistentModelID).inserted
            }
            try reconcileNaturalAndCrossDayGroup(
                fullGroup.isEmpty ? pendingGroup : fullGroup,
                in: context,
                report: &report
            )
        }
    }

    @MainActor
    static func reconcileNaturalGroup(
        _ group: [TaskCompletionActivity],
        report: inout TaskActivityIntegrityReport
    ) {
        let active = group.filter { $0.supersededAt == nil }
        guard active.count > 1,
              let winner = active.max(by: precedes) else {
            return
        }

        if let earliestCreatedAt = active
            .map(\.createdAt)
            .filter(DataIntegrityService.isFinite)
            .min() {
            report.normalizedFields += DataIntegrityService.assign(
                &winner.createdAt,
                earliestCreatedAt
            )
        }
        for loser in active where loser !== winner {
            supersede(loser, at: winner.updatedAt, report: &report)
            report.mergedRecords += 1
        }
    }

    @MainActor
    static func reconcileNaturalAndCrossDayGroup(
        _ group: [TaskCompletionActivity],
        in context: ModelContext,
        report: inout TaskActivityIntegrityReport
    ) throws {
        reconcileNaturalGroup(group, report: &report)
        for legacy in group where
            legacy.supersededAt == nil &&
            TaskActivityRules.origin(for: legacy.originRawValue) == .legacyBackfill {
            try reconcileCrossDayLegacy(
                legacy,
                in: context,
                report: &report
            )
        }
    }

    static func precedes(
        _ lhs: TaskCompletionActivity,
        _ rhs: TaskCompletionActivity
    ) -> Bool {
        let lhsOrigin = TaskActivityRules.origin(for: lhs.originRawValue)
        let rhsOrigin = TaskActivityRules.origin(for: rhs.originRawValue)
        if lhsOrigin != rhsOrigin {
            return lhsOrigin == .legacyBackfill
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    @MainActor
    static func reconcileCrossDayLegacy(
        _ legacy: TaskCompletionActivity,
        in context: ModelContext,
        report: inout TaskActivityIntegrityReport
    ) throws {
        let taskID = legacy.taskId
        let lowerBound = legacy.occurredAt.addingTimeInterval(-1)
        let upperBound = legacy.occurredAt.addingTimeInterval(1)
        let capturedOrigin = TaskCompletionActivityOrigin.captured.rawValue
        let candidatesDescriptor = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate<TaskCompletionActivity> { activity in
                activity.taskId == taskID &&
                    activity.originRawValue == capturedOrigin &&
                    activity.occurredAt >= lowerBound &&
                activity.occurredAt <= upperBound
            }
        )
        var seen: Set<PersistentIdentifier> = []
        let candidates = try context.fetch(candidatesDescriptor).filter { activity in
            activity.supersededAt == nil &&
                activity.taskId == taskID &&
                activity.originRawValue == capturedOrigin &&
                DataIntegrityService.validDayKey(activity.activityDayKey) != nil &&
                DataIntegrityService.isFinite(activity.occurredAt) &&
                activity.occurredAt >= lowerBound &&
                activity.occurredAt <= upperBound &&
                seen.insert(activity.persistentModelID).inserted
        }
        guard let captured = candidates.max(by: precedes) else {
            return
        }
        let supersededAt = DataIntegrityService.isFinite(captured.updatedAt)
            ? captured.updatedAt
            : legacy.updatedAt
        supersede(legacy, at: supersededAt, report: &report)
        report.mergedRecords += 1
    }

    @MainActor
    static func supersede(
        _ activity: TaskCompletionActivity,
        at timestamp: Date,
        report: inout TaskActivityIntegrityReport
    ) {
        guard activity.supersededAt == nil else { return }
        activity.supersededAt = timestamp
        report.supersededRecords += 1
    }
}
