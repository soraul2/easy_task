import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class TaskHistoryStatisticsSession {
    public private(set) var statistics = TaskHistoryStatistics()
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var pendingCalculation: Swift.Task<Void, Never>?

    public init(context: ModelContext) {
        self.context = context
    }

    deinit {
        pendingCalculation?.cancel()
    }

    public func apply(
        _ filter: ArchiveFilter,
        referenceDate: Date = Date()
    ) {
        pendingCalculation?.cancel()
        isLoading = true
        errorMessage = nil

        pendingCalculation = Swift.Task { [weak self] in
            await Swift.Task.yield()
            guard !Swift.Task.isCancelled, let self else { return }
            do {
                let range = ArchiveQueryRules.dayKeyRange(
                    for: filter,
                    referenceDate: referenceDate
                )
                let lowerBound = range.lowerBound ?? "0001-01-01"
                let tasks = try BoundedQueryService.taskHistoryStatisticsCandidates(
                    from: lowerBound,
                    through: range.upperBound,
                    in: context,
                    isCancelled: { Swift.Task<Never, Never>.isCancelled }
                )
                guard !Swift.Task.isCancelled else { return }
                statistics = TaskHistoryStatisticsRules.statistics(
                    from: tasks,
                    lowerBound: lowerBound,
                    upperBound: range.upperBound
                )
                isLoading = false
            } catch is CancellationError {
                // A newer filter owns the visible calculation.
            } catch {
                guard !Swift.Task.isCancelled else { return }
                statistics = TaskHistoryStatistics()
                errorMessage = "기간 통계를 계산하지 못했습니다."
                isLoading = false
            }
        }
    }
}
