import Foundation
import SwiftData

public enum FocusSessionServiceError: LocalizedError, Equatable {
    case activeSessionAlreadyExists(UUID)
    case noActiveSession
    case staleCommand
    case taskUnavailable
    case taskAlreadyCompleted
    case terminalRecordConflict
    case backupImportBlockedByActiveSession

    public var errorDescription: String? {
        switch self {
        case .activeSessionAlreadyExists:
            "이미 진행 중인 집중 또는 휴식 타이머가 있습니다."
        case .noActiveSession:
            "진행 중인 집중 타이머가 없습니다."
        case .staleCommand:
            "타이머 상태가 이미 변경되었습니다. 현재 상태를 다시 확인해 주세요."
        case .taskUnavailable:
            "집중할 작업을 찾을 수 없거나 보관된 작업입니다."
        case .taskAlreadyCompleted:
            "완료된 작업에는 집중 타이머를 시작할 수 없습니다."
        case .terminalRecordConflict:
            "이미 저장된 집중 기록과 충돌해 타이머를 종료하지 못했습니다."
        case .backupImportBlockedByActiveSession:
            "진행 중인 집중 또는 휴식 타이머를 종료한 뒤 백업을 가져와 주세요."
        }
    }
}

public enum FocusSessionReconciliationResult {
    case unchanged(FocusActiveSessionSnapshot)
    case focusEnded(FocusSession)
    case breakEnded
    case noActiveSession
}

public enum FocusSessionService {
    @MainActor
    public static func beginFocus(
        taskID: UUID,
        focusSeconds: Int = FocusTimerRules.defaultFocusSeconds,
        breakSeconds: Int = FocusTimerRules.defaultBreakSeconds,
        now: Date = Date(),
        in context: ModelContext,
        directoryURL: URL? = nil
    ) throws -> FocusActiveSessionSnapshot {
        if let existing = try FocusActiveSessionStore.read(directoryURL: directoryURL) {
            throw FocusSessionServiceError.activeSessionAlreadyExists(existing.sessionID)
        }

        guard let task = try canonicalTask(id: taskID, in: context),
              task.archivedAt == nil else {
            throw FocusSessionServiceError.taskUnavailable
        }
        let status = TaskStatus(rawValue: task.status) ?? .todo
        guard status != .done else {
            throw FocusSessionServiceError.taskAlreadyCompleted
        }

        let snapshot = FocusTimerRules.startFocus(
            taskID: task.id,
            taskTitle: task.title,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            now: now
        )
        if status == .todo {
            try PersistenceCommandService.perform(in: context) {
                _ = try TaskLifecycleService.applyStatus(
                    .doing,
                    to: task,
                    in: context,
                    now: now
                )
            }
        }
        // A crash between these two durable writes can leave a Task in `doing`,
        // but it must never create a ghost Focus for a Task transition that failed.
        try FocusActiveSessionStore.write(snapshot, directoryURL: directoryURL)
        return snapshot
    }

    public static func activeSnapshot(
        directoryURL: URL? = nil
    ) throws -> FocusActiveSessionSnapshot? {
        try FocusActiveSessionStore.read(directoryURL: directoryURL)
    }

    public static func requireNoActiveSessionForBackupImport(
        directoryURL: URL? = nil
    ) throws {
        guard try FocusActiveSessionStore.read(directoryURL: directoryURL) == nil else {
            throw FocusSessionServiceError.backupImportBlockedByActiveSession
        }
    }

    public static func pause(
        expectedSessionID: UUID,
        expectedRevision: Int,
        now: Date = Date(),
        directoryURL: URL? = nil
    ) throws -> FocusActiveSessionSnapshot {
        let snapshot = try requiredSnapshot(
            expectedSessionID: expectedSessionID,
            expectedRevision: expectedRevision,
            directoryURL: directoryURL
        )
        let updated: FocusActiveSessionSnapshot
        do {
            updated = try FocusTimerRules.pause(
                snapshot,
                expectedSessionID: expectedSessionID,
                expectedRevision: expectedRevision,
                now: now
            )
        } catch FocusTimerRulesError.staleCommand {
            throw FocusSessionServiceError.staleCommand
        }
        try FocusActiveSessionStore.write(updated, directoryURL: directoryURL)
        return updated
    }

    public static func resume(
        expectedSessionID: UUID,
        expectedRevision: Int,
        now: Date = Date(),
        directoryURL: URL? = nil
    ) throws -> FocusActiveSessionSnapshot {
        let snapshot = try requiredSnapshot(
            expectedSessionID: expectedSessionID,
            expectedRevision: expectedRevision,
            directoryURL: directoryURL
        )
        let updated: FocusActiveSessionSnapshot
        do {
            updated = try FocusTimerRules.resume(
                snapshot,
                expectedSessionID: expectedSessionID,
                expectedRevision: expectedRevision,
                now: now
            )
        } catch FocusTimerRulesError.staleCommand {
            throw FocusSessionServiceError.staleCommand
        }
        try FocusActiveSessionStore.write(updated, directoryURL: directoryURL)
        return updated
    }

