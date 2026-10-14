import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private func companionTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("WatchCompanionTests-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func watchCompanionOutboxSurvivesRestartAndOldSnapshot() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let now = Date(), phoneID = UUID(), taskID = UUID()
    var state = WatchCompanionState()
    state.snapshot = WatchCompanionSnapshot(phoneID: phoneID, revision: 2, generatedAt: now,
        dayKey: DayKey.key(for: now), tasks: [])
    try state.enqueue(.addTask(id: taskID, title: "오프라인 작업", dayKey: DayKey.key(for: now)), now: now)
    try WatchCompanionStateStore.write(state, to: url)
    var restored = try WatchCompanionStateStore.read(from: url)
    #expect(restored.pending == state.pending)
    #expect(restored.projectedTasks.map(\.id) == [taskID])
    let old = WatchCompanionSnapshot(phoneID: phoneID, revision: 1, generatedAt: now.addingTimeInterval(-1), dayKey: DayKey.key(for: now), tasks: [])
    try restored.receive(WatchCompanionResponse(snapshot: old))
    #expect(restored.snapshot?.revision == 2)
    #expect(restored.pending.count == 1)
}

@Test func watchCompanionAcknowledgementDoesNotDuplicateOptimisticTask() throws {
    let now = Date(), phoneID = UUID(), id = UUID()
    var state = WatchCompanionState()
    let snapshot = WatchCompanionSnapshot(phoneID: phoneID, revision: 1, generatedAt: now,
        dayKey: DayKey.key(for: now), tasks: [])
    state.snapshot = snapshot
    try state.enqueue(.addTask(id: id, title: "한 번만", dayKey: snapshot.dayKey), now: now)
    let commandID = try #require(state.pending.first?.id)
    var next = snapshot
    next.revision = 2
    next.tasks = [WatchCompanionTask(id: id, title: "한 번만", status: "todo", updatedAt: now, plannedDayKey: snapshot.dayKey)]
    try state.receive(WatchCompanionResponse(snapshot: next))
    #expect(state.projectedTasks.count == 1)
    #expect(state.pending.count == 1)
    try state.receive(WatchCompanionResponse(snapshot: next, receipts: [WatchCompanionReceipt(commandID: commandID, accepted: true)]))
    #expect(state.pending.isEmpty)
    #expect(state.projectedTasks.count == 1)
}

@Test func watchCompanionTimerAndTerminalRecordAreSavedTogether() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(), id = UUID()
    var state = WatchCompanionState()
    state.snapshot = WatchCompanionSnapshot(phoneID: UUID(), revision: 1, generatedAt: now,
        dayKey: DayKey.key(for: now), tasks: [])
    state.activeFocus = FocusTimerRules.startFocus(taskID: id, taskTitle: "집중", focusSeconds: 300, now: now)
    #expect(try state.finishFocus(outcome: .completed, now: now.addingTimeInterval(320)))
    #expect(try !state.finishFocus(outcome: .completed, now: now.addingTimeInterval(330)))
    let url = directory.appendingPathComponent("state.json")
    try WatchCompanionStateStore.write(state, to: url)
    let restored = try WatchCompanionStateStore.read(from: url)
    #expect(restored.activeFocus == nil)
    #expect(restored.pending.count == 1)
    guard case let .recordFocus(record) = try #require(restored.pending.first?.action) else {
        Issue.record("Missing focus record"); return
    }
    #expect(record.focusedSeconds == 300)
    #expect(record.endedAt == now.addingTimeInterval(300))
}

