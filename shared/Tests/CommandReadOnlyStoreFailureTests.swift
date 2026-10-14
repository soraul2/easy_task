import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// These tests use a real SQLite-backed SwiftData configuration that disallows
// saves. No production store, file permissions, CloudKit or save-error injection
// is involved. The serial SDK run observed NSCocoaErrorDomain/513; the
// assertions retain that actual domain/code, with the full graph printed below.

@Test @MainActor
func commandReadOnlyFinalSaveFailureRollsBackMutationWithoutNotification() throws {
    try withCommandReadOnlyStore { container, id in
        let context = container.mainContext
        let original = try commandReadOnlySnapshot(in: context)
        let task = try #require(context.fetch(FetchDescriptor<Task>()).first { $0.id == id })
        let notifications = CommandReadOnlyCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var mutationCalls = 0

        let failure = try captureCommandReadOnlyFailure {
            try PersistenceCommandService.perform(in: context) {
                mutationCalls += 1
                task.title = "Uncommitted command edit"
                context.insert(Task(title: "Uncommitted command insertion", plannedAt: task.plannedAt, order: 200))
            }
        }
        let graph = commandReadOnlyErrorGraph(failure)
        recordCommandReadOnlyErrorGraph(graph, phase: "command-final-save")
        #expect(commandReadOnlyEngineFamily(graph), "Expected actual read-only store engine failure; inspect READONLY_SAVE_ERROR_GRAPH.")
        #expect(mutationCalls == 1, "A clean pre-save must reach the mutation to exercise final-save rollback.")
        let after = try commandReadOnlySnapshot(in: context)
        let persisted = try commandReadOnlySnapshot(in: ModelContext(container))
        #expect(after == original)
        #expect(persisted == original)
        #expect(!context.hasChanges)
        #expect(notifications.value == 0)
        #expect(!PersistenceCommandService.isPerformingCommand(in: context))
        withExtendedLifetime(container) {}
    }
}

@Test @MainActor
func commandReadOnlyPendingPreSaveFailureKeepsDraftAndDoesNotRunMutation() throws {
    try withCommandReadOnlyStore { container, id in
        let context = container.mainContext
        let original = try commandReadOnlySnapshot(in: context)
        let task = try #require(context.fetch(FetchDescriptor<Task>()).first { $0.id == id })
        task.title = "Pending draft retained after pre-save failure"
        #expect(context.hasChanges)
        let draft = try commandReadOnlySnapshot(in: context)
        let notifications = CommandReadOnlyCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var mutationCalls = 0

        let failure = try captureCommandReadOnlyFailure {
            try PersistenceCommandService.perform(in: context) {
                mutationCalls += 1
                task.title = "Mutation must not run"
                context.insert(Task(title: "Mutation must not insert", plannedAt: task.plannedAt, order: 200))
            }
        }
        let graph = commandReadOnlyErrorGraph(failure)
        recordCommandReadOnlyErrorGraph(graph, phase: "command-pending-pre-save")
        #expect(commandReadOnlyEngineFamily(graph), "Expected actual read-only store engine failure; inspect READONLY_SAVE_ERROR_GRAPH.")
        #expect(mutationCalls == 0)
        #expect(task.title == "Pending draft retained after pre-save failure")
        #expect(context.hasChanges, "Pre-save failure must preserve the user's dirty draft, without rollback.")
        let after = try commandReadOnlySnapshot(in: context)
        let persisted = try commandReadOnlySnapshot(in: ModelContext(container))
        #expect(after == draft)
        #expect(persisted == original)
        #expect(notifications.value == 0)
        #expect(!PersistenceCommandService.isPerformingCommand(in: context))
        withExtendedLifetime(container) {}
    }
}

