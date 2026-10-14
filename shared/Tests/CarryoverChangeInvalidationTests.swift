import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@MainActor
private func changedInboxTask(id: UUID = UUID(), dayKey: String = "2026-10-10", updatedAt: Date = .distantPast) throws -> Task {
    Task(id: id, title: "이월 변경", plannedAt: try #require(DayKey.date(from: dayKey)),
         order: 100, updatedAt: updatedAt)
}

@Test @MainActor
func carryoverKnownChangesReadOnlyChangedLogicalIDsAndSkipChildOnlyChanges() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let existing = try changedInboxTask()
    context.insert(existing)
    try context.save()
    let suite = "CarryoverChangeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var fullReads = 0
    var changedReads: [Set<UUID>] = []
    let session = CarryoverInboxSession(defaults: defaults, fetchChanged: { ids, dayKey in
        changedReads.append(Set(ids))
        return try CarryoverInboxRules.currentTasks(withIDs: ids, in: context, todayKey: dayKey)
    }) { dayKey in
        fullReads += 1
        return try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
    }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 1 && session.count == 1)
    let initialRevision = session.snapshotRevision
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, progressTaskIDs: [existing.id]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 1 && changedReads.isEmpty)
    #expect(session.snapshotRevision == initialRevision)

    let todayTask = try changedInboxTask(dayKey: "2026-10-12")
    try PersistenceCommandService.perform(in: context) { context.insert(todayTask) }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [todayTask.id]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 1 && changedReads == [Set([todayTask.id])])
    #expect(session.count == 1 && session.newCount == 0)
    #expect(session.snapshotRevision == initialRevision)

    try PersistenceCommandService.perform(in: context) {
        TaskRules.move(todayTask, to: try #require(DayKey.date(from: "2026-10-09")))
    }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [todayTask.id]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 1 && changedReads.count == 2)
    #expect(session.count == 2 && session.newCount == 1)
    #expect(session.tasks.map(\.instanceID) == (try CarryoverInboxRules.fetch(in: context, todayKey: "2026-10-12")).map(\.instanceID))
}

@Test @MainActor
func carryoverIncrementalDeletionChoosesRemainingDuplicateBeforeEligibility() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let older = try changedInboxTask()
    let logicalID = older.id
    let newer = try changedInboxTask(id: logicalID, updatedAt: Date())
    context.insert(older)
    context.insert(newer)
    try context.save()
    let suite = "CarryoverChangeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var fullReads = 0
    let session = CarryoverInboxSession(defaults: defaults, fetchChanged: { ids, dayKey in
        try CarryoverInboxRules.currentTasks(withIDs: ids, in: context, todayKey: dayKey)
    }) { dayKey in
        fullReads += 1
        return try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
    }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.tasks.first?.instanceID == newer.instanceID)
    try PersistenceCommandService.perform(in: context) { try TaskRules.delete(newer, from: context) }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [logicalID]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 1 && session.count == 1 && session.newCount == 0)
    #expect(session.tasks.first?.instanceID == older.instanceID)

    let moved = try changedInboxTask(id: logicalID, dayKey: "2026-10-12", updatedAt: Date().addingTimeInterval(1))
    try PersistenceCommandService.perform(in: context) { context.insert(moved) }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [logicalID]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 0 && fullReads == 1)
    #expect(try CarryoverInboxRules.fetch(in: context, todayKey: "2026-10-12").isEmpty)
}

@Test @MainActor
func carryoverIncrementalCompletionUndoAndHiddenChangeUnionMatchFullQuery() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let first = try changedInboxTask()
    let second = try changedInboxTask(dayKey: "2026-10-09")
    context.insert(first)
    context.insert(second)
    try context.save()
    let suite = "CarryoverChangeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var batches: [Set<UUID>] = []
    let session = CarryoverInboxSession(defaults: defaults, fetchChanged: { ids, dayKey in
        batches.append(Set(ids))
        return try CarryoverInboxRules.currentTasks(withIDs: ids, in: context, todayKey: dayKey)
    }) { try CarryoverInboxRules.fetch(in: context, todayKey: $0) }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    try PersistenceCommandService.perform(in: context) {
        TaskRules.applyStatus(.done, to: first)
        TaskRules.move(second, to: try #require(DayKey.date(from: "2026-10-12")))
    }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [first.id]))
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [second.id]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(batches == [Set([first.id, second.id])])
    #expect(session.count == 0)
    try PersistenceCommandService.perform(in: context) { TaskRules.applyStatus(.todo, to: first) }
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [first.id]))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 1 && session.newCount == 0)
    #expect(session.tasks.map(\.instanceID) == (try CarryoverInboxRules.fetch(in: context, todayKey: "2026-10-12")).map(\.instanceID))
}

