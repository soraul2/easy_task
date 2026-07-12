import Foundation
import OSLog
import SwiftData

#if canImport(Darwin)
import Darwin
#endif

public enum CloudKitProbeRole: String, Codable, Sendable {
    case writer
    case reader
    case cleanup
}

public enum CloudKitProbeKind: String, Codable, Sendable {
    case event
    case media
    case conflict
}

public enum CloudKitConflictVariant: String, Codable, CaseIterable, Sendable {
    case older
    case newer
}

public enum CloudKitProbeExpectation: String, Codable, Sendable {
    case present
    case absent
}

public struct CloudKitProbeConfiguration: Equatable, Sendable {
    public var kind: CloudKitProbeKind
    public var role: CloudKitProbeRole
    public var token: UUID
    public var expectation: CloudKitProbeExpectation
    public var conflictVariant: CloudKitConflictVariant?
    public var timeoutSeconds: Int
    public var waitsForExport: Bool
    public var exitsWhenFinished: Bool

    public init(
        kind: CloudKitProbeKind = .event,
        role: CloudKitProbeRole,
        token: UUID,
        expectation: CloudKitProbeExpectation = .present,
        conflictVariant: CloudKitConflictVariant? = nil,
        timeoutSeconds: Int = 180,
        waitsForExport: Bool = false,
        exitsWhenFinished: Bool = false
    ) {
        self.kind = kind
        self.role = role
        self.token = token
        self.expectation = expectation
        self.conflictVariant = conflictVariant
        self.timeoutSeconds = timeoutSeconds
        self.waitsForExport = waitsForExport
        self.exitsWhenFinished = exitsWhenFinished
    }
}

public struct CloudKitProbeSnapshot: Codable, Equatable, Sendable {
    public var token: UUID
    public var activeRecordCount: Int
    public var matchingRecordCount: Int
    public var sourceBundleIdentifier: String?
    public var expectation: CloudKitProbeExpectation
    public var passed: Bool
}

public struct CloudKitMediaProbeSnapshot: Codable, Equatable, Sendable {
    public var token: UUID
    public var totalReviewCount: Int
    public var activeReviewCount: Int
    public var matchingReviewCount: Int
    public var conflictingDayReviewCount: Int
    public var totalAttachmentCount: Int
    public var activeAttachmentCount: Int
    public var matchingAttachmentCount: Int
    public var sourceBundleIdentifier: String?
    public var attachmentSHA256: String?
    public var attachmentByteCount: Int?
    public var attachmentOrder: Double?
    public var dataMatchesExpected: Bool
    public var expectation: CloudKitProbeExpectation
    public var passed: Bool
}

public struct CloudKitConflictProbeSnapshot: Codable, Equatable, Sendable {
    public var token: UUID
    public var totalRecordCount: Int
    public var totalMarkerCount: Int
    public var activeMarkerCount: Int
    public var observedVariants: [CloudKitConflictVariant]
    public var winningVariant: CloudKitConflictVariant?
    public var sourceBundleIdentifier: String?
    public var expectation: CloudKitProbeExpectation
    public var passed: Bool
}

public struct CloudKitProbeRunResult: Codable, Equatable, Sendable {
    public var kind: CloudKitProbeKind
    public var role: CloudKitProbeRole
    public var token: UUID
    public var passed: Bool
    public var snapshot: CloudKitProbeSnapshot?
    public var mediaSnapshot: CloudKitMediaProbeSnapshot?
    public var conflictSnapshot: CloudKitConflictProbeSnapshot?
    public var error: String?

    public init(
        kind: CloudKitProbeKind = .event,
        role: CloudKitProbeRole,
        token: UUID,
        passed: Bool,
        snapshot: CloudKitProbeSnapshot? = nil,
        mediaSnapshot: CloudKitMediaProbeSnapshot? = nil,
        conflictSnapshot: CloudKitConflictProbeSnapshot? = nil,
        error: String? = nil
    ) {
        self.kind = kind
        self.role = role
        self.token = token
        self.passed = passed
        self.snapshot = snapshot
        self.mediaSnapshot = mediaSnapshot
        self.conflictSnapshot = conflictSnapshot
        self.error = error
    }
}

public enum CloudKitConvergenceProbe {
    public static let markerTitle = "__EASYTASK_CLOUDKIT_PROBE__"
    public static let logPrefix = "EASYTASK_CKPROBE"

    private static let logger = Logger(
        subsystem: "com.soraul2.easytask",
        category: "CloudKitProbe"
    )

