import Foundation

/// Counts for the requested month cells, rebuilt from the current visible rows.
/// This value does not retain models or cache data between renders.
public struct CalendarMonthCountProjection: Equatable, Sendable {
    public let eventCountByDayKey: [String: Int]
    public let placementCountByDayKey: [String: Int]

    public func eventCount(onDayKey dayKey: String) -> Int {
        eventCountByDayKey[dayKey] ?? 0
    }

    public func placementCount(onDayKey dayKey: String) -> Int {
        placementCountByDayKey[dayKey] ?? 0
    }

    @MainActor
    public static func make(
        dates: [Date],
        events: [CalendarEvent],
        templatePlacements: [TemplatePlacement]
    ) -> Self {
        let dayKeys = Set(dates.map(DayKey.key(for:))).sorted()
        var eventCounts = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, 0) })
        var placementCounts = eventCounts
        guard !dayKeys.isEmpty else {
            return Self(eventCountByDayKey: eventCounts, placementCountByDayKey: placementCounts)
        }

        // Select the logical representative once, then read its interval once.
        // Date filtering before this selection would revive older moved ranges.
        let ranges = CalendarEventRules.activeRepresentatives(in: events).map {
            (startDayKey: $0.startDayKey, endDayKey: $0.endDayKey)
        }
        for range in ranges {
            for dayKey in dayKeys where range.startDayKey <= dayKey && dayKey <= range.endDayKey {
                eventCounts[dayKey, default: 0] += 1
            }
        }

        // Preserve TemplateService's active physical-row count policy. Counts
        // need neither its display order nor logical-ID deduplication.
        for placement in templatePlacements where placement.supersededAt == nil {
            let dayKey = placement.dayKey
            if placementCounts[dayKey] != nil {
                placementCounts[dayKey, default: 0] += 1
            }
        }
        return Self(eventCountByDayKey: eventCounts, placementCountByDayKey: placementCounts)
    }
}
