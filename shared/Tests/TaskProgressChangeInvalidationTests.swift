import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func progressChangesFetchOnlyStartedStoppedAndDeletedTaskIDs() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let first = Task(title: "진행", plannedAt: Date(), order: 100)
    let second = Task(title: "유지", plannedAt: Date(), order: 200)
    context.insert(first)
    context.insert(second)
    try context.save()
    let firstID = first.id
    let secondID = second.id
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: [firstID, secondID])
    try await progressWaitForIdle(session)
    #expect(probe.calls == [Set([firstID, secondID])])
    let start = Date(timeIntervalSince1970: 1_788_400_000)

    try PersistenceCommandService.perform(in: context) {
        _ = try TaskLifecycleService.applyStatus(.doing, to: first, in: context, now: start)
    }
    try await progressWaitForIdle(session)
    #expect(probe.calls.last == Set([firstID]))
    #expect(probe.calls.count == 2)
    #expect(session.projection(for: firstID).currentStartedAt == start)
    try PersistenceCommandService.perform(in: context) {
        _ = try TaskLifecycleService.applyStatus(.todo, to: first, in: context,
            now: start.addingTimeInterval(600))
    }
    try await progressWaitForIdle(session)
    #expect(probe.calls.last == Set([firstID]))
    #expect(probe.calls.count == 3)
    #expect(session.projection(for: firstID).recordedDuration == 600)

    try PersistenceCommandService.perform(in: context) { try TaskRules.delete(first, from: context) }
    // A saved deletion can detach the cached models before the debounced load.
    // The last completed value projection must remain readable in that interval.
    #expect(session.projection(for: firstID).recordedDuration == 600)
    try await progressWaitForIdle(session)
    #expect(probe.calls.last == Set([firstID]))
    #expect(probe.calls.count == 4)
    #expect(session.projection(for: firstID) == TaskProgressProjection())
    #expect(session.projection(for: secondID) == TaskProgressProjection())
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
}

@Test @MainActor
func progressChangesSkipTaskTitlesChecklistAndNonvisibleEvents() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let task = Task(title: "표시", plannedAt: Date(), order: 100)
    context.insert(task)
    try context.save()
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: [task.id])
    try await progressWaitForIdle(session)

    try PersistenceCommandService.perform(in: context) { task.title = "제목 편집" }
    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskChecklistItem(taskId: task.id, title: "체크리스트", order: 100))
    }
    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskProgressEvent(taskId: UUID(), kind: .started, occurredAt: Date()))
    }
    try await Swift.Task.sleep(for: .milliseconds(120))
    #expect(probe.calls == [Set([task.id])])
    #expect(!session.isLoading)
    #expect(session.projection(for: task.id) == TaskProgressProjection())
}

@Test @MainActor
func progressChangesRememberEmptyResultsAndFetchOnlyAddedTaskIDs() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let firstID = UUID()
    let secondID = UUID()
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    context.insert(TaskProgressEvent(taskId: secondID, kind: .started, occurredAt: start))
    try context.save()
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: [firstID])
    try await progressWaitForIdle(session)
    session.apply(taskIDs: [firstID])
    await Swift.Task.yield()
    #expect(probe.calls == [Set([firstID])])
    #expect(!session.isLoading)
    session.apply(taskIDs: [firstID, secondID])
    try await progressWaitForIdle(session)
    #expect(probe.calls == [Set([firstID]), Set([secondID])])
    #expect(session.projection(for: secondID).currentStartedAt == start)
    session.apply(taskIDs: [firstID])
    await Swift.Task.yield()
    #expect(probe.calls.count == 2)
    #expect(session.eventsByTaskID[secondID] == nil)
    #expect(session.projection(for: secondID) == TaskProgressProjection())
    session.apply(taskIDs: [firstID, secondID])
    try await progressWaitForIdle(session)
    #expect(probe.calls == [Set([firstID]), Set([secondID]), Set([secondID])])
    #expect(session.projection(for: secondID).currentStartedAt == start)
}

@Test @MainActor
func progressChangesCancelRemovedRequestsAndReloadAfterHiddenEdits() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let firstID = UUID()
    let secondID = UUID()
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    context.insert(TaskProgressEvent(taskId: firstID, kind: .started, occurredAt: start))
    context.insert(TaskProgressEvent(taskId: secondID, kind: .started, occurredAt: start))
    try context.save()
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: [firstID])
    session.apply(taskIDs: [secondID])
    try await progressWaitForIdle(session)
    #expect(probe.calls == [Set([secondID])])
    #expect(session.eventsByTaskID[firstID] == nil)
    #expect(session.projection(for: firstID) == TaskProgressProjection())

    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskProgressEvent(taskId: secondID, kind: .stopped,
            occurredAt: start.addingTimeInterval(300)))
    }
    session.cancel()
    try await Swift.Task.sleep(for: .milliseconds(120))
    #expect(probe.calls.count == 1)
    // Hidden changes do not require a new set of displayed IDs or a direct-save callback.
    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskProgressEvent(taskId: secondID, kind: .started,
            occurredAt: start.addingTimeInterval(400)))
    }
    session.apply(taskIDs: [secondID])
    try await progressWaitForIdle(session)
    #expect(probe.calls == [Set([secondID]), Set([secondID])])
    #expect(session.projection(for: secondID).recordedDuration == 300)
    #expect(session.projection(for: secondID).currentStartedAt == start.addingTimeInterval(400))
}

