import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    static let conflictMarkerTitle = "__PLANBASE_CLOUDKIT_CONFLICT_PROBE__"

    @MainActor
    static func runConflictProbe(
        configuration: CloudKitProbeConfiguration,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        let snapshot: CloudKitConflictProbeSnapshot
        switch configuration.role {
        case .writer:
            guard let variant = configuration.conflictVariant else {
                throw CocoaError(
                    .validationMissingMandatoryProperty,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Conflict writer requires --cloudkit-probe-variant"
                    ]
                )
            }
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try writeConflictMarker(
                    token: configuration.token,
                    variant: variant,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            }
            snapshot = try conflictSnapshot(
                token: configuration.token,
                expectation: .present,
                expectedWinner: variant,
                requiresBothVariants: false,
                context: context
            )
        case .reader:
            snapshot = try await waitForConflictExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try cleanupConflictMarker(token: configuration.token, context: context)
            }
            snapshot = try conflictSnapshot(
                token: configuration.token,
                expectation: .absent,
                expectedWinner: nil,
                requiresBothVariants: false,
                context: context
            )
        }

        return CloudKitProbeRunResult(
            kind: .conflict,
            role: configuration.role,
            token: configuration.token,
            passed: snapshot.passed,
            conflictSnapshot: snapshot,
            error: !snapshot.passed && configuration.role == .reader
                ? "CloudKit conflict probe timed out"
                : nil
        )
    }

    @MainActor
    static func writeConflictMarker(
        token: UUID,
        variant: CloudKitConflictVariant,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) throws {
        let records = try conflictEvents(token: token, context: context)
        guard try records.allSatisfy({
            try isConflictMarker($0, token: token)
        }) else {
            throw probeFileExistsError("Conflict probe token collides with a user event")
        }
        guard !records.contains(where: {
            conflictNote(from: $0.note)?.variant == variant
        }) else {
            throw probeFileExistsError("Conflict probe variant already exists")
        }

        let markerDate = try conflictMarkerDate()
        let baseTimestamp = conflictBaseTimestamp()
        let updatedAt = conflictUpdatedAt(for: variant)
        let event = CalendarEvent(
            id: token,
            instanceID: UUID(),
            title: conflictMarkerTitle,
            startAt: markerDate,
            endAt: markerDate,
            note: "\(token.uuidString)|\(variant.rawValue)|\(sourceBundleIdentifier)",
            createdAt: baseTimestamp,
            updatedAt: updatedAt
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(event)
        }
        log(
            "LOCAL_CONFLICT_SAVED token=\(token.uuidString) " +
                "variant=\(variant.rawValue)"
        )
    }

    @MainActor
    static func cleanupConflictMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let records = try conflictEvents(token: token, context: context)
        let markers = records.filter { event in
            (try? isConflictMarker(event, token: token)) == true
        }
        guard markers.count == records.count else {
            log("LOCAL_CONFLICT_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }
        try PersistenceCommandService.perform(in: context) {
            for event in markers {
                context.delete(event)
            }
        }
        log("LOCAL_CONFLICT_DELETED token=\(token.uuidString) count=\(markers.count)")
    }

    @MainActor
    static func conflictSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        expectedWinner: CloudKitConflictVariant?,
        requiresBothVariants: Bool,
        context: ModelContext
    ) throws -> CloudKitConflictProbeSnapshot {
        let records = try conflictEvents(token: token, context: context)
        let markers = records.filter { event in
            (try? isConflictMarker(event, token: token)) == true
        }
        let activeMarkers = markers.filter { $0.supersededAt == nil }
        let notes = markers.compactMap { conflictNote(from: $0.note) }
        let variants = Array(Set(notes.map(\.variant))).sorted {
            $0.rawValue < $1.rawValue
        }
        let activeNote = activeMarkers.first.flatMap { conflictNote(from: $0.note) }
        let selectedNote = requiresBothVariants
            ? activeNote
            : notes.first(where: { $0.variant == expectedWinner })
        let hasBothVariants = Set(variants) == Set(CloudKitConflictVariant.allCases)
        let passed: Bool
        switch expectation {
        case .present:
            if requiresBothVariants {
                passed = activeMarkers.count == 1 &&
                    selectedNote?.variant == expectedWinner &&
                    markers.count == 2 &&
                    hasBothVariants
            } else {
                passed = records.count == markers.count &&
                    notes.filter { $0.variant == expectedWinner }.count == 1
            }
        case .absent:
            passed = records.isEmpty
        }

        return CloudKitConflictProbeSnapshot(
            token: token,
            totalRecordCount: records.count,
            totalMarkerCount: markers.count,
            activeMarkerCount: activeMarkers.count,
            observedVariants: variants,
            winningVariant: selectedNote?.variant,
            sourceBundleIdentifier: selectedNote?.sourceBundleIdentifier,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForConflictExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitConflictProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try reconciledConflictSnapshot(
            token: token,
            expectation: expectation,
            context: context
        )

        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try reconciledConflictSnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}

private extension CloudKitConvergenceProbe {
    struct ConflictNote {
        let token: UUID
        let variant: CloudKitConflictVariant
        let sourceBundleIdentifier: String
    }

    @MainActor
    static func reconciledConflictSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitConflictProbeSnapshot {
        let records = try conflictEvents(token: token, context: context)
        guard try records.allSatisfy({
            try isConflictMarker($0, token: token)
        }) else {
            throw probeFileExistsError(
                "Conflict probe token collides with a user event"
            )
        }
        if expectation == .present {
            _ = try DataIntegrityService.reconcileCalendarEvents(
                logicalID: token,
                context: context
            )
        }
        return try conflictSnapshot(
            token: token,
            expectation: expectation,
            expectedWinner: expectation == .present ? .newer : nil,
            requiresBothVariants: expectation == .present,
            context: context
        )
    }

    @MainActor
    static func conflictEvents(
        token: UUID,
        context: ModelContext
    ) throws -> [CalendarEvent] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<CalendarEvent> { event in
                event.id == token
            }
        ))
    }

    static func conflictMarkerDate() throws -> Date {
        guard let date = DayKey.date(from: "2099-12-29") else {
            throw CocoaError(.formatting)
        }
        return date
    }

    static func conflictBaseTimestamp() -> Date {
        Date(timeIntervalSince1970: 4_102_444_800)
    }

    static func conflictUpdatedAt(for variant: CloudKitConflictVariant) -> Date {
        conflictBaseTimestamp().addingTimeInterval(variant == .older ? 10 : 20)
    }

    static func isConflictMarker(
        _ event: CalendarEvent,
        token: UUID
    ) throws -> Bool {
        guard event.id == token,
              event.title == conflictMarkerTitle,
              event.startDayKey == DayKey.key(for: try conflictMarkerDate()),
              event.endDayKey == DayKey.key(for: try conflictMarkerDate()),
              event.createdAt == conflictBaseTimestamp(),
              let note = conflictNote(from: event.note),
              note.token == token,
              !note.sourceBundleIdentifier.isEmpty,
              event.updatedAt == conflictUpdatedAt(for: note.variant) else {
            return false
        }
        return true
    }

    static func conflictNote(from note: String?) -> ConflictNote? {
        let components = note?.split(
            separator: "|",
            maxSplits: 2,
            omittingEmptySubsequences: false
        ) ?? []
        guard components.count == 3,
              let token = UUID(uuidString: String(components[0])),
              let variant = CloudKitConflictVariant(rawValue: String(components[1])) else {
            return nil
        }
        return ConflictNote(
            token: token,
            variant: variant,
            sourceBundleIdentifier: String(components[2])
        )
    }
}
