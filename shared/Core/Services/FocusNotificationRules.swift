import Foundation
import SwiftData

public enum FocusNotificationAction: String, Codable, Equatable, Sendable {
    case open
    case startBreak
    case continueFocus
    case startFocus
    case extendBreak
    case dismiss
}

public struct FocusNotificationActionToken: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var tokenID: UUID
    public var requestIdentifier: String
    public var sessionID: UUID
    public var instanceID: UUID
    public var revision: Int
    public var phaseRawValue: String
    public var taskID: UUID
    public var taskTitleSnapshot: String
    public var plannedFocusSeconds: Int
    public var plannedBreakSeconds: Int
    public var deadline: Date
    public var expiresAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        tokenID: UUID = UUID(),
        requestIdentifier: String,
        sessionID: UUID,
        instanceID: UUID,
        revision: Int,
        phase: FocusTimerPhase,
        taskID: UUID,
        taskTitleSnapshot: String,
        plannedFocusSeconds: Int,
        plannedBreakSeconds: Int,
        deadline: Date,
        expiresAt: Date
    ) {
        self.formatVersion = formatVersion
        self.tokenID = tokenID
        self.requestIdentifier = requestIdentifier
        self.sessionID = sessionID
        self.instanceID = instanceID
        self.revision = revision
        phaseRawValue = phase.rawValue
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.plannedFocusSeconds = plannedFocusSeconds
        self.plannedBreakSeconds = plannedBreakSeconds
        self.deadline = deadline
        self.expiresAt = expiresAt
    }

    public var phase: FocusTimerPhase? {
        FocusTimerPhase(rawValue: phaseRawValue)
    }
}

public enum FocusNotificationRulesError: LocalizedError, Equatable {
    case invalidSnapshot
    case invalidToken
    case staleAction
    case actionNotAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            "알림을 예약할 집중 타이머 상태가 올바르지 않습니다."
        case .invalidToken:
            "집중 알림 정보가 올바르지 않습니다."
        case .staleAction:
            "이 알림은 현재 집중 타이머와 일치하지 않습니다."
        case .actionNotAvailable:
            "현재 상태에서는 이 알림 동작을 실행할 수 없습니다."
        }
    }
}

public enum FocusNotificationRules {
    public static let actionGracePeriod: TimeInterval = 60 * 60
    public static let extensionBreakSeconds = 5 * 60

    public static let focusEndedCategoryIdentifier = "planbase.focus.category.ended"
    public static let breakEndedCategoryIdentifier = "planbase.focus.category.break-ended"
    public static let startBreakActionIdentifier = "planbase.focus.action.start-break"
    public static let continueFocusActionIdentifier = "planbase.focus.action.continue-focus"
    public static let startFocusActionIdentifier = "planbase.focus.action.start-focus"
    public static let extendBreakActionIdentifier = "planbase.focus.action.extend-break"

    public static let routeKindKey = "routeKind"
    public static let routeKindValue = "focus"
    public static let tokenIDKey = "focusNotificationTokenID"
    public static let sessionIDKey = "focusSessionID"
    public static let revisionKey = "focusRevision"
    public static let phaseKey = "focusPhase"
    public static let deadlineKey = "focusDeadline"

    public static func requestIdentifier(
        namespace: String,
        snapshot: FocusActiveSessionSnapshot
    ) throws -> String {
        guard FocusTimerRules.isValid(snapshot), let phase = snapshot.phase else {
            throw FocusNotificationRulesError.invalidSnapshot
        }
        return [
            namespace,
            snapshot.sessionID.uuidString.lowercased(),
            phase.rawValue,
            String(snapshot.revision)
        ].joined(separator: ".")
    }

    public static func makeToken(
        snapshot: FocusActiveSessionSnapshot,
        requestIdentifier: String,
        tokenID: UUID = UUID()
    ) throws -> FocusNotificationActionToken {
        guard FocusTimerRules.isValid(snapshot),
              let phase = snapshot.phase,
              let deadline = snapshot.deadline,
              !requestIdentifier.isEmpty else {
            throw FocusNotificationRulesError.invalidSnapshot
        }
        return FocusNotificationActionToken(
            tokenID: tokenID,
            requestIdentifier: requestIdentifier,
            sessionID: snapshot.sessionID,
            instanceID: snapshot.instanceID,
            revision: snapshot.revision,
            phase: phase,
            taskID: snapshot.taskID,
            taskTitleSnapshot: snapshot.taskTitleSnapshot,
            plannedFocusSeconds: snapshot.plannedFocusSeconds,
            plannedBreakSeconds: snapshot.plannedBreakSeconds,
            deadline: deadline,
            expiresAt: deadline.addingTimeInterval(actionGracePeriod)
        )
    }

