import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func focusTimerPauseResumeAndTerminalDurationUseWallClockDeadlines() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = FocusTimerRules.startFocus(
        taskID: UUID(),
        taskTitle: "집중 테스트",
        focusSeconds: 25 * 60,
        breakSeconds: 5 * 60,
        now: start
    )
    let paused = try FocusTimerRules.pause(snapshot, now: start.addingTimeInterval(90))
    #expect(paused.runState == .paused)
    #expect(paused.accumulatedFocusedSeconds == 90)
    #expect(paused.remainingSecondsAtPause == 1_410)

    let resumedAt = start.addingTimeInterval(300)
    let resumed = try FocusTimerRules.resume(paused, now: resumedAt)
    #expect(resumed.deadline == resumedAt.addingTimeInterval(1_410))

    let draft = try FocusTimerRules.terminalDraft(
        for: resumed,
        requestedOutcome: .stopped,
        now: resumedAt.addingTimeInterval(120)
    )
    #expect(draft.outcome == .stopped)
    #expect(draft.focusedDurationSeconds == 210)
}

@Test
func focusTimerDeadlineAlwaysWinsOverLateStopCommand() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = FocusTimerRules.startFocus(
        taskID: UUID(),
        taskTitle: "마감 우선순위",
        focusSeconds: 5 * 60,
        now: start
    )
    let draft = try FocusTimerRules.terminalDraft(
        for: snapshot,
        requestedOutcome: .stopped,
        now: start.addingTimeInterval(330)
    )

    #expect(draft.outcome == .completed)
    #expect(draft.endedAt == start.addingTimeInterval(300))
    #expect(draft.focusedDurationSeconds == 300)
}

@Test
func focusActiveStoreRoundTripsAndRejectsStaleRevision() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshot = FocusTimerRules.startFocus(
        taskID: UUID(),
        taskTitle: "로컬 상태",
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    try FocusActiveSessionStore.write(snapshot, directoryURL: directory)
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == snapshot)
    #expect(throws: FocusSessionServiceError.staleCommand) {
        try FocusSessionService.pause(
            expectedSessionID: snapshot.sessionID,
            expectedRevision: snapshot.revision + 1,
            directoryURL: directory
        )
    }
    try FocusActiveSessionStore.clear(directoryURL: directory)
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == nil)
}

@Test
@MainActor
func focusServiceStartsTaskAndPersistsOneTerminalRecord() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let task = Task(title: "집중할 일", plannedAt: start, order: 100)
    context.insert(task)

    let active = try FocusSessionService.beginFocus(
        taskID: task.id,
        focusSeconds: 25 * 60,
        now: start,
        in: context,
        directoryURL: directory
    )
    #expect(task.status == TaskStatus.doing.rawValue)

    let endedRecord = try FocusSessionService.endFocus(
        outcome: .stopped,
        expectedSessionID: active.sessionID,
        expectedRevision: active.revision,
        now: start.addingTimeInterval(125),
        in: context,
        directoryURL: directory
    )
    let record = try #require(endedRecord)
    #expect(record.taskId == task.id)
    #expect(record.focusedDurationSeconds == 125)
    #expect(record.outcomeRawValue == FocusSessionOutcome.stopped.rawValue)
    #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == nil)
}

@Test(arguments: [false, true])
func endingBreakRejectsStaleCommandsAndClearsOnlyCurrentSession(paused: Bool) throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var active = try FocusSessionService.beginBreak(
        taskID: UUID(), taskTitle: "휴식 종료", now: now, directoryURL: directory
    )
    if paused {
        active = try FocusSessionService.pause(
            expectedSessionID: active.sessionID, expectedRevision: active.revision,
            now: now.addingTimeInterval(20), directoryURL: directory
        )
    }
    #expect(throws: FocusSessionServiceError.staleCommand) {
        try FocusSessionService.endBreak(
            expectedSessionID: active.sessionID, expectedRevision: active.revision + 1,
            directoryURL: directory
        )
    }
    #expect(throws: FocusSessionServiceError.staleCommand) {
        try FocusSessionService.endBreak(
            expectedSessionID: UUID(), expectedRevision: active.revision,
            directoryURL: directory
        )
    }
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == active)
    try FocusSessionService.endBreak(
        expectedSessionID: active.sessionID, expectedRevision: active.revision,
        directoryURL: directory
    )
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == nil)
}

@Test
func endingBreakCannotDiscardAnActiveFocus() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = FocusTimerRules.startFocus(
        taskID: UUID(), taskTitle: "보존할 집중",
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try FocusActiveSessionStore.write(active, directoryURL: directory)
    #expect(throws: FocusTimerRulesError.invalidTransition) {
        try FocusSessionService.endBreak(
            expectedSessionID: active.sessionID, expectedRevision: active.revision,
            directoryURL: directory
        )
    }
    #expect(try FocusActiveSessionStore.read(directoryURL: directory) == active)
}

