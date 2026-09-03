import Foundation

public enum FocusTimerPhase: String, Codable, Sendable {
    case focus
    case breakTime
}

public enum FocusTimerRunState: String, Codable, Sendable {
    case running
    case paused
}

public struct FocusActiveSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var revision: Int
    public var sessionID: UUID
    public var instanceID: UUID
    public var taskID: UUID
    public var taskTitleSnapshot: String
    public var phaseRawValue: String
    public var runStateRawValue: String
    public var phaseStartedAt: Date
    public var segmentStartedAt: Date?
    public var deadline: Date?
    public var remainingSecondsAtPause: TimeInterval?
    public var accumulatedFocusedSeconds: TimeInterval
    public var plannedFocusSeconds: Int
    public var plannedBreakSeconds: Int
    public var updatedAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        revision: Int = 1,
        sessionID: UUID = UUID(),
        instanceID: UUID = UUID(),
        taskID: UUID,
        taskTitleSnapshot: String,
        phase: FocusTimerPhase,
        runState: FocusTimerRunState,
        phaseStartedAt: Date,
        segmentStartedAt: Date?,
        deadline: Date?,
        remainingSecondsAtPause: TimeInterval?,
        accumulatedFocusedSeconds: TimeInterval,
        plannedFocusSeconds: Int,
        plannedBreakSeconds: Int,
        updatedAt: Date
    ) {
        self.formatVersion = formatVersion
        self.revision = revision
        self.sessionID = sessionID
        self.instanceID = instanceID
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.phaseRawValue = phase.rawValue
        self.runStateRawValue = runState.rawValue
        self.phaseStartedAt = phaseStartedAt
        self.segmentStartedAt = segmentStartedAt
        self.deadline = deadline
        self.remainingSecondsAtPause = remainingSecondsAtPause
        self.accumulatedFocusedSeconds = accumulatedFocusedSeconds
        self.plannedFocusSeconds = plannedFocusSeconds
        self.plannedBreakSeconds = plannedBreakSeconds
        self.updatedAt = updatedAt
    }

    public var phase: FocusTimerPhase? {
        FocusTimerPhase(rawValue: phaseRawValue)
    }

    public var runState: FocusTimerRunState? {
        FocusTimerRunState(rawValue: runStateRawValue)
    }
}

public struct FocusSessionTerminalDraft: Equatable, Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var taskID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var plannedDurationSeconds: Int
    public var focusedDurationSeconds: Int
    public var outcome: FocusSessionOutcome

    public init(
        id: UUID,
        instanceID: UUID,
        taskID: UUID,
        startedAt: Date,
        endedAt: Date,
        plannedDurationSeconds: Int,
        focusedDurationSeconds: Int,
        outcome: FocusSessionOutcome
    ) {
        self.id = id
        self.instanceID = instanceID
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.focusedDurationSeconds = focusedDurationSeconds
        self.outcome = outcome
    }
}

public enum FocusTimerRulesError: LocalizedError, Equatable {
    case invalidSnapshot
    case invalidTransition
    case staleCommand

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            "저장된 집중 타이머 상태가 올바르지 않습니다."
        case .invalidTransition:
            "현재 상태에서는 요청한 타이머 동작을 수행할 수 없습니다."
        case .staleCommand:
            "타이머 상태가 이미 변경되었습니다."
        }
    }
}

public enum FocusTimerRules {
    public static let defaultFocusSeconds = 25 * 60
    public static let defaultBreakSeconds = 5 * 60
    public static let minimumFocusSeconds = 5 * 60
    public static let maximumFocusSeconds = 120 * 60
    public static let minimumBreakSeconds = 60
    public static let maximumBreakSeconds = 30 * 60