    public static func isValid(_ token: FocusNotificationActionToken) -> Bool {
        token.formatVersion == FocusNotificationActionToken.currentFormatVersion &&
            !token.requestIdentifier.isEmpty &&
            token.revision >= 1 &&
            token.phase != nil &&
            !token.taskTitleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            token.plannedFocusSeconds == FocusTimerRules.normalizedFocusSeconds(
                token.plannedFocusSeconds
            ) &&
            token.plannedBreakSeconds == FocusTimerRules.normalizedBreakSeconds(
                token.plannedBreakSeconds
            ) &&
            token.expiresAt >= token.deadline
    }

    public static func isActionable(
        _ token: FocusNotificationActionToken,
        now: Date
    ) -> Bool {
        isValid(token) && now >= token.deadline && now <= token.expiresAt
    }

    public static func matches(
        _ token: FocusNotificationActionToken,
        snapshot: FocusActiveSessionSnapshot
    ) -> Bool {
        token.sessionID == snapshot.sessionID &&
            token.instanceID == snapshot.instanceID &&
            token.revision == snapshot.revision &&
            token.phase == snapshot.phase &&
            token.taskID == snapshot.taskID &&
            token.taskTitleSnapshot == snapshot.taskTitleSnapshot &&
            token.plannedFocusSeconds == snapshot.plannedFocusSeconds &&
            token.plannedBreakSeconds == snapshot.plannedBreakSeconds &&
            token.deadline == snapshot.deadline
    }

    public static func categoryIdentifier(for phase: FocusTimerPhase) -> String {
        switch phase {
        case .focus: focusEndedCategoryIdentifier
        case .breakTime: breakEndedCategoryIdentifier
        }
    }

    public static func action(for identifier: String) -> FocusNotificationAction? {
        switch identifier {
        case startBreakActionIdentifier: .startBreak
        case continueFocusActionIdentifier: .continueFocus
        case startFocusActionIdentifier: .startFocus
        case extendBreakActionIdentifier: .extendBreak
        default: nil
        }
    }

    public static func title(for token: FocusNotificationActionToken) -> String {
        switch token.phase {
        case .focus:
            let minutes = max(1, token.plannedFocusSeconds / 60)
            return "\(minutes)분 집중을 완료했어요"
        case .breakTime:
            return "휴식이 끝났어요"
        case nil:
            return "집중 타이머가 끝났어요"
        }
    }

    public static func body(for token: FocusNotificationActionToken) -> String {
        switch token.phase {
        case .focus:
            return "\(token.taskTitleSnapshot) · 잠시 쉬어갈까요?"
        case .breakTime:
            return "\(token.taskTitleSnapshot) · 다시 집중할까요?"
        case nil:
            return token.taskTitleSnapshot
        }
    }
}

public enum FocusNotificationActionTokenStoreError: LocalizedError, Equatable {
    case appGroupContainerUnavailable
    case unsupportedFormatVersion(Int)
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            "집중 알림 공유 저장소를 열 수 없습니다."
        case .unsupportedFormatVersion(let version):
            "지원하지 않는 집중 알림 형식입니다. version=\(version)"
        case .invalidToken:
            "저장된 집중 알림 정보가 손상되었습니다."
        }
    }
}

public enum FocusNotificationActionTokenStore {
    public static let fileName = "focus-notification-action-v1.json"

