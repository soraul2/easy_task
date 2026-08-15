import Foundation
import SwiftData

public enum TaskProgressEventIntegrityService {
    public static let batchSize = 200

    public struct Report: Equatable, Sendable {
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
    }

    @MainActor
    @discardableResult
    public static func reconcile(
        in context: ModelContext,
        pageSize: Int = batchSize,
        isCancelled: () -> Bool = { false }
    ) throws -> Report {
        let resolvedPageSize = max(1, pageSize)
        let pendingEvents = pendingEvents(in: context)
        let pendingIdentifiers = Set(pendingEvents.map(\.persistentModelID))
        var report = Report()
        var offset = 0
        var pendingID: UUID?
        var pendingGroup: [TaskProgressEvent] = []

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<TaskProgressEvent>(sortBy: [
                SortDescriptor(\TaskProgressEvent.id),
                SortDescriptor(\TaskProgressEvent.instanceID)
            ])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = resolvedPageSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            for event in batch where
                event.supersededAt == nil &&
                !pendingIdentifiers.contains(event.persistentModelID) {
                if isCancelled() { throw CancellationError() }
                guard normalize(event, report: &report) else { continue }
                if pendingID == event.id {
                    pendingGroup.append(event)
                } else {
                    reconcileGroup(pendingGroup, report: &report)
                    pendingID = event.id
                    pendingGroup = [event]
                }
            }

            guard batch.count == resolvedPageSize else { break }
            offset += batch.count
        }
        reconcileGroup(pendingGroup, report: &report)
        try reconcilePendingGroups(
            pendingEvents,
            in: context,
            isCancelled: isCancelled,
            report: &report
        )
        return report
    }
}

private extension TaskProgressEventIntegrityService {
    @MainActor
    static func pendingEvents(in context: ModelContext) -> [TaskProgressEvent] {
        var seen: Set<PersistentIdentifier> = []
        return (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? TaskProgressEvent }
            .filter { seen.insert($0.persistentModelID).inserted }
    }

    @MainActor
    static func normalize(
        _ event: TaskProgressEvent,
        report: inout Report
    ) -> Bool {
        report.scannedRecords += 1
        report.normalizedFields += DataIntegrityService.normalizeTimestamps(event)
        let kind = TaskProgressEventKind(rawValue: event.kindRawValue)
        let origin = TaskProgressEventOrigin(rawValue: event.originRawValue)
        let invalidCompatibilityKind = origin == .compatibilityBoundary && kind != .stopped
        guard kind != nil,
              origin != nil,
              DataIntegrityService.isFinite(event.occurredAt),
              !invalidCompatibilityKind else {
            supersede(event, at: event.updatedAt, report: &report)
            return false
        }
        if origin == .compatibilityBoundary {
            let canonicalID = TaskProgressEventService.compatibilityBoundaryID(
                taskID: event.taskId,
                occurredAt: event.occurredAt
            )
            guard event.id == canonicalID else {
                supersede(event, at: event.updatedAt, report: &report)
                return false
            }
        }
        return true
    }

    @MainActor
    static func reconcilePendingGroups(
        _ pendingEvents: [TaskProgressEvent],
        in context: ModelContext,
        isCancelled: () -> Bool,
        report: inout Report
    ) throws {
        var validIDs: Set<UUID> = []
        for event in pendingEvents where event.supersededAt == nil {
            if isCancelled() { throw CancellationError() }
            if normalize(event, report: &report) {
                validIDs.insert(event.id)
            }
        }

        for id in validIDs {
            if isCancelled() { throw CancellationError() }
            let descriptor = FetchDescriptor<TaskProgressEvent>(
                predicate: #Predicate<TaskProgressEvent> { event in
                    event.id == id
                }
            )
            var seen: Set<PersistentIdentifier> = []
            let group = try context.fetch(descriptor).filter {
                $0.supersededAt == nil && seen.insert($0.persistentModelID).inserted
            }
            reconcileGroup(group, report: &report)
        }
    }

    @MainActor
    static func reconcileGroup(
        _ group: [TaskProgressEvent],
        report: inout Report
    ) {
        let active = group.filter { $0.supersededAt == nil }
        guard active.count > 1,
              let winner = active.max(by: precedes) else { return }
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

    static func precedes(
        _ lhs: TaskProgressEvent,
        _ rhs: TaskProgressEvent
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    @MainActor
    static func supersede(
        _ event: TaskProgressEvent,
        at timestamp: Date,
        report: inout Report
    ) {
        guard event.supersededAt == nil else { return }
        event.supersededAt = timestamp
        report.supersededRecords += 1
    }
}