    public static func configuration(
        arguments: [String]
    ) -> CloudKitProbeConfiguration? {
        guard let roleValue = value(after: "--cloudkit-probe-role", in: arguments),
              let role = CloudKitProbeRole(rawValue: roleValue),
              let tokenValue = value(after: "--cloudkit-probe-token", in: arguments),
              let token = UUID(uuidString: tokenValue) else {
            return nil
        }

        let kind: CloudKitProbeKind
        if let rawKind = value(after: "--cloudkit-probe-kind", in: arguments) {
            guard let parsedKind = CloudKitProbeKind(rawValue: rawKind) else { return nil }
            kind = parsedKind
        } else {
            kind = .event
        }

        let expectation: CloudKitProbeExpectation
        if let rawExpectation = value(after: "--cloudkit-probe-expect", in: arguments) {
            guard let parsedExpectation = CloudKitProbeExpectation(
                rawValue: rawExpectation
            ) else { return nil }
            expectation = parsedExpectation
        } else {
            expectation = .present
        }

        let conflictVariant: CloudKitConflictVariant?
        if let rawVariant = value(after: "--cloudkit-probe-variant", in: arguments) {
            guard let parsedVariant = CloudKitConflictVariant(
                rawValue: rawVariant
            ) else { return nil }
            conflictVariant = parsedVariant
        } else {
            conflictVariant = nil
        }

        let timeout: Int
        if let rawTimeout = value(after: "--cloudkit-probe-timeout", in: arguments) {
            guard let parsedTimeout = Int(rawTimeout) else { return nil }
            timeout = parsedTimeout
        } else {
            timeout = 180
        }

        return CloudKitProbeConfiguration(
            kind: kind,
            role: role,
            token: token,
            expectation: expectation,
            conflictVariant: conflictVariant,
            timeoutSeconds: min(max(timeout, 1), 600),
            waitsForExport: arguments.contains("--cloudkit-probe-wait-for-export"),
            exitsWhenFinished: arguments.contains("--cloudkit-probe-exit")
        )
    }

