import Foundation
import SwiftData

public enum FocusSessionIntegrityService {
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
        let pendingSessions = pendingSessions(in: context)
        let pendingIdentifiers = Set(pendingSessions.map(\.persistentModelID))
        var report = Report()
        var offset = 0
        var pendingID: UUID?
        var pendingGroup: [FocusSession] = []

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<FocusSession>(sortBy: [
                SortDescriptor(\FocusSession.id),
                SortDescriptor(\FocusSession.instanceID)
            ])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = resolvedPageSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            for session in batch where
                session.supersededAt == nil &&
                !pendingIdentifiers.contains(session.persistentModelID) {
                if isCancelled() { throw CancellationError() }
                guard normalize(session, report: &report) else { continue }
                if pendingID == session.id {
                    pendingGroup.append(session)
                } else {
                    reconcileGroup(pendingGroup, report: &report)
                    pendingID = session.id
                    pendingGroup = [session]
                }
            }

            guard batch.count == resolvedPageSize else { break }
            offset += batch.count
        }
        reconcileGroup(pendingGroup, report: &report)
        try reconcilePendingGroups(
            pendingSessions,
            in: context,
            isCancelled: isCancelled,
            report: &report
        )
        return report
    }
}

private extension FocusSessionIntegrityService {
    @MainActor
    static func pendingSessions(in context: ModelContext) -> [FocusSession] {
        var seen: Set<PersistentIdentifier> = []
        return (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? FocusSession }
            .filter { seen.insert($0.persistentModelID).inserted }
    }

    @MainActor
    static func normalize(
        _ session: FocusSession,
        report: inout Report
    ) -> Bool {
        report.scannedRecords += 1
        report.normalizedFields += DataIntegrityService.normalizeTimestamps(session)

        guard FocusSessionOutcome(rawValue: session.outcomeRawValue) != nil,
              DataIntegrityService.isFinite(session.startedAt),
              DataIntegrityService.isFinite(session.endedAt),
              session.endedAt >= session.startedAt,
              session.plannedDurationSeconds >= FocusTimerRules.minimumFocusSeconds,
              session.plannedDurationSeconds <= FocusTimerRules.maximumFocusSeconds else {
            supersede(session, at: session.updatedAt, report: &report)
            return false
        }

        let normalizedFocusedDuration = min(
            session.plannedDurationSeconds,
            max(0, session.focusedDurationSeconds)
        )
        report.normalizedFields += DataIntegrityService.assign(
            &session.focusedDurationSeconds,
            normalizedFocusedDuration
        )
        return true
    }

    @MainActor
    static func reconcilePendingGroups(
        _ pendingSessions: [FocusSession],
        in context: ModelContext,
        isCancelled: () -> Bool,
        report: inout Report
    ) throws {
        var validIDs: Set<UUID> = []
        for session in pendingSessions where session.supersededAt == nil {
            if isCancelled() { throw CancellationError() }
            if normalize(session, report: &report) {
                validIDs.insert(session.id)
            }
        }

        for id in validIDs {
            if isCancelled() { throw CancellationError() }
            let descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate<FocusSession> { session in
                    session.id == id
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
        _ group: [FocusSession],
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

    static func precedes(_ lhs: FocusSession, _ rhs: FocusSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    @MainActor
    static func supersede(
        _ session: FocusSession,
        at timestamp: Date,
        report: inout Report
    ) {
        guard session.supersededAt == nil else { return }
        session.supersededAt = timestamp
        report.supersededRecords += 1
    }
}