@Test @MainActor
func commandReadOnlyCleanNoopMatchesActualEmptySaveBehaviorWithoutNotification() throws {
    try withCommandReadOnlyStore { container, _ in
        // SDK behavior for a clean save is observed rather than assuming that
        // allowsSave:false necessarily rejects an empty save request.
        let directContext = ModelContext(container)
        directContext.autosaveEnabled = false
        var directFailure: NSError?
        do { try directContext.save() } catch { directFailure = error as NSError }
        let context = container.mainContext
        let original = try commandReadOnlySnapshot(in: context)
        let notifications = CommandReadOnlyCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var mutationCalls = 0
        var commandFailure: NSError?
        do {
            try PersistenceCommandService.perform(in: context) { mutationCalls += 1 }
        } catch { commandFailure = error as NSError }

        #expect((commandFailure == nil) == (directFailure == nil),
                "A clean no-op command should follow this SDK's actual empty-save behavior.")
        if let directFailure {
            recordCommandReadOnlyErrorGraph(commandReadOnlyErrorGraph(directFailure), phase: "direct-empty-save")
        }
        if let commandFailure {
            recordCommandReadOnlyErrorGraph(commandReadOnlyErrorGraph(commandFailure), phase: "command-clean-noop")
        }
        if let directFailure, let commandFailure {
            let directGraph = commandReadOnlyErrorGraph(directFailure)
            let commandGraph = commandReadOnlyErrorGraph(commandFailure)
            #expect(commandReadOnlyEngineFamily(directGraph))
            #expect(commandReadOnlyEngineFamily(commandGraph))
            #expect(directGraph.first == commandGraph.first, "Preserve the SDK's top-level error domain and code.")
            #expect(mutationCalls == 0)
        } else if directFailure == nil && commandFailure == nil {
            #expect(mutationCalls == 1)
            print("READONLY_EMPTY_SAVE_RESULT {\"command\":\"success\",\"direct\":\"success\",\"dirty\":false}")
        }
        let after = try commandReadOnlySnapshot(in: context)
        #expect(after == original)
        #expect(!context.hasChanges)
        #expect(notifications.value == 0)
        #expect(!PersistenceCommandService.isPerformingCommand(in: context))
        withExtendedLifetime(container) {}
    }
}

@Test @MainActor
func bootstrapReadOnlyEngineSaveFailureRollsBackRepairInWorkerContext() async throws {
    try await withCommandReadOnlyStoreAsync(repairNeeded: true) { container, _ in
        // Use the app's detached create-and-invoke facade, including both
        // snapshots of the same worker context. Only value snapshots leave it.
        let (before, after, graph, beforeSaveCalls) = try await PlanBaseBootstrapService.withWorker(
            container: container
        ) { worker in
            let before = try await worker.commandReadOnlyTestSnapshot()
            #expect(before.tasks.first?.plannedDayKey == "broken-readonly-day-key")
            #expect(!before.hasChanges)
            let beforeSaveCalls = CommandReadOnlyCounter()
            var failure: NSError?
            do {
                _ = try await worker.reconcile(beforeSave: {
                    #expect(!Thread.isMainThread)
                    beforeSaveCalls.increment()
                })
            } catch { failure = error as NSError }
            let actualFailure = try #require(failure, "The repair must reach an actual engine save failure, without injected errors.")
            let graph = commandReadOnlyErrorGraph(actualFailure)
            let after = try await worker.commandReadOnlyTestSnapshot()
            return (before, after, graph, beforeSaveCalls.value)
        }
        recordCommandReadOnlyErrorGraph(graph, phase: "bootstrap-worker-final-save")
        #expect(commandReadOnlyEngineFamily(graph), "Expected actual read-only store engine failure; inspect READONLY_SAVE_ERROR_GRAPH.")
        #expect(beforeSaveCalls == 1, "The worker must finish repair before attempting the failing save.")
        let persisted = try commandReadOnlySnapshot(in: ModelContext(container))
        #expect(after == before, "Verify the worker's own context rolled back, rather than only inspecting another reader.")
        #expect(persisted == before)
        #expect(!after.hasChanges)
        withExtendedLifetime(container) {}
    }
}

private struct CommandReadOnlyTaskValue: Sendable, Equatable {
    let id: UUID
    let instanceID: UUID
    let title: String
    let plannedAt: Date
    let plannedDayKey: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?
}

private struct CommandReadOnlySnapshot: Sendable, Equatable {
    let tasks: [CommandReadOnlyTaskValue]
    let checklistCount: Int
    let progressCount: Int
    let activityCount: Int
    let hasChanges: Bool
}

// Synchronous projection on the context's owning executor. Only this value
// snapshot leaves the background worker; no model/context crosses actors.
private func commandReadOnlySnapshot(in context: ModelContext) throws -> CommandReadOnlySnapshot {
    let tasks = try context.fetch(FetchDescriptor<Task>()).map {
        CommandReadOnlyTaskValue(id: $0.id, instanceID: $0.instanceID, title: $0.title,
                                plannedAt: $0.plannedAt, plannedDayKey: $0.plannedDayKey, status: $0.status,
                                createdAt: $0.createdAt, updatedAt: $0.updatedAt, supersededAt: $0.supersededAt)
    }.sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    return try CommandReadOnlySnapshot(
        tasks: tasks, checklistCount: context.fetchCount(FetchDescriptor<TaskChecklistItem>()),
        progressCount: context.fetchCount(FetchDescriptor<TaskProgressEvent>()),
        activityCount: context.fetchCount(FetchDescriptor<TaskCompletionActivity>()), hasChanges: context.hasChanges)
}

extension PlanBaseBootstrapWorker {
    fileprivate func commandReadOnlyTestSnapshot() throws -> CommandReadOnlySnapshot {
        try commandReadOnlySnapshot(in: modelContext)
    }
}

