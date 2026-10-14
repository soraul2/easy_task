import Foundation
import SwiftData

/// Create a fresh reader inside Task.detached for each publication. Its context
/// and fetched model rows stay on its executor; only a Sendable snapshot leaves.
@ModelActor
@available(watchOS 11, *)
public actor CalendarWidgetSnapshotReader {
    public func loadSnapshot(
        referenceDate: Date = Date(),
        themeID: String = AppThemePreset.defaultID,
        maximumEventCount: Int = 256
    ) throws -> CalendarWidgetSnapshot {
        try Swift.Task<Never, Never>.checkCancellation()
        let snapshot = try Self.makeSnapshot(
            in: modelContext,
            referenceDate: referenceDate,
            themeID: themeID,
            maximumEventCount: maximumEventCount
        )
        try Swift.Task<Never, Never>.checkCancellation()
        return snapshot
    }

    /// The same query/projection for a caller that owns pending context edits.
    /// This method is synchronous: context and model rows never leave its executor.
    public nonisolated static func makeSnapshot(
        in context: ModelContext,
        referenceDate: Date = Date(),
        themeID: String = AppThemePreset.defaultID,
        maximumEventCount: Int = 256
    ) throws -> CalendarWidgetSnapshot {
        let coverage = CalendarWidgetSnapshot.coverageDayKeys(for: referenceDate)
        let lockScreenCoverage = LockScreenWidgetRules.coverageDayKeys(for: referenceDate)
        return try makeSnapshot(
            referenceDate: referenceDate,
            themeID: themeID,
            maximumEventCount: maximumEventCount,
            fetchEvents: {
                try BoundedQueryService.events(
                    overlappingStartDayKey: coverage.startDayKey,
                    endDayKey: coverage.endDayKey,
                    in: context
                )
            },
            fetchTasks: {
                let plannedTasks = try context.fetch(
                    BoundedQueryService.widgetPlannedTasksDescriptor(
                        from: lockScreenCoverage.startDayKey,
                        through: lockScreenCoverage.endDayKey
                    )
                )
                let completedTasks = try context.fetch(
                    BoundedQueryService.widgetCompletedTasksDescriptor(
                        from: lockScreenCoverage.startDayKey,
                        through: lockScreenCoverage.endDayKey
                    )
                )
                var seenInstanceIDs: Set<UUID> = []
                return (plannedTasks + completedTasks).filter {
                    seenInstanceIDs.insert($0.instanceID).inserted
                }
            }
        )
    }

    // Error injection verifies partial calendar publication without a broken or
    // user-owned store. The same helper is used by both public reader paths.
    nonisolated static func makeSnapshot(
        referenceDate: Date,
        themeID: String,
        maximumEventCount: Int = 256,
        fetchEvents: () throws -> [CalendarEvent],
        fetchTasks: () throws -> [Task]
    ) throws -> CalendarWidgetSnapshot {
        let events = try fetchEvents()
        let tasks: [Task]?
        do {
            tasks = try fetchTasks()
        } catch {
            // Calendar events remain publishable when the auxiliary planner or
            // lock-screen task query is temporarily unavailable.
            tasks = nil
        }
        return CalendarWidgetSnapshot.make(
            events: events,
            tasks: tasks,
            referenceDate: referenceDate,
            themeID: themeID,
            maximumEventCount: maximumEventCount
        )
    }
}
