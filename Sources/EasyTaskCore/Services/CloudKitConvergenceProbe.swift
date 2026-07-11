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

public enum CloudKitProbeExpectation: String, Codable, Sendable {
    case present
    case absent
}

public struct CloudKitProbeConfiguration: Equatable, Sendable {
    public var role: CloudKitProbeRole
    public var token: UUID
    public var expectation: CloudKitProbeExpectation
    public var timeoutSeconds: Int
    public var exitsWhenFinished: Bool

    public init(
        role: CloudKitProbeRole,
        token: UUID,
        expectation: CloudKitProbeExpectation = .present,
        timeoutSeconds: Int = 180,
        exitsWhenFinished: Bool = false
    ) {
        self.role = role
        self.token = token
        self.expectation = expectation
        self.timeoutSeconds = timeoutSeconds
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

public struct CloudKitProbeRunResult: Codable, Equatable, Sendable {
    public var role: CloudKitProbeRole
    public var token: UUID
    public var passed: Bool
    public var snapshot: CloudKitProbeSnapshot?
    public var error: String?
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

        let expectation = value(after: "--cloudkit-probe-expect", in: arguments)
            .flatMap(CloudKitProbeExpectation.init(rawValue:)) ?? .present
        let timeout = value(after: "--cloudkit-probe-timeout", in: arguments)
            .flatMap(Int.init) ?? 180

        return CloudKitProbeConfiguration(
            role: role,
            token: token,
            expectation: expectation,
            timeoutSeconds: min(max(timeout, 1), 600),
            exitsWhenFinished: arguments.contains("--cloudkit-probe-exit")
        )
    }

    @MainActor
    @discardableResult
    public static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        context: ModelContext,
        sourceBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown"
    ) async -> CloudKitProbeRunResult? {
        guard let configuration = configuration(arguments: arguments) else {
            return nil
        }

        log("START role=\(configuration.role.rawValue) token=\(configuration.token.uuidString)")
        let result: CloudKitProbeRunResult
        do {
            switch configuration.role {
            case .writer:
                try writeMarker(
                    token: configuration.token,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
                let snapshot = try snapshot(
                    token: configuration.token,
                    expectation: .present,
                    context: context
                )
                result = CloudKitProbeRunResult(
                    role: .writer,
                    token: configuration.token,
                    passed: snapshot.passed,
                    snapshot: snapshot,
                    error: nil
                )
            case .reader:
                let snapshot = try await waitForExpectation(
                    configuration.expectation,
                    token: configuration.token,
                    timeoutSeconds: configuration.timeoutSeconds,
                    context: context
                )
                result = CloudKitProbeRunResult(
                    role: .reader,
                    token: configuration.token,
                    passed: snapshot.passed,
                    snapshot: snapshot,
                    error: snapshot.passed ? nil : "CloudKit probe timed out"
                )
            case .cleanup:
                try cleanupMarker(token: configuration.token, context: context)
                let snapshot = try snapshot(
                    token: configuration.token,
                    expectation: .absent,
                    context: context
                )
                result = CloudKitProbeRunResult(
                    role: .cleanup,
                    token: configuration.token,
                    passed: snapshot.passed,
                    snapshot: snapshot,
                    error: nil
                )
            }
        } catch {
            result = CloudKitProbeRunResult(
                role: configuration.role,
                token: configuration.token,
                passed: false,
                snapshot: nil,
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
        try PersistenceCommandService.perform(in: context) {
            for event in records where event.title == markerTitle {
                context.delete(event)
            }
        }
        log("LOCAL_DELETED token=\(token.uuidString) count=\(records.count)")
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

private extension CloudKitConvergenceProbe {
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

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }

    static func emit(_ result: CloudKitProbeRunResult) {
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

    static func terminateProcess(success: Bool) -> Never {
        fflush(stdout)
#if canImport(Darwin)
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
#else
        fatalError("CloudKit probe requested process termination")
#endif
    }
}