private final class CommandReadOnlyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct CommandReadOnlyErrorCode: Sendable, Equatable {
    let domain: String
    let code: Int
}

private func commandReadOnlyErrorGraph(_ error: NSError) -> [CommandReadOnlyErrorCode] {
    var visited = Set<ObjectIdentifier>()
    var graph: [CommandReadOnlyErrorCode] = []
    func visit(_ value: Any, depth: Int) {
        guard depth < 12 else { return }
        if let nested = value as? NSError {
            guard visited.insert(ObjectIdentifier(nested)).inserted else { return }
            graph.append(CommandReadOnlyErrorCode(domain: nested.domain, code: nested.code))
            for value in nested.userInfo.values { visit(value, depth: depth + 1) }
        } else if let errors = value as? [Any] {
            for value in errors { visit(value, depth: depth + 1) }
        } else if let values = value as? [String: Any] {
            for value in values.values { visit(value, depth: depth + 1) }
        }
    }
    visit(error, depth: 0)
    return graph
}

private func commandReadOnlyEngineFamily(_ graph: [CommandReadOnlyErrorCode]) -> Bool {
    // The actual allowsSave:false engine failure on the tested SDK is
    // NSFileWriteNoPermissionError (513), rather than a hypothesized Core Data
    // 134020 or underlying SQLite 8. Require the observed domain/code exactly.
    graph.contains {
        $0.domain == NSCocoaErrorDomain && $0.code == CocoaError.fileWriteNoPermission.rawValue
    }
}

private func recordCommandReadOnlyErrorGraph(_ graph: [CommandReadOnlyErrorCode], phase: String) {
    let payload: [String: Any] = [
        "phase": phase, "storeMode": "owned-temporary-local-allowsSave-false",
        "injectedSaveError": false,
        "errors": graph.map { ["domain": $0.domain, "code": $0.code] as [String: Any] },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
        print("READONLY_SAVE_ERROR_GRAPH \(String(decoding: data, as: UTF8.self))")
    }
}

private func captureCommandReadOnlyFailure(_ operation: () throws -> Void) throws -> NSError {
    var failure: NSError?
    do { try operation() } catch { failure = error as NSError }
    return try #require(failure, "The actual read-only engine save must fail; no injected failure is accepted.")
}

@MainActor
private func prepareCommandReadOnlyStore(repairNeeded: Bool) throws -> (directory: URL, store: URL, taskID: UUID) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseCommandReadOnlyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
        let store = directory.appendingPathComponent("readonly.store")
        let taskID = UUID()
        // The writer and every seeded model are released before read-only open.
        try autoreleasepool {
            let writer = try PlanBaseContainerFactory.makePersistent(storeURL: store, mode: .local)
            let context = writer.mainContext
            context.autosaveEnabled = false
            let day = try #require(DayKey.date(from: "2026-10-12"))
            let task = Task(id: taskID, title: "Persisted read-only original", plannedAt: day, order: 100)
            if repairNeeded { task.plannedDayKey = "broken-readonly-day-key" }
            context.insert(task)
            try context.save()
        }
        return (directory, store, taskID)
    } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
}

private func makeCommandReadOnlyContainer(at store: URL) throws -> ModelContainer {
    let schema = PlanBaseContainerFactory.schema
    let configuration = ModelConfiguration(
        PlanBaseCompatibility.modelConfigurationName, schema: schema, url: store,
        allowsSave: false, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [configuration])
}

@MainActor
private func withCommandReadOnlyStore(
    repairNeeded: Bool = false, _ body: (ModelContainer, UUID) throws -> Void
) throws {
    let fixture = try prepareCommandReadOnlyStore(repairNeeded: repairNeeded)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try autoreleasepool {
        let reader = try makeCommandReadOnlyContainer(at: fixture.store)
        reader.mainContext.autosaveEnabled = false
        try body(reader, fixture.taskID)
        withExtendedLifetime(reader) {}
    }
}

@MainActor
private func withCommandReadOnlyStoreAsync(
    repairNeeded: Bool, _ body: @MainActor (ModelContainer, UUID) async throws -> Void
) async throws {
    let fixture = try prepareCommandReadOnlyStore(repairNeeded: repairNeeded)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    // Keep the reader in a nested async scope so its worker/context lifetime ends
    // before removing the uniquely owned temporary directory.
    try await runCommandReadOnlyBody(at: fixture.store, taskID: fixture.taskID, body: body)
}

@MainActor
private func runCommandReadOnlyBody(
    at store: URL, taskID: UUID, body: @MainActor (ModelContainer, UUID) async throws -> Void
) async throws {
    let reader = try makeCommandReadOnlyContainer(at: store)
    reader.mainContext.autosaveEnabled = false
    try await body(reader, taskID)
    withExtendedLifetime(reader) {}
}
