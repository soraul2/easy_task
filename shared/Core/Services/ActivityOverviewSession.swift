import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class ActivityOverviewSession {
    public static let backwardPageDayCount = 90

    public private(set) var overview = ActivityOverview()
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var pendingCalculation: Swift.Task<Void, Never>?
    @ObservationIgnored private var midnightRefresh: Swift.Task<Void, Never>?
    @ObservationIgnored private var dataObserver: ActivityNotificationObserver?
    @ObservationIgnored private var timeZoneObserver: ActivityNotificationObserver?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var requestedWeekCount = TaskActivityRules.compactWeekCount
    @ObservationIgnored private var requestedCalendar = DayKey.calendar

    public init(context: ModelContext) {
        self.context = context
        dataObserver = ActivityNotificationObserver(
            NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification,
            object: context,
            queue: nil
        ) { [weak self] _ in
            Swift.Task { @MainActor [weak self] in
                guard self?.isActive == true else { return }
                self?.refresh()
            }
        })
        timeZoneObserver = ActivityNotificationObserver(
            NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Swift.Task { @MainActor [weak self] in
                guard self?.isActive == true else { return }
                self?.apply(
                    weekCount: self?.requestedWeekCount ?? TaskActivityRules.compactWeekCount,
                    referenceDate: Date(),
                    calendar: DayKey.calendar
                )
            }
        })
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
        generation += 1
        let requestGeneration = generation
        pendingCalculation?.cancel()
        isLoading = true
        errorMessage = nil

        pendingCalculation = Swift.Task { [weak self] in
            await Swift.Task.yield()
            guard !Swift.Task.isCancelled, let self else { return }
            do {
                let result = try loadOverview(
                    weekCount: requestedWeekCount,
                    referenceDate: referenceDate,
                    calendar: calendar,
                    isCancelled: { Swift.Task<Never, Never>.isCancelled }
                )
                guard !Swift.Task.isCancelled, generation == requestGeneration else {
                    return
                }
                overview = result
                isLoading = false
                pendingCalculation = nil
                scheduleMidnightRefresh(calendar: calendar)
            } catch is CancellationError {
                // A newer width, date, or lifecycle request owns the visible result.
            } catch {
                guard !Swift.Task.isCancelled, generation == requestGeneration else {
                    return
                }
                overview = ActivityOverview()
                errorMessage = "활동 기록을 불러오지 못했습니다."
                isLoading = false
                pendingCalculation = nil
            }
        }
    }

    public func refresh(referenceDate: Date = Date()) {
        guard isActive else { return }
        apply(
            weekCount: requestedWeekCount,
            referenceDate: referenceDate,
            calendar: requestedCalendar
        )
    }

    public func retry() {
        refresh()
    }

    public func cancel() {
        isActive = false
        generation += 1
        pendingCalculation?.cancel()
        pendingCalculation = nil
        midnightRefresh?.cancel()
        midnightRefresh = nil
        isLoading = false
    }
}

private final class ActivityNotificationObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

private extension ActivityOverviewSession {
    func loadOverview(
        weekCount: Int,
        referenceDate: Date,
        calendar: Calendar,
        isCancelled: () -> Bool
    ) throws -> ActivityOverview {
        let range = TaskActivityRules.heatmapRange(
            weekCount: weekCount,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let bestStreakStart = TaskActivityRules.dayKey(
            byAddingDays: -(TaskActivityRules.bestStreakDayCount - 1),
            to: range.todayDayKey,
            calendar: calendar
        ) ?? range.startDayKey
        var loadedLowerBound = min(range.startDayKey, bestStreakStart)
        var snapshots = try BoundedQueryService.taskActivitySnapshots(
            from: loadedLowerBound,
            through: range.todayDayKey,
            in: context,
            isCancelled: isCancelled
        )
        var activeDayKeys = Set(snapshots.map(\.activityDayKey))
        let yesterday = TaskActivityRules.dayKey(
            byAddingDays: -1,
            to: range.todayDayKey,
            calendar: calendar
        )
        let currentAnchor: String?
        if activeDayKeys.contains(range.todayDayKey) {
            currentAnchor = range.todayDayKey
        } else if let yesterday, activeDayKeys.contains(yesterday) {
            currentAnchor = yesterday
        } else {
            currentAnchor = nil
        }

        if let currentAnchor,
           hasActivityEveryDay(
            from: loadedLowerBound,
            through: currentAnchor,
            activeDayKeys: activeDayKeys,
            calendar: calendar
           ) {
            while true {
                if isCancelled() { throw CancellationError() }
                guard let pageEnd = TaskActivityRules.dayKey(
                    byAddingDays: -1,
                    to: loadedLowerBound,
                    calendar: calendar
                ),
                      let pageStart = TaskActivityRules.dayKey(
                        byAddingDays: -(Self.backwardPageDayCount - 1),
                        to: pageEnd,
                        calendar: calendar
                      ) else {
                    break
                }
                let page = try BoundedQueryService.taskActivitySnapshots(
                    from: pageStart,
                    through: pageEnd,
                    in: context,
                    isCancelled: isCancelled
                )
                snapshots.append(contentsOf: page)
                activeDayKeys.formUnion(page.map(\.activityDayKey))
                loadedLowerBound = pageStart
                guard hasActivityEveryDay(
                    from: pageStart,
                    through: pageEnd,
                    activeDayKeys: activeDayKeys,
                    calendar: calendar
                ) else {
                    break
                }
            }
        }

        let hasEarlierActivity = snapshots.isEmpty
            ? try BoundedQueryService.hasTaskActivity(
                before: loadedLowerBound,
                in: context
            )
            : false
        return TaskActivityRules.overview(
            from: snapshots,
            weekCount: weekCount,
            referenceDate: referenceDate,
            calendar: calendar,
            hasEarlierActivity: hasEarlierActivity
        )
    }

    func hasActivityEveryDay(
        from lowerBound: String,
        through upperBound: String,
        activeDayKeys: Set<String>,
        calendar: Calendar
    ) -> Bool {
        guard lowerBound <= upperBound else { return true }
        var cursor = lowerBound
        while cursor <= upperBound {
            guard activeDayKeys.contains(cursor) else { return false }
            guard let next = TaskActivityRules.dayKey(
                byAddingDays: 1,
                to: cursor,
                calendar: calendar
            ) else {
                return false
            }
            cursor = next
        }
        return true
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
