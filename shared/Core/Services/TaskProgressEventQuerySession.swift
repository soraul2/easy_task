import Foundation
import Observation
import SwiftData

@MainActor
@Observable
@available(watchOS 11, *)
public final class TaskProgressEventQuerySession {
    public private(set) var eventsByTaskID: [UUID: [TaskProgressEvent]] = [:]
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    private var projectionsByTaskID: [UUID: TaskProgressProjection] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let loadEvents: @MainActor (Set<UUID>) throws -> [TaskProgressEvent]
    @ObservationIgnored private var requestedTaskIDs: Set<UUID> = []
    @ObservationIgnored private var loadedTaskIDs: Set<UUID> = []
    @ObservationIgnored private var pendingTaskIDs: Set<UUID> = []
    @ObservationIgnored private var requiresFullReload = false
    @ObservationIgnored private var pendingLoad: Swift.Task<Void, Never>?
    @ObservationIgnored private var observers: [TaskProgressNotificationObserver] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false

    public init(context: ModelContext) {
        self.context = context
        loadEvents = { try TaskProgressEventService.events(forTaskIDs: $0, in: context) }
        installObservers()
    }

    init(context: ModelContext, loadEvents: @escaping @MainActor (Set<UUID>) throws -> [TaskProgressEvent]) {
        self.context = context
        self.loadEvents = loadEvents
        installObservers()
    }

    private func installObservers() {
        observe(PersistenceCommandService.dataChangedNotification, object: context) { [weak self] notification in
            self?.recordChanges(PersistenceCommandService.changes(in: notification))
        }
        observe(ModelContext.didSave, object: context) { [weak self] notification in
            guard let self, !PersistenceCommandService.isPerformingCommand(in: self.context),
                  PersistenceViewRevision.affects(.tasks, inSaveNotification: notification) else { return }
            self.refresh(debounce: true)
        }
        observe(CloudKitSyncService.eventChangedNotification) { [weak self] notification in
            guard let event = CloudKitSyncService.summary(from: notification),
                  event.kind == .import, event.isCompleted, event.succeeded else { return }
            self?.refresh(debounce: true)
        }
    }

    deinit {
        pendingLoad?.cancel()
    }

    public func apply(taskIDs: Set<UUID>) {
        let wasActive = isActive
        isActive = true
        // Events can be imported or edited while the board is hidden, without
        // changing task IDs. A tab's no-op archive notification is not a refresh contract.
        let removed = requestedTaskIDs.subtracting(taskIDs)
        requestedTaskIDs = taskIDs
        for id in removed {
            eventsByTaskID.removeValue(forKey: id)
            projectionsByTaskID.removeValue(forKey: id)
        }
        loadedTaskIDs.subtract(removed)
        pendingTaskIDs.subtract(removed)
        if !removed.isEmpty {
            // A pending request must not reintroduce IDs that left the board.
            generation += 1
            pendingLoad?.cancel()
            pendingLoad = nil
            isLoading = false
        }
        if !wasActive { requiresFullReload = true }
        pendingTaskIDs.formUnion(taskIDs.subtracting(loadedTaskIDs))
        scheduleLoad(debounce: false)
    }

    public func refresh(debounce: Bool = false) {
        guard isActive else { return }
        requiresFullReload = true
        scheduleLoad(debounce: debounce)
    }

    private func recordChanges(_ changes: PersistenceChangeSummary) {
        guard isActive, changes.domains.contains(.tasks) else { return }
        guard let progressTaskIDs = changes.progressTaskIDs else {
            refresh(debounce: true)
            return
        }
        let affected = progressTaskIDs.intersection(requestedTaskIDs)
        guard !affected.isEmpty else { return }
        pendingTaskIDs.formUnion(affected)
        scheduleLoad(debounce: true)
    }

    private func scheduleLoad(debounce: Bool) {
        let reloadAll = requiresFullReload
        let taskIDs = reloadAll ? requestedTaskIDs : pendingTaskIDs.intersection(requestedTaskIDs)
        guard reloadAll || !taskIDs.isEmpty else { return }
        generation += 1
        let requestGeneration = generation
        pendingLoad?.cancel()
        isLoading = true
        errorMessage = nil

        pendingLoad = Swift.Task { [weak self] in
            guard let self else { return }
            do {
                if debounce {
                    try await Swift.Task.sleep(for: .milliseconds(80))
                } else {
                    await Swift.Task.yield()
                }
                try Swift.Task.checkCancellation()
                let events = try loadEvents(taskIDs)
                try Swift.Task.checkCancellation()
                guard generation == requestGeneration else { return }
                let grouped = Dictionary(grouping: events, by: \.taskId)
                if reloadAll {
                    eventsByTaskID = grouped
                    projectionsByTaskID = grouped.mapValues { TaskProgressEventRules.projection(for: $0) }
                } else {
                    // Clear by cached keys before merging: deleted event models
                    // must never be read to decide which cached rows to remove.
                    for id in taskIDs {
                        eventsByTaskID.removeValue(forKey: id)
                        projectionsByTaskID.removeValue(forKey: id)
                    }
                    for (id, values) in grouped {
                        eventsByTaskID[id] = values
                        projectionsByTaskID[id] = TaskProgressEventRules.projection(for: values)
                    }
                }
                // Remember successful empty results as well as tasks with events.
                loadedTaskIDs.formUnion(taskIDs)
                pendingTaskIDs.subtract(taskIDs)
                requiresFullReload = false
                isLoading = false
                pendingLoad = nil
            } catch is CancellationError {
                // A newer task set or persistence notification owns the visible result.
            } catch {
                guard !Swift.Task.isCancelled, generation == requestGeneration else { return }
                errorMessage = "진행 시간을 불러오지 못했습니다."
                isLoading = false
                pendingLoad = nil
            }
        }
    }

    public func projection(for taskID: UUID) -> TaskProgressProjection {
        // Completed value projections remain safe while saved event deletions
        // are waiting for the next asynchronous refresh.
        projectionsByTaskID[taskID] ?? TaskProgressProjection()
    }

    public func cancel() {
        isActive = false
        generation += 1
        pendingLoad?.cancel()
        pendingLoad = nil
        isLoading = false
        requiresFullReload = true
    }

    private func observe(_ name: Notification.Name, object: AnyObject? = nil,
                         receive: @escaping @MainActor (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { notification in
            nonisolated(unsafe) let mainNotification = notification
            MainActor.assumeIsolated { receive(mainNotification) }
        }
        observers.append(TaskProgressNotificationObserver(token))
    }
}

@available(watchOS 11, *)
private final class TaskProgressNotificationObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
