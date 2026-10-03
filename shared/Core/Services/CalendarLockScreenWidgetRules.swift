import Foundation

public extension CalendarWidgetConstants {
    // A new configuration leaves installed task/quick-add widgets unchanged.
    static let calendarLockScreenKind = "PlanBaseCalendarLockScreenWidget"
}

public enum CalendarLockScreenAvailability: Equatable, Sendable {
    case available
    case needsRefresh
    case requiresAppUpdate

    public var message: String {
        switch self {
        case .available: ""
        case .needsRefresh: "앱을 열어 갱신"
        case .requiresAppUpdate: "업데이트 필요"
        }
    }
}

public struct CalendarLockScreenEventPreview: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let periodText: String
}

public struct CalendarLockScreenTimelineEntry: Equatable, Sendable {
    public let date: Date
    public let availability: CalendarLockScreenAvailability
}

public struct CalendarLockScreenPresentation: Equatable, Sendable {
    public let availability: CalendarLockScreenAvailability
    // Unknown/unreadable coverage must never become a confirmed zero.
    public let totalCount: Int?
    public let previews: [CalendarLockScreenEventPreview]
    public let remainingCount: Int

    public var countText: String {
        guard let totalCount else { return availability.message }
        return totalCount == 0 ? "일정 없음" : "일정 \(totalCount)개"
    }

    public var inlineText: String {
        guard let first = previews.first else { return countText }
        let remaining = (totalCount ?? 0) - 1
        let suffix = remaining > 0 ? " · +\(remaining)" : ""
        return "\(first.title) · \(first.periodText)\(suffix)"
    }

    public var accessibilityText: String {
        guard availability == .available else { return availability.message }
        guard let totalCount, totalCount > 0 else { return "오늘 일정 없음" }
        let details = previews.map { "\($0.title), \($0.periodText)" }
        let remainder = remainingCount > 0 && !previews.isEmpty
            ? ["그 외 \(remainingCount)개"] : []
        return (["오늘 일정 \(totalCount)개"] + details + remainder)
            .joined(separator: ", ")
    }
}

public enum CalendarLockScreenWidgetRules {
    public static let maximumPreviewCount = 2
    public static let maximumTimelineDayCount = 8

    public static func presentation(
        snapshot: CalendarWidgetSnapshot?,
        at date: Date,
        availability: CalendarLockScreenAvailability = .available,
        redactingDetails: Bool = false
    ) -> CalendarLockScreenPresentation {
        guard availability == .available else { return unavailable(availability) }
        guard let snapshot else { return unavailable(.needsRefresh) }
        guard snapshot.schemaVersion <= CalendarWidgetSnapshot.currentSchemaVersion else {
            return unavailable(.requiresAppUpdate)
        }
        guard snapshot.schemaVersion >= 1,
              snapshot.schemaVersion < 5 || snapshot.hasCompleteCalendarMetadata,
              validCoverage(snapshot),
              snapshot.covers(dayKey: DayKey.key(for: date)),
              validEventsAndCounts(snapshot) else {
            return unavailable(.needsRefresh)
        }

        let dayKey = DayKey.key(for: date)
        let visibleEvents = snapshot.events(onDayKey: dayKey).sorted(by: precedes)
        // V5's full-count dictionary is sparse: an absent day means zero.
        // Legacy snapshots retain their preview-based fallback contract.
        let declaredCount: Int? = snapshot.schemaVersion >= 5
            ? (snapshot.eventCountsByDayKey[dayKey] ?? 0)
            : snapshot.eventCountsByDayKey[dayKey]
        // Counts may exceed the capped preview payload, but cannot undercount it.
        if let declaredCount, declaredCount < visibleEvents.count {
            return unavailable(.needsRefresh)
        }
        let count = declaredCount ?? visibleEvents.count
        let previews: [CalendarLockScreenEventPreview] = redactingDetails ? [] :
            visibleEvents.prefix(maximumPreviewCount).map {
                CalendarLockScreenEventPreview(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    periodText: periodText(for: $0)
                )
            }
        return CalendarLockScreenPresentation(
            availability: .available,
            totalCount: count,
            previews: previews,
            remainingCount: count - previews.count
        )
    }

