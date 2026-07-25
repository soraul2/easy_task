import Foundation

public struct CalendarEventReuseDraft: Equatable, Sendable {
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var note: String?
    public var color: String?
    public var sourceEventID: UUID?

    public init(
        title: String,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        color: String? = nil,
        sourceEventID: UUID? = nil
    ) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.color = color
        self.sourceEventID = sourceEventID
    }

    public var includedDayCount: Int {
        CalendarEventReuseRules.includedDayCount(
            from: startAt,
            through: endAt
        )
    }
}

public struct CalendarEventRecommendation: Equatable, Identifiable, Sendable {
    public var eventID: UUID
    public var instanceID: UUID
    public var title: String
    public var includedDayCount: Int
    public var note: String?
    public var color: String?
    public var updatedAt: Date

    public init(
        eventID: UUID,
        instanceID: UUID,
        title: String,
        includedDayCount: Int,
        note: String?,
        color: String?,
        updatedAt: Date
    ) {
        self.eventID = eventID
        self.instanceID = instanceID
        self.title = title
        self.includedDayCount = includedDayCount
        self.note = note
        self.color = color
        self.updatedAt = updatedAt
    }

    public var id: UUID { instanceID }

    public var summary: String {
        let colorTitle = CalendarEventColor(
            rawValue: color ?? CalendarEventPalette.defaultColor
        )?.title ?? CalendarEventColor.blue.title
        let noteTitle = note == nil ? "메모 없음" : "메모 있음"
        return "\(title) · \(includedDayCount)일 · \(colorTitle) · \(noteTitle)"
    }
}

public enum CalendarEventReuseRules {
    public static let recommendationLimit = 5

    public static func includedDayCount(
        from startAt: Date,
        through endAt: Date,
        calendar: Calendar = DayKey.calendar
    ) -> Int {
        let normalizedStart = calendar.startOfDay(for: min(startAt, endAt))
        let normalizedEnd = calendar.startOfDay(for: max(startAt, endAt))
        return max(
            1,
            (calendar.dateComponents(
                [.day],
                from: normalizedStart,
                to: normalizedEnd
            ).day ?? 0) + 1
        )
    }

    public static func duplicateDraft(
        from event: CalendarEvent,
        targetStartAt: Date,
        calendar: Calendar = DayKey.calendar
    ) -> CalendarEventReuseDraft {
        let dayCount = includedDayCount(
            from: event.startAt,
            through: event.endAt,
            calendar: calendar
        )
        let normalizedStart = calendar.startOfDay(for: targetStartAt)
        let normalizedEnd = calendar.date(
            byAdding: .day,
            value: dayCount - 1,
            to: normalizedStart
        ) ?? normalizedStart
        return CalendarEventReuseDraft(
            title: event.title,
            startAt: normalizedStart,
            endAt: normalizedEnd,
            note: event.note,
            color: event.color,
            sourceEventID: event.id
        )
    }

    public static func makeIndependentEvent(
        from draft: CalendarEventReuseDraft,
        now: Date = Date()
    ) -> CalendarEvent? {
        CalendarEventRules.makeEvent(
            title: draft.title,
            startAt: draft.startAt,
            endAt: draft.endAt,
            note: draft.note,
            color: draft.color,
            now: now
        )
    }

    public static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "ko_KR")
            )
    }

    public static func recommendations(
        for title: String,
        from events: [CalendarEvent],
        excludingEventID: UUID? = nil,
        limit: Int = recommendationLimit
    ) -> [CalendarEventRecommendation] {
        let normalizedQuery = normalizedTitle(title)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        let representatives = activeRepresentatives(events)
            .filter { $0.id != excludingEventID }
            .filter {
                normalizedTitle($0.title).hasPrefix(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsIsExact = normalizedTitle(lhs.title) == normalizedQuery
                let rhsIsExact = normalizedTitle(rhs.title) == normalizedQuery
                if lhsIsExact != rhsIsExact {
                    return lhsIsExact
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.instanceID.uuidString > rhs.instanceID.uuidString
            }

        var seenSettings: Set<RecommendationSettingsKey> = []
        var result: [CalendarEventRecommendation] = []
        for event in representatives {
            let dayCount = includedDayCount(
                from: event.startAt,
                through: event.endAt
            )
            let normalizedNote = normalizedOptionalText(event.note)
            let key = RecommendationSettingsKey(
                title: normalizedTitle(event.title),
                includedDayCount: dayCount,
                note: normalizedNote,
                color: normalizedColor(event.color)
            )
            guard seenSettings.insert(key).inserted else { continue }
            result.append(CalendarEventRecommendation(
                eventID: event.id,
                instanceID: event.instanceID,
                title: event.title,
                includedDayCount: dayCount,
                note: normalizedNote,
                color: normalizedColor(event.color),
                updatedAt: event.updatedAt
            ))
            if result.count == limit {
                break
            }
        }
        return result
    }

    public static func applying(
        _ recommendation: CalendarEventRecommendation,
        to draft: CalendarEventReuseDraft
    ) -> CalendarEventReuseDraft {
        let normalizedStart = DayKey.startOfDay(for: draft.startAt)
        return CalendarEventReuseDraft(
            title: draft.title,
            startAt: normalizedStart,
            endAt: DayKey.addingDays(
                recommendation.includedDayCount - 1,
                to: normalizedStart
            ),
            note: recommendation.note,
            color: recommendation.color,
            sourceEventID: draft.sourceEventID
        )
    }

    private static func activeRepresentatives(
        _ events: [CalendarEvent]
    ) -> [CalendarEvent] {
        var representatives: [UUID: CalendarEvent] = [:]
        for event in events where event.supersededAt == nil {
            guard let existing = representatives[event.id] else {
                representatives[event.id] = event
                continue
            }
            if event.updatedAt > existing.updatedAt ||
                (event.updatedAt == existing.updatedAt &&
                    event.instanceID.uuidString > existing.instanceID.uuidString) {
                representatives[event.id] = event
            }
        }
        return Array(representatives.values)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func normalizedColor(_ value: String?) -> String? {
        guard let value,
              let color = CalendarEventColor(rawValue: value) else {
            return nil
        }
        return color.rawValue
    }

    private struct RecommendationSettingsKey: Hashable {
        var title: String
        var includedDayCount: Int
        var note: String?
        var color: String?
    }
}
