import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    public static let focusMarkerDate = Date(timeIntervalSince1970: 4_102_272_000)

    @MainActor
    static func runFocusProbe(
        configuration: CloudKitProbeConfiguration,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(configuration: configuration) {
                try writeFocusMarker(token: configuration.token, context: context)
            }
            let snapshot = try focusSnapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .focus,
                role: .writer,
                token: configuration.token,
                passed: snapshot.passed,
                focusSnapshot: snapshot
            )
        case .reader:
            let snapshot = try await waitForFocusExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .focus,
                role: .reader,
                token: configuration.token,
                passed: snapshot.passed,
                focusSnapshot: snapshot,
                error: snapshot.passed ? nil : "CloudKit focus probe timed out"
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(configuration: configuration) {
                try cleanupFocusMarker(token: configuration.token, context: context)
            }
            let snapshot = try focusSnapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
            return CloudKitProbeRunResult(
                kind: .focus,
                role: .cleanup,
                token: configuration.token,
                passed: snapshot.passed,
                focusSnapshot: snapshot
            )
        }
    }
}

private extension CloudKitConvergenceProbe {
    @MainActor
    static func writeFocusMarker(token: UUID, context: ModelContext) throws {
        guard try focusMarkers(token: token, context: context).isEmpty else {
            throw probeFileExistsError("Focus probe token already exists")
        }
        let marker = FocusSession(
            id: token,
            taskId: token,
            startedAt: focusMarkerDate,
            endedAt: focusMarkerDate.addingTimeInterval(300),
            plannedDurationSeconds: 300,
            focusedDurationSeconds: 300,
            outcome: .completed,
            createdAt: focusMarkerDate,
            updatedAt: focusMarkerDate.addingTimeInterval(300)
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(marker)
        }
        log("FOCUS_LOCAL_SAVED token=\(token.uuidString)")
    }

    @MainActor
    static func cleanupFocusMarker(token: UUID, context: ModelContext) throws {
        let records = try focusMarkers(token: token, context: context)
        let markers = records.filter(isFocusMarker)
        guard markers.count == records.count else {
            log("FOCUS_LOCAL_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }
        try PersistenceCommandService.perform(in: context) {
            for marker in markers {
                context.delete(marker)
            }
        }
        log("FOCUS_LOCAL_DELETED token=\(token.uuidString) count=\(markers.count)")
    }

    @MainActor
    static func focusMarkers(
        token: UUID,
        context: ModelContext
    ) throws -> [FocusSession] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<FocusSession> { session in
                session.taskId == token
            }
        ))
    }

    static func isFocusMarker(_ session: FocusSession) -> Bool {
        session.id == session.taskId &&
            session.startedAt == focusMarkerDate &&
            session.endedAt == focusMarkerDate.addingTimeInterval(300) &&
            session.plannedDurationSeconds == 300 &&
            session.focusedDurationSeconds == 300 &&
            session.outcomeRawValue == FocusSessionOutcome.completed.rawValue
    }

    @MainActor
    static func focusSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitFocusProbeSnapshot {
        let records = try focusMarkers(token: token, context: context)
        let active = records.filter { $0.supersededAt == nil }
        let matching = active.filter(isFocusMarker)
        let passed = switch expectation {
        case .present: active.count == 1 && matching.count == 1
        case .absent: records.isEmpty
        }
        return CloudKitFocusProbeSnapshot(
            token: token,
            totalSessionCount: records.count,
            activeSessionCount: active.count,
            matchingSessionCount: matching.count,
            outcomeRawValue: matching.first?.outcomeRawValue,
            focusedDurationSeconds: matching.first?.focusedDurationSeconds,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForFocusExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitFocusProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try focusSnapshot(
            token: token,
            expectation: expectation,
            context: context
        )
        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try focusSnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}
