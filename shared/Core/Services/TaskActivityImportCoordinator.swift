import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class TaskActivityImportCoordinator {
    public static let productionDebounce: Duration = .seconds(2)

    public private(set) var isPending = false
    public private(set) var isRunning = false
    public private(set) var lastReport: TaskActivityBackfillReport?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let onFailure: @MainActor (any Error) -> Void
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingTask: Swift.Task<Void, Never>?

    public init(
        context: ModelContext,
        clock: any Clock<Duration> = ContinuousClock(),
        debounce: Duration = productionDebounce,
        onFailure: @escaping @MainActor (any Error) -> Void = { _ in }
    ) {
        self.context = context
        self.clock = clock
        self.debounce = debounce
        self.onFailure = onFailure
    }

    deinit {
        pendingTask?.cancel()
    }

    public func schedule(after summary: CloudKitSyncEventSummary) {
        guard CloudKitSyncService.shouldScheduleActivityReconciliation(
            after: summary
        ) else { return }
        generation += 1
        let requestGeneration = generation
        pendingTask?.cancel()
        isPending = true
        errorMessage = nil

        pendingTask = Swift.Task { [weak self, clock, debounce] in
            do {
                try await clock.sleep(for: debounce)
                guard !Swift.Task.isCancelled else { return }
                self?.runIfCurrent(requestGeneration)
            } catch is CancellationError {
                // A newer successful import replaced this request.
            } catch {
                guard !Swift.Task.isCancelled else { return }
                self?.recordFailure(error, generation: requestGeneration)
            }
        }
    }

    public func cancel() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        isPending = false
    }
}

private extension TaskActivityImportCoordinator {
    func runIfCurrent(_ requestGeneration: Int) {
        guard generation == requestGeneration else { return }
        pendingTask = nil
        isPending = false
        isRunning = true
        defer { isRunning = false }

        do {
            let report = try PersistenceCommandService.perform(in: context) {
                let backfill = try TaskActivityBackfillService.backfillLegacyCompletions(
                    in: context
                )
                _ = try TaskActivityIntegrityService.reconcile(in: context)
                return backfill
            }
            guard generation == requestGeneration else { return }
            lastReport = report
            errorMessage = nil
        } catch {
            recordFailure(error, generation: requestGeneration)
        }
    }

    func recordFailure(_ error: any Error, generation requestGeneration: Int) {
        guard generation == requestGeneration else { return }
        pendingTask = nil
        isPending = false
        isRunning = false
        errorMessage = "활동 기록을 정리하지 못했습니다."
        onFailure(error)
    }
}