    public static func normalizedFocusSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumFocusSeconds), maximumFocusSeconds)
    }

    public static func normalizedBreakSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumBreakSeconds), maximumBreakSeconds)
    }

    public static func startFocus(
        taskID: UUID,
        taskTitle: String,
        focusSeconds: Int = defaultFocusSeconds,
        breakSeconds: Int = defaultBreakSeconds,
        now: Date = Date(),
        sessionID: UUID = UUID(),
        instanceID: UUID = UUID()
    ) -> FocusActiveSessionSnapshot {
        let plannedFocusSeconds = normalizedFocusSeconds(focusSeconds)
        let plannedBreakSeconds = normalizedBreakSeconds(breakSeconds)
        return FocusActiveSessionSnapshot(
            sessionID: sessionID,
            instanceID: instanceID,
            taskID: taskID,
            taskTitleSnapshot: normalizedTitle(taskTitle),
            phase: .focus,
            runState: .running,
            phaseStartedAt: now,
            segmentStartedAt: now,
            deadline: now.addingTimeInterval(TimeInterval(plannedFocusSeconds)),
            remainingSecondsAtPause: nil,
            accumulatedFocusedSeconds: 0,
            plannedFocusSeconds: plannedFocusSeconds,
            plannedBreakSeconds: plannedBreakSeconds,
            updatedAt: now
        )
    }

    public static func startBreak(
        taskID: UUID,
        taskTitle: String,
        focusSeconds: Int = defaultFocusSeconds,
        breakSeconds: Int = defaultBreakSeconds,
        now: Date = Date(),
        sessionID: UUID = UUID(),
        instanceID: UUID = UUID()
    ) -> FocusActiveSessionSnapshot {
        let plannedFocusSeconds = normalizedFocusSeconds(focusSeconds)
        let plannedBreakSeconds = normalizedBreakSeconds(breakSeconds)
        return FocusActiveSessionSnapshot(
            sessionID: sessionID,
            instanceID: instanceID,
            taskID: taskID,
            taskTitleSnapshot: normalizedTitle(taskTitle),
            phase: .breakTime,
            runState: .running,
            phaseStartedAt: now,
            segmentStartedAt: now,
            deadline: now.addingTimeInterval(TimeInterval(plannedBreakSeconds)),
            remainingSecondsAtPause: nil,
            accumulatedFocusedSeconds: 0,
            plannedFocusSeconds: plannedFocusSeconds,
            plannedBreakSeconds: plannedBreakSeconds,
            updatedAt: now
        )
    }

    public static func remainingSeconds(
        for snapshot: FocusActiveSessionSnapshot,
        now: Date = Date()
    ) -> TimeInterval {
        let planned = TimeInterval(
            snapshot.phase == .focus
                ? snapshot.plannedFocusSeconds
                : snapshot.plannedBreakSeconds
        )
        switch snapshot.runState {
        case .running:
            guard let deadline = snapshot.deadline else { return 0 }
            return min(planned, max(0, deadline.timeIntervalSince(now)))
        case .paused:
            return min(planned, max(0, snapshot.remainingSecondsAtPause ?? 0))
        case nil:
            return 0
        }
    }

    public static func focusedDurationSeconds(
        for snapshot: FocusActiveSessionSnapshot,
        now: Date = Date()
    ) -> TimeInterval {
        guard snapshot.phase == .focus else { return 0 }
        var duration = snapshot.accumulatedFocusedSeconds
        if snapshot.runState == .running, let segmentStartedAt = snapshot.segmentStartedAt {
            duration += max(0, now.timeIntervalSince(segmentStartedAt))
        }
        return min(TimeInterval(snapshot.plannedFocusSeconds), max(0, duration))
    }

    public static func hasReachedDeadline(
        _ snapshot: FocusActiveSessionSnapshot,
        now: Date = Date()
    ) -> Bool {
        snapshot.runState == .running &&
            snapshot.deadline.map { $0 <= now } == true
    }

    public static func pause(
        _ snapshot: FocusActiveSessionSnapshot,
        expectedSessionID: UUID? = nil,
        expectedRevision: Int? = nil,
        now: Date = Date()
    ) throws -> FocusActiveSessionSnapshot {
        try validateCommand(
            snapshot,
            expectedSessionID: expectedSessionID,
            expectedRevision: expectedRevision
        )
        guard snapshot.runState == .running, !hasReachedDeadline(snapshot, now: now) else {
            throw FocusTimerRulesError.invalidTransition
        }

        var result = snapshot
        result.revision += 1
        result.runStateRawValue = FocusTimerRunState.paused.rawValue
        result.remainingSecondsAtPause = remainingSeconds(for: snapshot, now: now)
        if snapshot.phase == .focus {
            result.accumulatedFocusedSeconds = focusedDurationSeconds(
                for: snapshot,
                now: now
            )
        }
        result.segmentStartedAt = nil
        result.deadline = nil
        result.updatedAt = now
        return result
    }

    public static func resume(
        _ snapshot: FocusActiveSessionSnapshot,
        expectedSessionID: UUID? = nil,
        expectedRevision: Int? = nil,
        now: Date = Date()
    ) throws -> FocusActiveSessionSnapshot {
        try validateCommand(
            snapshot,
            expectedSessionID: expectedSessionID,
            expectedRevision: expectedRevision
        )
        guard snapshot.runState == .paused else {
            throw FocusTimerRulesError.invalidTransition
        }
        let remaining = remainingSeconds(for: snapshot, now: now)
        guard remaining > 0 else { throw FocusTimerRulesError.invalidTransition }

        var result = snapshot
        result.revision += 1
        result.runStateRawValue = FocusTimerRunState.running.rawValue
        result.segmentStartedAt = now
        result.deadline = now.addingTimeInterval(remaining)
        result.remainingSecondsAtPause = nil
        result.updatedAt = now
        return result
    }

    public static func terminalDraft(
        for snapshot: FocusActiveSessionSnapshot,
        requestedOutcome: FocusSessionOutcome,
        now: Date = Date()
    ) throws -> FocusSessionTerminalDraft {
        guard snapshot.phase == .focus else {
            throw FocusTimerRulesError.invalidTransition
        }
        guard isValid(snapshot) else { throw FocusTimerRulesError.invalidSnapshot }

        let didReachDeadline = hasReachedDeadline(snapshot, now: now)
        let outcome: FocusSessionOutcome = didReachDeadline ? .completed : requestedOutcome
        let proposedEnd = didReachDeadline ? (snapshot.deadline ?? now) : now
        let endedAt = max(snapshot.phaseStartedAt, proposedEnd)
        let focusedDuration = didReachDeadline
            ? snapshot.plannedFocusSeconds
            : Int(focusedDurationSeconds(for: snapshot, now: endedAt).rounded(.down))
        return FocusSessionTerminalDraft(
            id: snapshot.sessionID,
            instanceID: snapshot.instanceID,
            taskID: snapshot.taskID,
            startedAt: snapshot.phaseStartedAt,
            endedAt: endedAt,
            plannedDurationSeconds: snapshot.plannedFocusSeconds,
            focusedDurationSeconds: min(
                snapshot.plannedFocusSeconds,
                max(0, focusedDuration)
            ),
            outcome: outcome
        )
    }

    public static func isValid(_ snapshot: FocusActiveSessionSnapshot) -> Bool {
        guard snapshot.formatVersion == FocusActiveSessionSnapshot.currentFormatVersion,
              snapshot.revision >= 1,
              snapshot.phase != nil,
              snapshot.runState != nil,
              snapshot.phaseStartedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.accumulatedFocusedSeconds.isFinite,
              snapshot.accumulatedFocusedSeconds >= 0,
              snapshot.plannedFocusSeconds == normalizedFocusSeconds(
                snapshot.plannedFocusSeconds
              ),
              snapshot.plannedBreakSeconds == normalizedBreakSeconds(
                snapshot.plannedBreakSeconds
              ) else {
            return false
        }
        switch snapshot.runState {
        case .running:
            return snapshot.segmentStartedAt?.timeIntervalSinceReferenceDate.isFinite == true &&
                snapshot.deadline?.timeIntervalSinceReferenceDate.isFinite == true &&
                snapshot.remainingSecondsAtPause == nil
        case .paused:
            return snapshot.segmentStartedAt == nil &&
                snapshot.deadline == nil &&
                snapshot.remainingSecondsAtPause?.isFinite == true &&
                (snapshot.remainingSecondsAtPause ?? -1) >= 0
        case nil:
            return false
        }
    }
}

private extension FocusTimerRules {
    static func normalizedTitle(_ title: String) -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "집중 작업" : value
    }

    static func validateCommand(
        _ snapshot: FocusActiveSessionSnapshot,
        expectedSessionID: UUID?,
        expectedRevision: Int?
    ) throws {
        guard isValid(snapshot) else { throw FocusTimerRulesError.invalidSnapshot }
        if let expectedSessionID, snapshot.sessionID != expectedSessionID {
            throw FocusTimerRulesError.staleCommand
        }
        if let expectedRevision, snapshot.revision != expectedRevision {
            throw FocusTimerRulesError.staleCommand
        }
    }
}