@Test @MainActor func watchCompanionDuplicateCreationAndCompletionAreIdempotent() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let url = directory.appendingPathComponent("journal.json")
    let service = try WatchCompanionService(journalURL: url)
    let now = Date(), id = UUID()
    let initial = try service.snapshot(in: context, now: now)
    let add = WatchCompanionCommand(phoneID: initial.phoneID, createdAt: now,
        action: .addTask(id: id, title: "Watch 추가", dayKey: initial.dayKey))
    _ = try service.respond(to: WatchCompanionRequest(commands: [add, add]), in: context, now: now)
    #expect(try context.fetchCount(FetchDescriptor<EasyTaskCore.Task>()) == 1)
    let task = try #require(context.fetch(FetchDescriptor<EasyTaskCore.Task>()).first)
    let complete = WatchCompanionCommand(phoneID: initial.phoneID, createdAt: now.addingTimeInterval(1),
        action: .setStatus(taskID: id, expectedStatus: "todo", expectedUpdatedAt: task.updatedAt,
            status: "done", completionDayKey: initial.dayKey, confirmedReminderAt: nil))
    _ = try service.respond(to: WatchCompanionRequest(commands: [complete]), in: context, now: now.addingTimeInterval(1))
    let restarted = try WatchCompanionService(journalURL: url)
    _ = try restarted.respond(to: WatchCompanionRequest(commands: [add, complete]), in: context, now: now.addingTimeInterval(2))
    #expect(task.status == "done")
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<EasyTaskCore.Task>()) == 1)
}

@Test @MainActor func watchCompanionRejectsStaleStatusAndChangedReminder() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let service = try WatchCompanionService(journalURL: directory.appendingPathComponent("journal.json"))
    let now = Date()
    let task = EasyTaskCore.Task(title: "수정된 작업", plannedAt: now, order: 0, createdAt: now, updatedAt: now)
    context.insert(task); try context.save()
    let snapshot = try service.snapshot(in: context, now: now)
    task.title = "iPhone에서 수정"; task.updatedAt = now.addingTimeInterval(1); try context.save()
    let stale = WatchCompanionCommand(phoneID: snapshot.phoneID, createdAt: now.addingTimeInterval(2),
        action: .setStatus(taskID: task.id, expectedStatus: "todo", expectedUpdatedAt: now,
            status: "done", completionDayKey: snapshot.dayKey, confirmedReminderAt: nil))
    let result = try service.respond(to: WatchCompanionRequest(commands: [stale]), in: context, now: now.addingTimeInterval(2))
    #expect(result.receipts.first?.accepted == false)
    #expect(task.status == "todo")
    task.reminderAt = now.addingTimeInterval(3600); try context.save()
    let unconfirmed = WatchCompanionCommand(phoneID: snapshot.phoneID, createdAt: now.addingTimeInterval(3),
        action: .setStatus(taskID: task.id, expectedStatus: "todo", expectedUpdatedAt: task.updatedAt,
            status: "done", completionDayKey: snapshot.dayKey, confirmedReminderAt: nil))
    let rejected = try service.respond(to: WatchCompanionRequest(commands: [unconfirmed]), in: context, now: now.addingTimeInterval(3))
    #expect(rejected.receipts.first?.accepted == false)
    #expect(task.status == "todo")
}

@Test @MainActor func watchCompanionInterruptedCommandDoesNotRecreateDeletedTask() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("journal.json")
    let container = try PlanBaseContainerFactory.makeInMemory()
    let now = Date(), phoneID = UUID(), commandID = UUID()
    // Simulate interruption after marking a command prepared: its commit outcome is unknown.
    let json: [String: Any] = ["version": 1, "phoneID": phoneID.uuidString, "revision": 1,
                             "prepared": [commandID.uuidString], "receipts": []]
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    let service = try WatchCompanionService(journalURL: url)
    let command = WatchCompanionCommand(id: commandID, phoneID: phoneID, createdAt: now,
        action: .addTask(id: UUID(), title: "복구 확인", dayKey: DayKey.key(for: now)))
    let response = try service.respond(to: WatchCompanionRequest(commands: [command]), in: container.mainContext, now: now)
    #expect(response.receipts.first?.accepted == false)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<EasyTaskCore.Task>()) == 0)
}

