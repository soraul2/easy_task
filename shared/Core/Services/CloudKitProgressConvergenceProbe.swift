import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    public static let progressMarkerDate = Date(timeIntervalSince1970: 4_102_358_400)

    @MainActor
    static func runProgressProbe(
        configuration: CloudKitProbeConfiguration,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(configuration: configuration) {
                try writeProgressMarker(token: configuration.token, context: context)
            }
            let snapshot = try progressSnapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .progress,
                role: .writer,
                token: configuration.token,
                passed: snapshot.passed,
                progressSnapshot: snapshot
            )
        case .reader:
            let snapshot = try await waitForProgressExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .progress,
                role: .reader,
                token: configuration.token,
                passed: snapshot.passed,
                progressSnapshot: snapshot,
                error: snapshot.passed ? nil : "CloudKit progress probe timed out"
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(configuration: configuration) {
                try cleanupProgressMarker(token: configuration.token, context: context)
            }
            let snapshot = try progressSnapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .progress,
                role: .cleanup,
                token: configuration.token,
                passed: snapshot.passed,
                progressSnapshot: snapshot
            )
        }
    }
}

private extension CloudKitConvergenceProbe {
    @MainActor
    static func writeProgressMarker(token: UUID, context: ModelContext) throws {
        guard try progressMarkers(token: token, context: context).isEmpty else {
            throw probeFileExistsError("Progress probe token already exists")
        }
        let marker = TaskProgressEvent(
            id: token,
            taskId: token,
            kind: .started,
            origin: .captured,
            occurredAt: progressMarkerDate,
            createdAt: progressMarkerDate,
            updatedAt: progressMarkerDate
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(marker)
        }
        log("PROGRESS_LOCAL_SAVED token=\(token.uuidString)")
    }

    @MainActor
    static func cleanupProgressMarker(token: UUID, context: ModelContext) throws {
        let records = try progressMarkers(token: token, context: context)
        let markers = records.filter(isProgressMarker)
        guard markers.count == records.count else {
            log("PROGRESS_LOCAL_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }
        try PersistenceCommandService.perform(in: context) {
            for marker in markers {
                context.delete(marker)
            }
        }
        log("PROGRESS_LOCAL_DELETED token=\(token.uuidString) count=\(markers.count)")
    }

    @MainActor
    static func progressMarkers(
        token: UUID,
        context: ModelContext
    ) throws -> [TaskProgressEvent] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<TaskProgressEvent> { event in
                event.taskId == token
            }
        ))
    }

    static func isProgressMarker(_ event: TaskProgressEvent) -> Bool {
        event.id == event.taskId &&
            event.kindRawValue == TaskProgressEventKind.started.rawValue &&
            event.originRawValue == TaskProgressEventOrigin.captured.rawValue &&
            event.occurredAt == progressMarkerDate
    }

    @MainActor
    static func progressSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitProgressProbeSnapshot {
        let records = try progressMarkers(token: token, context: context)
        let active = records.filter { $0.supersededAt == nil }
        let matching = active.filter(isProgressMarker)
        let passed = switch expectation {
        case .present: active.count == 1 && matching.count == 1
        case .absent: records.isEmpty
        }
        return CloudKitProgressProbeSnapshot(
            token: token,
            totalEventCount: records.count,
            activeEventCount: active.count,
            matchingEventCount: matching.count,
            kindRawValue: matching.first?.kindRawValue,
            originRawValue: matching.first?.originRawValue,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForProgressExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitProgressProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try progressSnapshot(
            token: token,
            expectation: expectation,
            context: context
        )
        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try progressSnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}
