import Foundation
import SwiftData

public enum BoundedQueryService {
    public static let archivePageSize = 30

    public static func boardTasksDescriptor(
        selectedDayKey: String
    ) -> FetchDescriptor<Task> {
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && (
                    task.plannedDayKey == selectedDayKey ||
                    task.completedDayKey == selectedDayKey
                )
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func carryoverTasksDescriptor(
        before dayKey: String
    ) -> FetchDescriptor<Task> {
        let doneStatus = TaskStatus.done.rawValue
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.status != doneStatus &&
                    task.plannedDayKey < dayKey
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func eventsDescriptor(
        overlappingStartDayKey startDayKey: String,
        endDayKey: String
    ) -> FetchDescriptor<CalendarEvent> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<CalendarEvent> { event in
                event.supersededAt == nil &&
                    event.startDayKey <= upperBound &&
                    event.endDayKey >= lowerBound
            },
            sortBy: [
                SortDescriptor(\CalendarEvent.startDayKey),
                SortDescriptor(\CalendarEvent.endDayKey, order: .reverse),
                SortDescriptor(\CalendarEvent.title)
            ]
        )
    }

    public static func calendarTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.plannedDayKey >= lowerBound &&
                    task.plannedDayKey <= upperBound
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func templatePlacementsDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<TemplatePlacement> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<TemplatePlacement> { placement in
                placement.supersededAt == nil &&
                    placement.dayKey >= lowerBound &&
                    placement.dayKey <= upperBound
            },
            sortBy: [
                SortDescriptor(\TemplatePlacement.dayKey),
                SortDescriptor(\TemplatePlacement.createdAt)
            ]
        )
    }

    @MainActor
    public static func nextOrder(
        in context: ModelContext,
        dayKey: String,
        status: TaskStatus
    ) throws -> Double {
        let statusValue = status.rawValue
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.plannedDayKey == dayKey &&
                    task.status == statusValue
            },
            sortBy: [SortDescriptor(\Task.order, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.order ?? 0) + 100
    }

    @MainActor
    public static func tasksLinked(
        toEventID eventID: UUID,
        in context: ModelContext
    ) throws -> [Task] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.eventId == eventID
            }
        ))
    }

    @MainActor
    public static func tasks(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext
    ) throws -> [Task] {
        try context.fetch(calendarTasksDescriptor(
            from: startDayKey,
            through: endDayKey
        ))
    }
}
