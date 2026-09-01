import Foundation
import SwiftData

extension BoundedQueryService {
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

    public static func recentCalendarEventsDescriptor()
        -> FetchDescriptor<CalendarEvent> {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.supersededAt == nil
            },
            sortBy: [
                SortDescriptor(\CalendarEvent.updatedAt, order: .reverse),
                SortDescriptor(\CalendarEvent.instanceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = eventRecommendationScanLimit
        return descriptor
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

    public static func widgetPlannedTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
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

    public static func widgetCompletedTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    (task.completedDayKey ?? "") >= lowerBound &&
                    (task.completedDayKey ?? "") <= upperBound
            },
            sortBy: [
                SortDescriptor(\Task.completedDayKey),
                SortDescriptor(\Task.updatedAt),
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
}