    @MainActor
    @discardableResult
    public static func endFocus(
        outcome: FocusSessionOutcome,
        expectedSessionID: UUID,
        expectedRevision: Int,
        now: Date = Date(),
        in context: ModelContext,
        directoryURL: URL? = nil
    ) throws -> FocusSession? {
        let snapshot = try requiredSnapshot(
            expectedSessionID: expectedSessionID,
            expectedRevision: expectedRevision,
            directoryURL: directoryURL
        )
        let draft = try FocusTimerRules.terminalDraft(
            for: snapshot,
            requestedOutcome: outcome,
            now: now
        )

        let record: FocusSession? = if draft.focusedDurationSeconds > 0 {
            try PersistenceCommandService.perform(in: context) {
                try persist(draft, at: now, in: context)
            }
        } else {
            nil
        }
        try FocusActiveSessionStore.clear(directoryURL: directoryURL)
        return record
    }

    public static func beginBreak(
        taskID: UUID,
        taskTitle: String,
        focusSeconds: Int = FocusTimerRules.defaultFocusSeconds,
        breakSeconds: Int = FocusTimerRules.defaultBreakSeconds,
        now: Date = Date(),
        directoryURL: URL? = nil
    ) throws -> FocusActiveSessionSnapshot {
        if let existing = try FocusActiveSessionStore.read(directoryURL: directoryURL) {
            throw FocusSessionServiceError.activeSessionAlreadyExists(existing.sessionID)
        }
        let snapshot = FocusTimerRules.startBreak(
            taskID: taskID,
            taskTitle: taskTitle,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            now: now
        )
        try FocusActiveSessionStore.write(snapshot, directoryURL: directoryURL)
        return snapshot
    }

    @MainActor
    public static func reconcile(
        now: Date = Date(),
        in context: ModelContext,
        directoryURL: URL? = nil
    ) throws -> FocusSessionReconciliationResult {
        guard let snapshot = try FocusActiveSessionStore.read(directoryURL: directoryURL) else {
            return .noActiveSession
        }

        if FocusTimerRules.hasReachedDeadline(snapshot, now: now) {
            if snapshot.phase == .breakTime {
                try FocusActiveSessionStore.clear(directoryURL: directoryURL)
                return .breakEnded
            }
            let record = try endFocus(
                outcome: .completed,
                expectedSessionID: snapshot.sessionID,
                expectedRevision: snapshot.revision,
                now: now,
                in: context,
                directoryURL: directoryURL
            )
            if let record { return .focusEnded(record) }
            return .noActiveSession
        }

        guard snapshot.phase == .focus else { return .unchanged(snapshot) }
        guard let task = try canonicalTask(id: snapshot.taskID, in: context),
              task.archivedAt == nil else {
            return try endAsInterrupted(
                snapshot,
                now: now,
                in: context,
                directoryURL: directoryURL
            )
        }
        if TaskStatus(rawValue: task.status) == .done {
            let record = try endFocus(
                outcome: .taskCompleted,
                expectedSessionID: snapshot.sessionID,
                expectedRevision: snapshot.revision,
                now: now,
                in: context,
                directoryURL: directoryURL
            )
            if let record { return .focusEnded(record) }
            return .noActiveSession
        }
        return .unchanged(snapshot)
    }
}

private extension FocusSessionService {
    static func requiredSnapshot(
        expectedSessionID: UUID,
        expectedRevision: Int,
        directoryURL: URL?
    ) throws -> FocusActiveSessionSnapshot {
        guard let snapshot = try FocusActiveSessionStore.read(directoryURL: directoryURL) else {
            throw FocusSessionServiceError.noActiveSession
        }
        guard snapshot.sessionID == expectedSessionID,
              snapshot.revision == expectedRevision else {
            throw FocusSessionServiceError.staleCommand
        }
        return snapshot
    }

    @MainActor
    static func canonicalTask(id: UUID, in context: ModelContext) throws -> Task? {
        try BoundedQueryService.representativeTask(
            from: context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: id))
        )
    }

    @MainActor
    static func persist(
        _ draft: FocusSessionTerminalDraft,
        at timestamp: Date,
        in context: ModelContext
    ) throws -> FocusSession {
        let id = draft.id
        let candidates = try context.fetch(FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { session in
                session.id == id && session.supersededAt == nil
            }
        ))
        if let identical = candidates.first(where: { matches($0, draft: draft) }) {
            return identical
        }
        if candidates.contains(where: { $0.instanceID == draft.instanceID }) {
            throw FocusSessionServiceError.terminalRecordConflict
        }

        let session = FocusSession(
            id: draft.id,
            instanceID: draft.instanceID,
            taskId: draft.taskID,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            plannedDurationSeconds: draft.plannedDurationSeconds,
            focusedDurationSeconds: draft.focusedDurationSeconds,
            outcome: draft.outcome,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(session)
        return session
    }

    static func matches(
        _ session: FocusSession,
        draft: FocusSessionTerminalDraft
    ) -> Bool {
        session.id == draft.id &&
            session.instanceID == draft.instanceID &&
            session.taskId == draft.taskID &&
            session.startedAt == draft.startedAt &&
            session.endedAt == draft.endedAt &&
            session.plannedDurationSeconds == draft.plannedDurationSeconds &&
            session.focusedDurationSeconds == draft.focusedDurationSeconds &&
            session.outcomeRawValue == draft.outcome.rawValue
    }

    @MainActor
    static func endAsInterrupted(
        _ snapshot: FocusActiveSessionSnapshot,
        now: Date,
        in context: ModelContext,
        directoryURL: URL?
    ) throws -> FocusSessionReconciliationResult {
        let record = try endFocus(
            outcome: .interrupted,
            expectedSessionID: snapshot.sessionID,
            expectedRevision: snapshot.revision,
            now: now,
            in: context,
            directoryURL: directoryURL
        )
        if let record { return .focusEnded(record) }
        return .noActiveSession
    }
}