@Test func watchCompanionRejectsFutureProtocolWithoutDroppingQueue() throws {
    let now = Date()
    var state = WatchCompanionState()
    state.snapshot = WatchCompanionSnapshot(phoneID: UUID(), revision: 1, generatedAt: now,
        dayKey: DayKey.key(for: now), tasks: [])
    try state.enqueue(.addTask(id: UUID(), title: "보존", dayKey: DayKey.key(for: now)))
    var response = WatchCompanionResponse(snapshot: try #require(state.snapshot))
    response.version = 999
    #expect(throws: WatchCompanionError.self) { try state.receive(response) }
    #expect(state.pending.count == 1)
}

@Test @MainActor func watchCompanionOrderedTransitionsPreserveCompletionDayAndFocusRecord() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let service = try WatchCompanionService(journalURL: directory.appendingPathComponent("journal.json"))
    let start = DayKey.startOfDay(for: Date()).addingTimeInterval(-600)
    var state = WatchCompanionState()
    state.snapshot = try service.snapshot(in: context, now: start)
    let id = UUID(), dayKey = DayKey.key(for: start)
    try state.enqueue(.addTask(id: id, title: "연결 전 작업", dayKey: dayKey), now: start)
    let todo = try #require(state.projectedTasks.first)
    try state.enqueue(.setStatus(taskID: id, expectedStatus: todo.status, expectedUpdatedAt: todo.updatedAt,
        status: "doing", completionDayKey: dayKey, confirmedReminderAt: nil), now: start.addingTimeInterval(1))
    state.activeFocus = FocusTimerRules.startFocus(taskID: id, taskTitle: todo.title, focusSeconds: 300, now: start.addingTimeInterval(1))
    try state.finishFocus(outcome: .completed, now: start.addingTimeInterval(301))
    let doing = try #require(state.projectedTasks.first)
    try state.enqueue(.setStatus(taskID: id, expectedStatus: doing.status, expectedUpdatedAt: doing.updatedAt,
        status: "done", completionDayKey: dayKey, confirmedReminderAt: nil), now: start.addingTimeInterval(302))
    let request = WatchCompanionRequest(commands: state.pending)
    let response = try service.respond(to: request, in: context, now: start.addingTimeInterval(1000))
    #expect(response.receipts.allSatisfy { $0.accepted })
    _ = try service.respond(to: request, in: context, now: start.addingTimeInterval(1100))
    let task = try #require(context.fetch(FetchDescriptor<EasyTaskCore.Task>()).first)
    #expect(task.status == "done")
    #expect(task.completedDayKey == dayKey)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 2)
    let focus = try #require(context.fetch(FetchDescriptor<FocusSession>()).first)
    #expect(focus.focusedDurationSeconds == 300)
    #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
}

@Test func watchCompanionRejectedChangesRemainAvailableForUserReview() throws {
    let now = Date()
    var state = WatchCompanionState()
    state.snapshot = WatchCompanionSnapshot(phoneID: UUID(), revision: 1, generatedAt: now,
        dayKey: DayKey.key(for: now), tasks: [])
    try state.enqueue(.addTask(id: UUID(), title: "제목 보존", dayKey: DayKey.key(for: now)))
    let command = try #require(state.pending.first)
    let response = WatchCompanionResponse(snapshot: try #require(state.snapshot), receipts: [
        WatchCompanionReceipt(commandID: command.id, accepted: false, message: "다시 확인")])
    try state.receive(response)
    #expect(state.pending.isEmpty)
    #expect(state.failed == [command])
    #expect(state.lastFailure == "다시 확인")
}

@Test @MainActor func watchCompanionCapsTransferredRowsWithoutUndercountingToday() throws {
    let directory = try companionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = Date()
    for index in 0..<110 {
        context.insert(EasyTaskCore.Task(title: String(repeating: "긴 제목 ", count: 100),
            plannedAt: now, order: Double(index)))
    }
    try context.save()
    let service = try WatchCompanionService(journalURL: directory.appendingPathComponent("journal.json"))
    let response = try service.respond(to: WatchCompanionRequest(), in: context, now: now)
    #expect(response.snapshot.tasks.count <= 100)
    #expect(response.snapshot.hasMoreTasks)
    #expect(response.snapshot.todoCount == 110)
    #expect(try WatchCompanionProtocol.encode(response).count <= WatchCompanionProtocol.maximumPayloadBytes)
}
