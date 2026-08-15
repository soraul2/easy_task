import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class TaskProgressEventQuerySession {
    public private(set) var eventsByTaskID: [UUID: [TaskProgressEvent]] = [:]
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var requestedTaskIDs: Set<UUID> = []
    @ObservationIgnored private var pendingLoad: Swift.Task<Void, Never>?
    @ObservationIgnored private var dataObserver: TaskProgressNotificationObserver?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false

    public init(context: ModelContext) {
        self.context = context
        dataObserver = TaskProgressNotificationObserver(
            NotificationCenter.default.addObserver(
                forName: PersistenceCommandService.dataChangedNotification,
                object: context,
                queue: nil
            ) { [weak self] _ in
                Swift.Task { @MainActor [weak self] in
                    guard self?.isActive == true else { return }
                    self?.refresh(debounce: true)
                }
            }
        )
    }

    deinit {
        pendingLoad?.cancel()
    }

    public func apply(taskIDs: Set<UUID>) {
        isActive = true
        guard requestedTaskIDs != taskIDs || eventsByTaskID.isEmpty else { return }
        requestedTaskIDs = taskIDs
        refresh(debounce: false)
    }

    public func refresh(debounce: Bool = false) {
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
                let events = try TaskProgressEventService.events(
                    forTaskIDs: requestedTaskIDs,
                    in: context
                )
                try Swift.Task.checkCancellation()
                guard generation == requestGeneration else { return }
                eventsByTaskID = Dictionary(grouping: events, by: \.taskId)
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
        TaskProgressEventRules.projection(for: eventsByTaskID[taskID] ?? [])
    }

    public func cancel() {
        isActive = false
        generation += 1
        pendingLoad?.cancel()
        pendingLoad = nil
        isLoading = false
    }
}

private final class TaskProgressNotificationObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
