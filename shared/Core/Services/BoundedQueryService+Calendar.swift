import Foundation
import SwiftData

extension BoundedQueryService {
    /// A range descriptor finds candidate logical IDs, not necessarily their
    /// latest physical versions. Complete those IDs before testing the range.
    @MainActor
    public static func events(
        overlappingStartDayKey startDayKey: String,
        endDayKey: String,
        in context: ModelContext
    ) throws -> [CalendarEvent] {
        try representativeCalendarEvents(
            overlappingStartDayKey: startDayKey,
            endDayKey: endDayKey,
            fetch: { try context.fetch($0) }
        )
    }

    // Injection tests query failures without using an unavailable user store.
    @MainActor
    static func representativeCalendarEvents(
        overlappingStartDayKey startDayKey: String,
        endDayKey: String,
        fetch: (FetchDescriptor<CalendarEvent>) throws -> [CalendarEvent]
    ) throws -> [CalendarEvent] {
        let seeds = try fetch(eventsDescriptor(
            overlappingStartDayKey: startDayKey, endDayKey: endDayKey))
        let candidateIDs = Array(Set(seeds.map(\.id))).sorted { $0.uuidString < $1.uuidString }
        guard !candidateIDs.isEmpty else { return [] }

        var versions: [CalendarEvent] = []
        // As in the existing Task readers, this bounds predicate inputs, never
        // result rows: every active version of each candidate ID is required.
        for startIndex in stride(from: 0, to: candidateIDs.count, by: 200) {
            let endIndex = min(startIndex + 200, candidateIDs.count)
            let ids = Array(candidateIDs[startIndex..<endIndex])
            versions += try fetch(FetchDescriptor<CalendarEvent>(
                predicate: #Predicate<CalendarEvent> { event in
                    event.supersededAt == nil && ids.contains(event.id)
                },
                sortBy: [SortDescriptor(\CalendarEvent.instanceID)]
            ))
        }
        return CalendarEventRules.events(
            overlappingStartDayKey: startDayKey, endDayKey: endDayKey, in: versions)
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
