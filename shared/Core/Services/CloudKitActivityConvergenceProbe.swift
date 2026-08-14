import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    public static let activityMarkerDayKey = "2099-12-30"

    @MainActor
    static func runActivityProbe(
        configuration: CloudKitProbeConfiguration,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try writeActivityMarker(
                    token: configuration.token,
                    context: context
                )
            }
            let snapshot = try activitySnapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .activity,
                role: .writer,
                token: configuration.token,
                passed: snapshot.passed,
                activitySnapshot: snapshot
            )
        case .reader:
            let snapshot = try await waitForActivityExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .activity,
                role: .reader,
                token: configuration.token,
                passed: snapshot.passed,
                activitySnapshot: snapshot,
                error: snapshot.passed ? nil : "CloudKit activity probe timed out"
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try cleanupActivityMarker(
                    token: configuration.token,
                    context: context
                )
            }
            let snapshot = try activitySnapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .activity,
                role: .cleanup,
                token: configuration.token,
                passed: snapshot.passed,
                activitySnapshot: snapshot
            )
        }
    }
}

private extension CloudKitConvergenceProbe {
    @MainActor
    static func writeActivityMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let existing = try activityMarkers(token: token, context: context)
        guard existing.isEmpty else {
            throw probeFileExistsError("Activity probe token already exists")
        }
        guard let occurredAt = DayKey.date(from: activityMarkerDayKey) else {
            throw CocoaError(.formatting)
        }
        let now = Date()
        let marker = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(
                taskID: token,
                activityDayKey: activityMarkerDayKey
            ),
            taskId: token,
            activityDayKey: activityMarkerDayKey,
            occurredAt: occurredAt,
            origin: .captured,
            createdAt: now,
            updatedAt: now
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(marker)
        }
        log("ACTIVITY_LOCAL_SAVED token=\(token.uuidString)")
    }

    @MainActor
    static func cleanupActivityMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let records = try activityMarkers(token: token, context: context)
        let expectedID = TaskActivityRules.logicalID(
            taskID: token,
            activityDayKey: activityMarkerDayKey
        )
        let markers = records.filter {
            $0.id == expectedID &&
                $0.activityDayKey == activityMarkerDayKey &&
                $0.originRawValue == TaskCompletionActivityOrigin.captured.rawValue
        }
        guard markers.count == records.count else {
            log("ACTIVITY_LOCAL_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }
        try PersistenceCommandService.perform(in: context) {
            for marker in markers {
                context.delete(marker)
            }
        }
        log("ACTIVITY_LOCAL_DELETED token=\(token.uuidString) count=\(markers.count)")
    }

    @MainActor
    static func activityMarkers(
        token: UUID,
        context: ModelContext
    ) throws -> [TaskCompletionActivity] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<TaskCompletionActivity> { activity in
                activity.taskId == token
            }
        ))
    }

    @MainActor
    static func activitySnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitActivityProbeSnapshot {
        let records = try activityMarkers(token: token, context: context)
        let active = records.filter { $0.supersededAt == nil }
        let expectedID = TaskActivityRules.logicalID(
            taskID: token,
            activityDayKey: activityMarkerDayKey
        )
        let matching = active.filter {
            $0.id == expectedID &&
                $0.activityDayKey == activityMarkerDayKey &&
                $0.originRawValue == TaskCompletionActivityOrigin.captured.rawValue
        }
        let passed: Bool
        switch expectation {
        case .present:
            passed = active.count == 1 && matching.count == 1
        case .absent:
            passed = records.isEmpty
        }
        return CloudKitActivityProbeSnapshot(
            token: token,
            totalActivityCount: records.count,
            activeActivityCount: active.count,
            matchingActivityCount: matching.count,
            activityDayKey: matching.first?.activityDayKey,
            originRawValue: matching.first?.originRawValue,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForActivityExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitActivityProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try activitySnapshot(
            token: token,
            expectation: expectation,
            context: context
        )
        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try activitySnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}
