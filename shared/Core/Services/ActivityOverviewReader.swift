import Foundation
import SwiftData

struct ActivityPendingChanges: Equatable, Sendable {
    let excludedIDs: Set<PersistentIdentifier>
    let snapshots: Set<TaskActivitySnapshot>

    @MainActor
    init(context: ModelContext) {
        let insertedAndChanged = context.insertedModelsArray + context.changedModelsArray
        let deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
        excludedIDs = Set((insertedAndChanged + context.deletedModelsArray).compactMap {
            ($0 as? TaskCompletionActivity)?.persistentModelID
        })
        snapshots = Set(insertedAndChanged.compactMap { model in
            guard let activity = model as? TaskCompletionActivity,
                  !deleted.contains(activity.persistentModelID), activity.supersededAt == nil else { return nil }
            return TaskActivitySnapshot(taskID: activity.taskId, activityDayKey: activity.activityDayKey)
        })
    }
}

/// Constructed from a detached task so both the context and aggregation stay off MainActor.
@ModelActor
actor ActivityOverviewReader {
    func loadOverview(
        weekCount: Int,
        referenceDate: Date,
        calendar: Calendar,
        pending: ActivityPendingChanges
    ) throws -> ActivityOverview {
        let isCancelled = { Swift.Task<Never, Never>.isCancelled }
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
        var snapshots = try self.snapshots(
            from: loadedLowerBound,
            through: range.todayDayKey,
            pending: pending,
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
                        byAddingDays: -(ActivityOverviewSession.backwardPageDayCount - 1),
                        to: pageEnd,
                        calendar: calendar
                      ) else {
                    break
                }
                let page = try self.snapshots(
                    from: pageStart,
                    through: pageEnd,
                    pending: pending,
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
            ? try hasTaskActivity(
                before: loadedLowerBound,
                pending: pending
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

    private func snapshots(
        from lowerBound: String,
        through upperBound: String,
        pending: ActivityPendingChanges,
        isCancelled: () -> Bool
    ) throws -> [TaskActivitySnapshot] {
        let descriptor = FetchDescriptor<TaskCompletionActivity>(predicate: #Predicate {
            $0.supersededAt == nil && $0.activityDayKey >= lowerBound && $0.activityDayKey <= upperBound
        })
        var result = Set<TaskActivitySnapshot>()
        try modelContext.enumerate(descriptor, batchSize: 256) { activity in
            if isCancelled() { throw CancellationError() }
            guard !pending.excludedIDs.contains(activity.persistentModelID) else { return }
            result.insert(TaskActivitySnapshot(taskID: activity.taskId, activityDayKey: activity.activityDayKey))
        }
        result.formUnion(pending.snapshots.filter {
            $0.activityDayKey >= lowerBound && $0.activityDayKey <= upperBound
        })
        return Array(result)
    }

    private func hasTaskActivity(before dayKey: String, pending: ActivityPendingChanges) throws -> Bool {
        if pending.snapshots.contains(where: { $0.activityDayKey < dayKey }) { return true }
        var descriptor = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate { $0.supersededAt == nil && $0.activityDayKey < dayKey },
            sortBy: [SortDescriptor(\TaskCompletionActivity.activityDayKey, order: .reverse)]
        )
        descriptor.fetchLimit = 256
        descriptor.fetchOffset = 0
        while true {
            try Swift.Task.checkCancellation()
            let batch = try modelContext.fetch(descriptor)
            if batch.contains(where: { !pending.excludedIDs.contains($0.persistentModelID) }) { return true }
            if batch.count < 256 { return false }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
    }
}