@Test @MainActor
func progressChangesKeepDirectSaveLegacyAndSuccessfulImportFallbacks() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let first = Task(title: "첫째", plannedAt: Date(), order: 100)
    let second = Task(title: "둘째", plannedAt: Date(), order: 200)
    context.insert(first)
    context.insert(second)
    try context.save()
    let ids: Set<UUID> = [first.id, second.id]
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: ids)
    try await progressWaitForIdle(session)
    first.title = "직접 저장 편집"
    try context.save()
    try await progressWaitForIdle(session)
    #expect(probe.calls == [ids, ids])
    NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification, object: context)
    try await progressWaitForIdle(session)
    #expect(probe.calls == [ids, ids, ids])
    // Exercise the public successful-import reconciliation boundary on a local
    // memory store; no CloudKit account or actual import is accessed by this test.
    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true), context: context)
    try await progressWaitForIdle(session)
    #expect(probe.calls == [ids, ids, ids, ids])
    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: false), context: context)
    try await Swift.Task.sleep(for: .milliseconds(120))
    #expect(probe.calls.count == 4)
}

@Test @MainActor
func progressChangesConservativelyRefetchBothParentsWhenEventMoves() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let firstID = UUID()
    let secondID = UUID()
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    let event = TaskProgressEvent(taskId: firstID, kind: .started, occurredAt: start)
    context.insert(event)
    try context.save()
    let ids: Set<UUID> = [firstID, secondID]
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: ids)
    try await progressWaitForIdle(session)
    try PersistenceCommandService.perform(in: context) { event.taskId = secondID }
    try await progressWaitForIdle(session)
    #expect(probe.calls == [ids, ids])
    #expect(session.projection(for: firstID) == TaskProgressProjection())
    #expect(session.projection(for: secondID).currentStartedAt == start)
}

@Test @MainActor
func progressChangesRetainSavedProjectionAcrossCommandRollbackAndQueryFailure() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let task = Task(title: "실패 검증", plannedAt: Date(), order: 100)
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    context.insert(task)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
    try context.save()
    let id = task.id
    let probe = ProgressQueryProbe(context: context)
    let session = TaskProgressEventQuerySession(context: context, loadEvents: probe.load)
    session.apply(taskIDs: [id])
    try await progressWaitForIdle(session)
    do {
        try PersistenceCommandService.perform(in: context) {
            _ = try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: start)
            throw CocoaError(.fileWriteUnknown)
        }
        Issue.record("실패한 명령은 오류를 전달해야 합니다")
    } catch {}
    try await Swift.Task.sleep(for: .milliseconds(120))
    #expect(probe.calls.count == 1)
    #expect(session.projection(for: id).currentStartedAt == start)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 1)

    probe.shouldFail = true
    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskProgressEvent(taskId: id, kind: .stopped,
            occurredAt: start.addingTimeInterval(600)))
    }
    try await progressWaitForIdle(session)
    #expect(session.errorMessage != nil)
    #expect(session.projection(for: id).currentStartedAt == start)
    #expect(probe.calls == [Set([id]), Set([id])])
    probe.shouldFail = false
    session.apply(taskIDs: [id])
    try await progressWaitForIdle(session)
    #expect(session.errorMessage == nil)
    #expect(probe.calls == [Set([id]), Set([id]), Set([id])])
    #expect(session.projection(for: id).recordedDuration == 600)
    #expect(session.projection(for: id).currentStartedAt == nil)
}

@MainActor
private final class ProgressQueryProbe {
    let context: ModelContext
    var calls: [Set<UUID>] = []
    var shouldFail = false

    init(context: ModelContext) { self.context = context }

    func load(_ ids: Set<UUID>) throws -> [TaskProgressEvent] {
        calls.append(ids)
        if shouldFail { throw CocoaError(.fileReadUnknown) }
        return try TaskProgressEventService.events(forTaskIDs: ids, in: context)
    }
}

@MainActor
private func progressWaitForIdle(_ session: TaskProgressEventQuerySession) async throws {
    for _ in 0..<400 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(5))
    }
    #expect(!session.isLoading)
}