@Test
@MainActor
func focusReconciliationEndsForTaskCompletionAndDeadline() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let task = Task(title: "완료 수렴", plannedAt: start, order: 100)
    context.insert(task)

    _ = try FocusSessionService.beginFocus(
        taskID: task.id,
        focusSeconds: 300,
        now: start,
        in: context,
        directoryURL: directory
    )
    try PersistenceCommandService.perform(in: context) {
        _ = try TaskLifecycleService.applyStatus(
            .done,
            to: task,
            in: context,
            now: start.addingTimeInterval(90)
        )
    }
    let taskCompletion = try FocusSessionService.reconcile(
        now: start.addingTimeInterval(90),
        in: context,
        directoryURL: directory
    )
    guard case .focusEnded(let completedTaskRecord) = taskCompletion else {
        Issue.record("Task completion should end the active Focus")
        return
    }
    #expect(completedTaskRecord.outcomeRawValue == FocusSessionOutcome.taskCompleted.rawValue)
    #expect(completedTaskRecord.focusedDurationSeconds == 90)

    let secondTask = Task(title: "마감 수렴", plannedAt: start, order: 200)
    context.insert(secondTask)
    _ = try FocusSessionService.beginFocus(
        taskID: secondTask.id,
        focusSeconds: 300,
        now: start,
        in: context,
        directoryURL: directory
    )
    let deadline = try FocusSessionService.reconcile(
        now: start.addingTimeInterval(330),
        in: context,
        directoryURL: directory
    )
    guard case .focusEnded(let deadlineRecord) = deadline else {
        Issue.record("Deadline should end the active Focus")
        return
    }
    #expect(deadlineRecord.outcomeRawValue == FocusSessionOutcome.completed.rawValue)
    #expect(deadlineRecord.endedAt == start.addingTimeInterval(300))
    #expect(deadlineRecord.focusedDurationSeconds == 300)
}

@Test
func activeFocusBlocksBackupImportUntilSnapshotIsCleared() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FocusSessionService.requireNoActiveSessionForBackupImport(
        directoryURL: directory
    )

    let snapshot = FocusTimerRules.startFocus(
        taskID: UUID(),
        taskTitle: "백업 경계"
    )
    try FocusActiveSessionStore.write(snapshot, directoryURL: directory)
    #expect(throws: FocusSessionServiceError.backupImportBlockedByActiveSession) {
        try FocusSessionService.requireNoActiveSessionForBackupImport(
            directoryURL: directory
        )
    }
}

@Test
@MainActor
func focusIntegrityClampsDurationAndConvergesDuplicates() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let logicalID = UUID()
    let taskID = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let older = FocusSession(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        taskId: taskID,
        startedAt: start,
        endedAt: start.addingTimeInterval(60),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 60,
        outcome: .stopped,
        createdAt: start,
        updatedAt: start.addingTimeInterval(60)
    )
    let newer = FocusSession(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        taskId: taskID,
        startedAt: start,
        endedAt: start.addingTimeInterval(400),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 999,
        outcome: .completed,
        createdAt: start.addingTimeInterval(10),
        updatedAt: start.addingTimeInterval(400)
    )
    context.insert(older)
    context.insert(newer)
    try context.save()

    let report = try FocusSessionIntegrityService.reconcile(in: context)
    #expect(report.mergedRecords == 1)
    #expect(older.supersededAt == newer.updatedAt)
    #expect(newer.supersededAt == nil)
    #expect(newer.focusedDurationSeconds == 300)
    #expect(newer.createdAt == start)
}

@Test
@MainActor
func focusHistoryRoundTripsThroughCurrentBackupFormats() throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    source.mainContext.insert(FocusSession(
        taskId: UUID(),
        startedAt: start,
        endedAt: start.addingTimeInterval(300),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 300,
        outcome: .completed,
        createdAt: start,
        updatedAt: start.addingTimeInterval(300)
    ))
    try source.mainContext.save()

    let payload = try BackupCodec.makePayload(context: source.mainContext)
    #expect(payload.backupVersion == 2)
    #expect(payload.focusSessions?.count == 1)

    let package = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(package.manifest.formatVersion == 10)
    #expect(package.records.payload.focusSessions?.count == 1)

    let destination = try PlanBaseContainerFactory.makeInMemory()
    try BackupPackageCodec.restoreMerging(package, into: destination.mainContext)
    let restored = try #require(destination.mainContext.fetch(
        FetchDescriptor<FocusSession>()
    ).first)
    #expect(restored.focusedDurationSeconds == 300)
    #expect(restored.outcomeRawValue == FocusSessionOutcome.completed.rawValue)
}