    // Calendar-only snapshots work even when publishing task summaries failed.
    // Date entries select the next day's events; they do not reread live data.
    // A separate terminal entry guards both coverage expiry and the eight-day
    // horizon even when a requested replacement timeline has not arrived.
    public static func timeline(
        snapshot: CalendarWidgetSnapshot?,
        startingAt now: Date,
        availability: CalendarLockScreenAvailability = .available
    ) -> (entries: [CalendarLockScreenTimelineEntry], refreshDate: Date) {
        let initialAvailability = presentation(
            snapshot: snapshot, at: now, availability: availability
        ).availability
        var entries = [CalendarLockScreenTimelineEntry(
            date: now, availability: initialAvailability
        )]
        guard initialAvailability == .available else {
            return (entries, timelineRefreshDate(after: now))
        }

        for offset in 1..<maximumTimelineDayCount {
            let midnight = DayKey.addingDays(offset, to: DayKey.startOfDay(for: now))
            let nextAvailability = presentation(snapshot: snapshot, at: midnight).availability
            entries.append(CalendarLockScreenTimelineEntry(
                date: midnight, availability: nextAvailability
            ))
            if nextAvailability != .available {
                return (entries, midnight)
            }
        }

        let terminalDate = DayKey.addingDays(
            maximumTimelineDayCount, to: DayKey.startOfDay(for: now)
        )
        entries.append(CalendarLockScreenTimelineEntry(
            date: terminalDate, availability: .needsRefresh
        ))
        return (entries, terminalDate)
    }

    // Includes the terminal date; the available-entry limit remains eight.
    public static func timelineEntryDates(
        snapshot: CalendarWidgetSnapshot?,
        startingAt now: Date,
        availability: CalendarLockScreenAvailability = .available
    ) -> [Date] {
        timeline(snapshot: snapshot, startingAt: now, availability: availability)
            .entries.map(\.date)
    }

    public static func timelineRefreshDate(after date: Date) -> Date {
        DayKey.addingDays(1, to: DayKey.startOfDay(for: date))
    }

    private static func unavailable(
        _ availability: CalendarLockScreenAvailability
    ) -> CalendarLockScreenPresentation {
        CalendarLockScreenPresentation(
            availability: availability,
            totalCount: nil,
            previews: [],
            remainingCount: 0
        )
    }

    private static func validCoverage(_ snapshot: CalendarWidgetSnapshot) -> Bool {
        DayKey.date(from: snapshot.coveredStartDayKey) != nil &&
            DayKey.date(from: snapshot.coveredEndDayKey) != nil &&
            snapshot.coveredStartDayKey <= snapshot.coveredEndDayKey
    }

    private static func validEventsAndCounts(_ snapshot: CalendarWidgetSnapshot) -> Bool {
        var seenIDs: Set<UUID> = []
        for event in snapshot.events {
            guard seenIDs.insert(event.id).inserted,
                  !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  DayKey.date(from: event.startDayKey) != nil,
                  DayKey.date(from: event.endDayKey) != nil,
                  event.startDayKey <= event.endDayKey else { return false }
        }
        return snapshot.eventCountsByDayKey.allSatisfy { key, count in
            count >= 0 && DayKey.date(from: key) != nil && snapshot.covers(dayKey: key)
        }
    }

    private static func precedes(
        _ lhs: CalendarWidgetEventSnapshot,
        _ rhs: CalendarWidgetEventSnapshot
    ) -> Bool {
        if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
        if lhs.endDayKey != rhs.endDayKey { return lhs.endDayKey > rhs.endDayKey }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func periodText(for event: CalendarWidgetEventSnapshot) -> String {
        guard event.startDayKey != event.endDayKey,
              let start = DayKey.date(from: event.startDayKey),
              let end = DayKey.date(from: event.endDayKey) else { return "종일" }
        let calendar = DayKey.calendar
        let includeYear = calendar.component(.year, from: start) !=
            calendar.component(.year, from: end)
        func label(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let prefix = includeYear ? "\(parts.year ?? 0)/" : ""
            return "\(prefix)\(parts.month ?? 0)/\(parts.day ?? 0)"
        }
        return "\(label(start))–\(label(end))"
    }
}