    public static func isProbeInvocation(arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix("--cloudkit-probe-") }
    }

    @MainActor
    @discardableResult
    public static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        context: ModelContext,
        sourceBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown"
    ) async -> CloudKitProbeRunResult? {
        guard isProbeInvocation(arguments: arguments) else {
            return nil
        }
        guard let configuration = configuration(arguments: arguments) else {
            log("INVALID_ARGUMENTS")
            if arguments.contains("--cloudkit-probe-exit") {
                terminateProcess(success: false)
            }
            return nil
        }

        log(
            "START kind=\(configuration.kind.rawValue) " +
                "role=\(configuration.role.rawValue) token=\(configuration.token.uuidString)"
        )
        let result: CloudKitProbeRunResult
        do {
            switch configuration.kind {
            case .event:
                result = try await runEventProbe(
                    configuration: configuration,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            case .media:
                result = try await runMediaProbe(
                    configuration: configuration,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            case .conflict:
                result = try await runConflictProbe(
                    configuration: configuration,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            }
        } catch {
            result = CloudKitProbeRunResult(
                kind: configuration.kind,
                role: configuration.role,
                token: configuration.token,
                passed: false,
                error: error.localizedDescription
            )
        }

        emit(result)
        if configuration.exitsWhenFinished {
            terminateProcess(success: result.passed)
        }
        return result
    }
}

extension CloudKitConvergenceProbe {
    @MainActor
    static func runEventProbe(
        configuration: CloudKitProbeConfiguration,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try writeMarker(
                    token: configuration.token,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            }
            let snapshot = try snapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
            return CloudKitProbeRunResult(
                role: .writer,
                token: configuration.token,
                passed: snapshot.passed,
                snapshot: snapshot
            )
        case .reader:
            let snapshot = try await waitForExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
            return CloudKitProbeRunResult(
                role: .reader,
                token: configuration.token,
                passed: snapshot.passed,
                snapshot: snapshot,
                error: snapshot.passed ? nil : "CloudKit probe timed out"
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try cleanupMarker(token: configuration.token, context: context)
            }
            let snapshot = try snapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
            return CloudKitProbeRunResult(
                role: .cleanup,
                token: configuration.token,
                passed: snapshot.passed,
                snapshot: snapshot
            )
        }
    }

    @MainActor
    static func writeMarker(
        token: UUID,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) throws {
        let existing = try markerEvents(token: token, context: context)
        guard existing.isEmpty else {
            throw CocoaError(
                .fileWriteFileExists,
                userInfo: [NSLocalizedDescriptionKey: "Probe token already exists"]
            )
        }

        let markerDate = try markerDate()
        let now = Date()
        let event = CalendarEvent(
            id: token,
            instanceID: UUID(),
            title: markerTitle,
            startAt: markerDate,
            endAt: markerDate,
            note: "\(token.uuidString)|\(sourceBundleIdentifier)",
            createdAt: now,
            updatedAt: now
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(event)
        }
        log("LOCAL_SAVED token=\(token.uuidString)")
    }

    @MainActor
    static func cleanupMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let records = try markerEvents(token: token, context: context)
        let markers = records.filter { event in
            event.title == markerTitle &&
                event.note?.hasPrefix(token.uuidString) == true
        }
        guard markers.count == records.count else {
            log("LOCAL_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }
        try PersistenceCommandService.perform(in: context) {
            for event in markers {
                context.delete(event)
            }
        }
        log("LOCAL_DELETED token=\(token.uuidString) count=\(markers.count)")
    }

    @MainActor
    static func snapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitProbeSnapshot {
        let activeRecords = try markerEvents(token: token, context: context)
            .filter { $0.supersededAt == nil }
        let matchingRecords = activeRecords.filter { event in
            event.title == markerTitle &&
                event.note?.hasPrefix(token.uuidString) == true
        }
        let source = matchingRecords.first?.note?
            .split(separator: "|", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init)
        let passed: Bool
        switch expectation {
        case .present:
            passed = activeRecords.count == 1 && matchingRecords.count == 1
        case .absent:
            passed = activeRecords.isEmpty
        }
        return CloudKitProbeSnapshot(
            token: token,
            activeRecordCount: activeRecords.count,
            matchingRecordCount: matchingRecords.count,
            sourceBundleIdentifier: source,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try snapshot(
            token: token,
            expectation: expectation,
            context: context
        )

        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try snapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}

extension CloudKitConvergenceProbe {
    @MainActor
    static func markerEvents(
        token: UUID,
        context: ModelContext
    ) throws -> [CalendarEvent] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<CalendarEvent> { event in
                event.id == token
            }
        ))
    }

    static func markerDate() throws -> Date {
        guard let date = DayKey.date(from: "2099-12-31") else {
            throw CocoaError(.formatting)
        }
        return date
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }

    private static func emit(_ result: CloudKitProbeRunResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(result))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        log("RESULT \(payload)")
    }

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        print("\(logPrefix) \(message)")
        fflush(stdout)
    }

    static func probeFileExistsError(_ description: String) -> CocoaError {
        CocoaError(
            .fileWriteFileExists,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    @MainActor
    static func performMutationAwaitingExportIfRequested(
        configuration: CloudKitProbeConfiguration,
        mutation: () throws -> Void
    ) async throws {
        guard configuration.waitsForExport else {
            try mutation()
            return
        }

        let earliestStartDate = Date()
        let observer = ExportEventObserver(earliestStartDate: earliestStartDate)
        do {
            try mutation()
        } catch {
            observer.invalidate()
            throw error
        }

        switch await waitForCompletedExport(
            observer: observer,
            timeoutSeconds: configuration.timeoutSeconds
        ) {
        case .completed(let summary):
            guard summary.succeeded else {
                throw CocoaError(
                    .fileWriteUnknown,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "CloudKit export failed: " +
                            (summary.errorDescription ?? "unknown error")
                    ]
                )
            }
            log("EXPORT_COMPLETED id=\(summary.identifier.uuidString) succeeded=true")
        case .timedOut:
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit export timed out"]
            )
        }
    }

    @MainActor
    private static func waitForCompletedExport(
        observer: ExportEventObserver,
        timeoutSeconds: Int
    ) async -> ExportWaitOutcome {
        defer { observer.invalidate() }
        return await withTaskGroup(of: ExportWaitOutcome.self) { group in
            group.addTask {
                for await summary in observer.stream {
                    guard !Swift.Task.isCancelled else { return .timedOut }
                    if summary.isCompleted {
                        return .completed(summary)
                    }
                }
                return .timedOut
            }
            group.addTask {
                try? await Swift.Task.sleep(for: .seconds(timeoutSeconds))
                return .timedOut
            }
            let outcome = await group.next() ?? .timedOut
            group.cancelAll()
            return outcome
        }
    }

    private final class ExportEventObserver: @unchecked Sendable {
        let stream: AsyncStream<CloudKitSyncEventSummary>

        private let earliestStartDate: Date
        private let continuation: AsyncStream<CloudKitSyncEventSummary>.Continuation
        private var observerToken: NSObjectProtocol?
        private var startedEventIDs: Set<UUID> = []
        private let lock = NSLock()

        init(earliestStartDate: Date) {
            self.earliestStartDate = earliestStartDate
            let pair = AsyncStream<CloudKitSyncEventSummary>.makeStream()
            stream = pair.stream
            continuation = pair.continuation
            observerToken = NotificationCenter.default.addObserver(
                forName: CloudKitSyncService.eventChangedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.receive(notification)
            }
        }

        func invalidate() {
            lock.lock()
            let token = observerToken
            observerToken = nil
            lock.unlock()
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
            continuation.finish()
        }

        private func receive(_ notification: Notification) {
            guard let summary = CloudKitSyncService.summary(from: notification),
                  summary.kind == .export,
                  let startedAt = summary.startedAt,
                  startedAt >= earliestStartDate else { return }

            log(
                "EXPORT_EVENT id=\(summary.identifier.uuidString) " +
                    "completed=\(summary.isCompleted) " +
                    "succeeded=\(summary.succeeded) " +
                    "error=\(summary.errorDescription ?? "none")"
            )

            lock.lock()
            defer { lock.unlock() }
            if summary.isCompleted {
                guard startedEventIDs.remove(summary.identifier) != nil else { return }
                continuation.yield(summary)
            } else {
                startedEventIDs.insert(summary.identifier)
            }
        }

        deinit {
            invalidate()
        }
    }

    private static func terminateProcess(success: Bool) -> Never {
        fflush(stdout)
#if canImport(Darwin)
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
#else
        fatalError("CloudKit probe requested process termination")
#endif
    }
}

private enum ExportWaitOutcome: Sendable {
    case completed(CloudKitSyncEventSummary)
    case timedOut
}