@Test
@MainActor
func focusDaySummaryIsDateBoundedAndConvergesLogicalDuplicates() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = DayKey.startOfDay(for: Date())
    let logicalID = UUID()
    let taskID = UUID()

    context.insert(FocusSession(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        taskId: taskID,
        startedAt: today.addingTimeInterval(100),
        endedAt: today.addingTimeInterval(400),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 120,
        outcome: .stopped,
        createdAt: today,
        updatedAt: today.addingTimeInterval(400)
    ))
    context.insert(FocusSession(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        taskId: taskID,
        startedAt: today.addingTimeInterval(100),
        endedAt: today.addingTimeInterval(400),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 300,
        outcome: .completed,
        createdAt: today,
        updatedAt: today.addingTimeInterval(500)
    ))
    context.insert(FocusSession(
        taskId: taskID,
        startedAt: DayKey.addingDays(-1, to: today),
        endedAt: DayKey.addingDays(-1, to: today).addingTimeInterval(300),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 300,
        outcome: .completed,
        createdAt: today,
        updatedAt: today
    ))
    try context.save()

    let summary = try FocusSessionQueryService.summary(in: context)
    #expect(summary.sessionCount == 1)
    #expect(summary.completedCount == 1)
    #expect(summary.focusedDurationSeconds == 300)
}

@Test
func focusNotificationTokenRoundTripsAndExpiresAfterGracePeriod() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = FocusTimerRules.startFocus(
        taskID: UUID(),
        taskTitle: "알림 테스트",
        focusSeconds: 25 * 60,
        breakSeconds: 5 * 60,
        now: start
    )
    let requestID = try FocusNotificationRules.requestIdentifier(
        namespace: "planbase.focus.test",
        snapshot: snapshot
    )
    let token = try FocusNotificationRules.makeToken(
        snapshot: snapshot,
        requestIdentifier: requestID
    )

    try FocusNotificationActionTokenStore.write(token, directoryURL: directory)
    #expect(try FocusNotificationActionTokenStore.read(directoryURL: directory) == token)
    #expect(requestID.contains(snapshot.sessionID.uuidString.lowercased()))
    #expect(FocusNotificationRules.title(for: token) == "25분 집중을 완료했어요")
    #expect(!FocusNotificationRules.isActionable(token, now: start))
    #expect(FocusNotificationRules.isActionable(token, now: token.deadline))
    #expect(!FocusNotificationRules.isActionable(
        token,
        now: token.expiresAt.addingTimeInterval(1)
    ))
}

@Test
@MainActor
func focusNotificationActionEndsFocusBeforeStartingBreakAndRejectsReplay() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let task = Task(title: "알림에서 휴식", plannedAt: start, order: 100)
    context.insert(task)
    let focus = try FocusSessionService.beginFocus(
        taskID: task.id,
        focusSeconds: 5 * 60,
        breakSeconds: 2 * 60,
        now: start,
        in: context,
        directoryURL: directory
    )
    let token = try FocusNotificationRules.makeToken(
        snapshot: focus,
        requestIdentifier: try FocusNotificationRules.requestIdentifier(
            namespace: "planbase.focus.test",
            snapshot: focus
        )
    )
    try FocusNotificationActionTokenStore.write(token, directoryURL: directory)

    let result = try FocusNotificationActionService.perform(
        action: .startBreak,
        tokenID: token.tokenID,
        sessionID: token.sessionID,
        revision: token.revision,
        phase: .focus,
        deadline: token.deadline,
        now: token.deadline,
        in: context,
        directoryURL: directory
    )
    guard case .started(let rest) = result else {
        Issue.record("The notification action should start a break")
        return
    }
    #expect(rest.phase == .breakTime)
    #expect(rest.plannedBreakSeconds == 2 * 60)
    #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
    #expect(try FocusNotificationActionTokenStore.read(directoryURL: directory) == nil)
    #expect(throws: FocusNotificationRulesError.staleAction) {
        try FocusNotificationActionService.perform(
            action: .startBreak,
            tokenID: token.tokenID,
            sessionID: token.sessionID,
            revision: token.revision,
            phase: .focus,
            deadline: token.deadline,
            now: token.deadline,
            in: context,
            directoryURL: directory
        )
    }
}

@Test
@MainActor
func breakNotificationCanExtendBreakForFiveMinutes() throws {
    let directory = focusTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let rest = try FocusSessionService.beginBreak(
        taskID: UUID(),
        taskTitle: "쉬는 중",
        focusSeconds: 25 * 60,
        breakSeconds: 60,
        now: start,
        directoryURL: directory
    )
    let token = try FocusNotificationRules.makeToken(
        snapshot: rest,
        requestIdentifier: try FocusNotificationRules.requestIdentifier(
            namespace: "planbase.focus.test",
            snapshot: rest
        )
    )
    try FocusNotificationActionTokenStore.write(token, directoryURL: directory)

    let result = try FocusNotificationActionService.perform(
        action: .extendBreak,
        tokenID: token.tokenID,
        sessionID: token.sessionID,
        revision: token.revision,
        phase: .breakTime,
        deadline: token.deadline,
        now: token.deadline,
        in: context,
        directoryURL: directory
    )
    guard case .started(let extended) = result else {
        Issue.record("The notification action should extend the break")
        return
    }
    #expect(extended.phase == .breakTime)
    #expect(extended.plannedBreakSeconds == FocusNotificationRules.extensionBreakSeconds)
    #expect(extended.deadline == token.deadline.addingTimeInterval(
        TimeInterval(FocusNotificationRules.extensionBreakSeconds)
    ))
}

private func focusTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "PlanBaseFocusTests-\(UUID().uuidString)",
        isDirectory: true
    )
}