    public static func read(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> FocusNotificationActionToken? {
        let fileURL = try resolvedFileURL(directoryURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(FormatEnvelope.self, from: data)
        guard envelope.formatVersion <= FocusNotificationActionToken.currentFormatVersion else {
            throw FocusNotificationActionTokenStoreError.unsupportedFormatVersion(
                envelope.formatVersion
            )
        }
        let token = try decoder.decode(FocusNotificationActionToken.self, from: data)
        guard FocusNotificationRules.isValid(token) else {
            throw FocusNotificationActionTokenStoreError.invalidToken
        }
        return token
    }

    public static func write(
        _ token: FocusNotificationActionToken,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard FocusNotificationRules.isValid(token) else {
            throw FocusNotificationActionTokenStoreError.invalidToken
        }
        let fileURL = try resolvedFileURL(directoryURL, fileManager: fileManager)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(token).write(
            to: fileURL,
            options: FocusActiveSessionStore.snapshotWritingOptions
        )
    }

    public static func clear(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let fileURL = try resolvedFileURL(directoryURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

private extension FocusNotificationActionTokenStore {
    struct FormatEnvelope: Decodable {
        let formatVersion: Int
    }

    static func resolvedFileURL(
        _ directoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        if let directoryURL {
            return directoryURL.appendingPathComponent(fileName)
        }
        if let testing = FocusModeConstants.uiTestingDirectory {
            return testing.appendingPathComponent(fileName)
        }
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: FocusModeConstants.appGroupIdentifier
        ) else {
            throw FocusNotificationActionTokenStoreError.appGroupContainerUnavailable
        }
        return groupURL
            .appendingPathComponent(FocusModeConstants.directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

public enum FocusNotificationActionResult: Equatable, Sendable {
    case dismissed
    case started(FocusActiveSessionSnapshot)
}

public enum FocusNotificationActionService {
    @MainActor
    public static func perform(
        action: FocusNotificationAction,
        tokenID: UUID,
        sessionID: UUID,
        revision: Int,
        phase: FocusTimerPhase,
        deadline: Date,
        now: Date = Date(),
        in context: ModelContext,
        directoryURL: URL? = nil
    ) throws -> FocusNotificationActionResult {
        guard action != .open,
              let token = try FocusNotificationActionTokenStore.read(
                directoryURL: directoryURL
              ),
              token.tokenID == tokenID,
              token.sessionID == sessionID,
              token.revision == revision,
              token.phase == phase,
              token.deadline == deadline,
              FocusNotificationRules.isActionable(token, now: now) else {
            throw FocusNotificationRulesError.staleAction
        }

        if let active = try FocusSessionService.activeSnapshot(directoryURL: directoryURL) {
            guard FocusNotificationRules.matches(token, snapshot: active),
                  FocusTimerRules.hasReachedDeadline(active, now: now) else {
                throw FocusNotificationRulesError.staleAction
            }
            _ = try FocusSessionService.reconcile(
                now: now,
                in: context,
                directoryURL: directoryURL
            )
        }

        guard try FocusSessionService.activeSnapshot(directoryURL: directoryURL) == nil else {
            throw FocusNotificationRulesError.staleAction
        }
        if phase == .focus {
            try validateCompletedFocus(token, in: context)
        }

        if action == .dismiss {
            try FocusNotificationActionTokenStore.clear(directoryURL: directoryURL)
            return .dismissed
        }

        let started: FocusActiveSessionSnapshot
        switch (phase, action) {
        case (.focus, .startBreak):
            started = try FocusSessionService.beginBreak(
                taskID: token.taskID,
                taskTitle: token.taskTitleSnapshot,
                focusSeconds: token.plannedFocusSeconds,
                breakSeconds: token.plannedBreakSeconds,
                now: now,
                directoryURL: directoryURL
            )
        case (.focus, .continueFocus), (.breakTime, .startFocus):
            started = try FocusSessionService.beginFocus(
                taskID: token.taskID,
                focusSeconds: token.plannedFocusSeconds,
                breakSeconds: token.plannedBreakSeconds,
                now: now,
                in: context,
                directoryURL: directoryURL
            )
        case (.breakTime, .extendBreak):
            started = try FocusSessionService.beginBreak(
                taskID: token.taskID,
                taskTitle: token.taskTitleSnapshot,
                focusSeconds: token.plannedFocusSeconds,
                breakSeconds: FocusNotificationRules.extensionBreakSeconds,
                now: now,
                directoryURL: directoryURL
            )
        default:
            throw FocusNotificationRulesError.actionNotAvailable
        }
        try? FocusNotificationActionTokenStore.clear(directoryURL: directoryURL)
        return .started(started)
    }
}

public final class FocusPresentationVisibilityStore: @unchecked Sendable {
    public static let shared = FocusPresentationVisibilityStore()

    private let lock = NSLock()
    private var counts: [UUID: Int] = [:]

    public init() {}

    public func show(sessionID: UUID) {
        lock.lock()
        counts[sessionID, default: 0] += 1
        lock.unlock()
    }

    public func hide(sessionID: UUID) {
        lock.lock()
        let next = max(0, counts[sessionID, default: 0] - 1)
        if next == 0 {
            counts.removeValue(forKey: sessionID)
        } else {
            counts[sessionID] = next
        }
        lock.unlock()
    }

    public func isVisible(sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return counts[sessionID, default: 0] > 0
    }
}

private extension FocusNotificationActionService {
    @MainActor
    static func validateCompletedFocus(
        _ token: FocusNotificationActionToken,
        in context: ModelContext
    ) throws {
        let id = token.sessionID
        let instanceID = token.instanceID
        let candidates = try context.fetch(FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { session in
                session.id == id &&
                    session.instanceID == instanceID &&
                    session.supersededAt == nil
            }
        ))
        guard candidates.contains(where: { session in
            session.taskId == token.taskID &&
                session.endedAt == token.deadline &&
                session.plannedDurationSeconds == token.plannedFocusSeconds &&
                session.outcomeRawValue == FocusSessionOutcome.completed.rawValue
        }) else {
            throw FocusNotificationRulesError.staleAction
        }
    }
}
