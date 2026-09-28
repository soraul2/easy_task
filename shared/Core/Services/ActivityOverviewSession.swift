import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class ActivityOverviewSession {
    public nonisolated static let backwardPageDayCount = 90

    public private(set) var overview = ActivityOverview()
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var changes: PersistenceViewRevision?
    @ObservationIgnored private var pendingCalculation: Swift.Task<Void, Never>?
    @ObservationIgnored private var midnightRefresh: Swift.Task<Void, Never>?
    @ObservationIgnored private var completedRequest: Request?
    @ObservationIgnored private var pendingRequest: Request?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var requestedWeekCount = TaskActivityRules.compactWeekCount
    @ObservationIgnored private var requestedCalendar = DayKey.calendar

    private struct Request: Equatable {
        let revision: Int
        let weekCount: Int
        let dayKey: String
        let calendar: Calendar
        let pending: ActivityPendingChanges
    }

    public init(context: ModelContext) {
        self.context = context
        changes = PersistenceViewRevision(context: context, domains: .tasks) { [weak self] in
            guard let self, self.isActive else { return }
            self.apply(weekCount: self.requestedWeekCount, calendar: DayKey.calendar)
        }
    }

    deinit {
        pendingCalculation?.cancel()
        midnightRefresh?.cancel()
    }

    public func apply(
        weekCount: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = DayKey.calendar
    ) {
        isActive = true
        requestedWeekCount = max(1, weekCount)
        requestedCalendar = calendar
        let request = Request(
            revision: changes?.value ?? 0, weekCount: requestedWeekCount,
            dayKey: DayKey.key(for: referenceDate, calendar: calendar), calendar: calendar,
            pending: ActivityPendingChanges(context: context)
        )
        if completedRequest == request {
            generation += 1
            pendingCalculation?.cancel()
            pendingCalculation = nil
            pendingRequest = nil
            isLoading = false
            errorMessage = nil
            // A width/day/data change invalidates this cache; tab reentry does not.
            scheduleMidnightRefresh(calendar: calendar)
            return
        }
        guard pendingRequest != request else { return }
        generation += 1
        let requestGeneration = generation
        pendingCalculation?.cancel()
        pendingRequest = request
        isLoading = true
        errorMessage = nil
        let container = context.container

        pendingCalculation = Swift.Task { [weak self] in
            await Swift.Task.yield()
            guard !Swift.Task.isCancelled else { return }
            let calculation = Swift.Task.detached(priority: .userInitiated) {
                let reader = ActivityOverviewReader(modelContainer: container)
                return try await reader.loadOverview(
                    weekCount: request.weekCount, referenceDate: referenceDate,
                    calendar: calendar, pending: request.pending
                )
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await calculation.value
                } onCancel: {
                    calculation.cancel()
                }
                guard !Swift.Task.isCancelled, let self, generation == requestGeneration else { return }
                overview = result
                completedRequest = request
                pendingRequest = nil
                isLoading = false
                pendingCalculation = nil
                scheduleMidnightRefresh(calendar: calendar)
            } catch is CancellationError {
                // The current generation owns the visible result.
            } catch {
                guard !Swift.Task.isCancelled, let self, generation == requestGeneration else { return }
                errorMessage = "활동 기록을 불러오지 못했습니다."
                pendingRequest = nil
                isLoading = false
                pendingCalculation = nil
            }
        }
    }

    public func refresh(referenceDate: Date = Date()) {
        guard isActive else { return }
        completedRequest = nil
        apply(weekCount: requestedWeekCount, referenceDate: referenceDate, calendar: requestedCalendar)
    }

    public func retry() { refresh() }

    public func cancel() {
        isActive = false
        generation += 1
        pendingCalculation?.cancel()
        pendingCalculation = nil
        pendingRequest = nil
        midnightRefresh?.cancel()
        midnightRefresh = nil
        isLoading = false
    }

    func scheduleMidnightRefresh(calendar: Calendar) {
        midnightRefresh?.cancel()
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return
        }
        let delay = max(1, nextDay.timeIntervalSince(now) + 1)
        midnightRefresh = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: .seconds(delay))
                guard !Swift.Task.isCancelled else { return }
                self?.refresh()
            } catch {
                // Cancellation means the view left or a newer refresh owns the timer.
            }
        }
    }
}