@Test @MainActor
func carryoverUnknownChangesRolloverAndFailedIncrementalReadUseFullFallback() throws {
    enum Failure: Error { case unavailable }
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let task = try changedInboxTask()
    context.insert(task)
    try context.save()
    let suite = "CarryoverChangeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var fullReads = 0
    var fails = false
    let session = CarryoverInboxSession(defaults: defaults, fetchChanged: { ids, dayKey in
        if fails { throw Failure.unavailable }
        return try CarryoverInboxRules.currentTasks(withIDs: ids, in: context, todayKey: dayKey)
    }) { dayKey in
        fullReads += 1
        return try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
    }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    session.recordChanges(.unknown(in: .tasks))
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(fullReads == 2)
    session.refreshPendingChanges(todayKey: "2026-10-13")
    #expect(fullReads == 3)
    fails = true
    session.recordChanges(PersistenceChangeSummary(domains: .tasks, taskIDs: [task.id]))
    session.refreshPendingChanges(todayKey: "2026-10-13")
    #expect(session.errorMessage != nil && session.count == 1 && fullReads == 3)
    session.didDisplayInbox()
    fails = false
    session.refreshPendingChanges(todayKey: "2026-10-13")
    #expect(session.errorMessage == nil && fullReads == 4)
}

@Test @MainActor
func carryoverProductionSessionHandlesCommandIDsDirectSaveAndLegacyNotifications() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let suite = "CarryoverChangeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let session = CarryoverInboxSession(context: context, defaults: defaults)
    session.refreshPendingChanges(todayKey: "2026-10-12")
    let task = try changedInboxTask()
    try PersistenceCommandService.perform(in: context) { context.insert(task) }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 1 && session.newCount == 1)
    let revision = session.snapshotRevision
    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: Date()))
    }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.snapshotRevision == revision)
    task.status = TaskStatus.done.rawValue
    try context.save()
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 0)
    task.status = TaskStatus.todo.rawValue
    try context.save()
    NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification, object: context)
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 1)
}

enum CarryoverLogicalIDMutationCase: Sendable, Equatable {
    case eligible, completed, today, deletedDuplicate
}

@Test(arguments: [CarryoverLogicalIDMutationCase.eligible, .completed, .today, .deletedDuplicate])
@MainActor
func carryoverLogicalIDReassignmentInvalidatesOldKeyAndMatchesCanonicalQuery(
    scenario: CarryoverLogicalIDMutationCase
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let reference = try #require(DayKey.date(from: "2026-10-12"))
    let changed = try changedInboxTask(updatedAt: reference)
    let oldID = changed.id
    let newID = UUID()
    let kept = try changedInboxTask(dayKey: "2026-10-09", updatedAt: reference)
    let older = try changedInboxTask(id: oldID, updatedAt: reference.addingTimeInterval(-60))
    context.insert(changed)
    context.insert(kept)
    if scenario == .deletedDuplicate { context.insert(older) }
    try context.save()
    let physicalIdentifier = changed.persistentModelID
    let suite = "CarryoverIDMutationTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var fullReads = 0
    var changedReads: [Set<UUID>] = []
    let session = CarryoverInboxSession(defaults: defaults, fetchChanged: { ids, dayKey in
        changedReads.append(Set(ids))
        return try CarryoverInboxRules.currentTasks(withIDs: ids, in: context, todayKey: dayKey)
    }) { dayKey in
        fullReads += 1
        return try CarryoverInboxRules.fetch(in: context, todayKey: dayKey)
    }
    session.refreshPendingChanges(todayKey: "2026-10-12")
    #expect(session.count == 2)
    let commands = CarryoverCommandChanges(context: context)
    try PersistenceCommandService.perform(in: context) {
        changed.id = newID
        switch scenario {
        case .eligible: break
        case .completed: TaskRules.applyStatus(.done, to: changed, now: reference)
        case .today: TaskRules.move(changed, to: reference, now: reference)
        case .deletedDuplicate: try TaskRules.delete(changed, from: context)
        }
    }
    #expect(commands.values.count == 1)
    let summary = try #require(commands.values.last)
    #expect(summary.taskIDs == Set([newID]))
    #expect(summary.taskIdentifiers == Set([physicalIdentifier]))
    session.recordChanges(summary)
    session.refreshPendingChanges(todayKey: "2026-10-12")
    let canonical = try CarryoverInboxRules.fetch(in: context, todayKey: "2026-10-12")
    #expect(fullReads == 1)
    #expect(changedReads == [Set([oldID, newID])])
    #expect(session.tasks.map(\.instanceID) == canonical.map(\.instanceID))
    #expect(session.tasks.map(\.id) == canonical.map(\.id))
    #expect(Set(session.tasks.map(\.id)).count == session.count)
    #expect(session.tasks.contains { $0.id == kept.id })
    switch scenario {
    case .eligible:
        #expect(session.count == 2 && session.newCount == 1)
        #expect(!session.tasks.contains { $0.id == oldID })
        #expect(session.tasks.contains { $0.id == newID })
    case .completed, .today:
        #expect(session.count == 1 && session.newCount == 0)
        #expect(!session.tasks.contains { $0.id == oldID || $0.id == newID })
    case .deletedDuplicate:
        #expect(session.count == 2 && session.newCount == 0)
        #expect(session.tasks.contains { $0.instanceID == older.instanceID })
        #expect(!session.tasks.contains { $0.id == newID })
    }
}

private final class CarryoverCommandChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var summaries: [PersistenceChangeSummary] = []
    private var token: (any NSObjectProtocol)?
    var values: [PersistenceChangeSummary] { lock.withLock { summaries } }

    init(context: ModelContext) {
        token = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { [weak self] notification in
            let summary = PersistenceCommandService.changes(in: notification)
            self?.lock.withLock { self?.summaries.append(summary) }
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
