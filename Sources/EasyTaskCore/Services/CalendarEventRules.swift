import Foundation

public enum CalendarEventRules {
    public struct EventDraft: Equatable {
        public var title: String
        public var startAt: Date
        public var endAt: Date
        public var note: String?
        public var color: String?

        public var startDayKey: String { DayKey.key(for: startAt) }
        public var endDayKey: String { DayKey.key(for: endAt) }
    }

    public static func normalizedDraft(
        title: String,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        color: String? = nil
    ) -> EventDraft? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let normalizedStart = DayKey.startOfDay(for: min(startAt, endAt))
        let normalizedEnd = DayKey.startOfDay(for: max(startAt, endAt))
        return EventDraft(
            title: trimmedTitle,
            startAt: normalizedStart,
            endAt: normalizedEnd,
            note: normalizedOptionalText(note),
            color: normalizedColorID(color)
        )
    }

    public static func makeEvent(
        title: String,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        color: String? = nil,
        now: Date = Date()
    ) -> CalendarEvent? {
        guard let draft = normalizedDraft(
            title: title,
            startAt: startAt,
            endAt: endAt,
            note: note,
            color: color
        ) else {
            return nil
        }

        return CalendarEvent(
            title: draft.title,
            startAt: draft.startAt,
            endAt: draft.endAt,
            note: draft.note,
            color: draft.color,
            createdAt: now,
            updatedAt: now
        )
    }

    @discardableResult
    public static func update(
        _ event: CalendarEvent,
        title: String,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        color: String? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let draft = normalizedDraft(
            title: title,
            startAt: startAt,
            endAt: endAt,
            note: note,
            color: color
        ) else {
            return false
        }

        event.title = draft.title
        event.startAt = draft.startAt
        event.endAt = draft.endAt
        event.startDayKey = draft.startDayKey
        event.endDayKey = draft.endDayKey
        event.note = draft.note
        event.color = draft.color
        event.updatedAt = now
        return true
    }

    public static func events(on date: Date, in events: [CalendarEvent]) -> [CalendarEvent] {
        Self.events(onDayKey: DayKey.key(for: date), in: events)
    }

    public static func events(onDayKey dayKey: String, in events: [CalendarEvent]) -> [CalendarEvent] {
        sorted(events.filter {
            $0.supersededAt == nil && $0.startDayKey <= dayKey && dayKey <= $0.endDayKey
        })
    }

    public static func events(
        overlapping startDate: Date,
        through endDate: Date,
        in events: [CalendarEvent]
    ) -> [CalendarEvent] {
        let startDayKey = DayKey.key(for: DayKey.startOfDay(for: min(startDate, endDate)))
        let endDayKey = DayKey.key(for: DayKey.startOfDay(for: max(startDate, endDate)))
        return sorted(events.filter {
            $0.supersededAt == nil && $0.startDayKey <= endDayKey && $0.endDayKey >= startDayKey
        })
    }

    public static func sorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted(by: eventSort)
    }

    @discardableResult
    public static func detachTasks(
        from event: CalendarEvent,
        in tasks: [Task],
        now: Date = Date()
    ) -> Int {
        detachTasks(fromEventID: event.id, in: tasks, now: now)
    }

    @discardableResult
    public static func detachTasks(
        fromEventID eventID: UUID,
        in tasks: [Task],
        now: Date = Date()
    ) -> Int {
        var detachedCount = 0
        for task in tasks where task.supersededAt == nil && task.eventId == eventID {
            task.eventId = nil
            task.updatedAt = now
            detachedCount += 1
        }
        return detachedCount
    }

    private static func eventSort(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDayKey != rhs.startDayKey {
            return lhs.startDayKey < rhs.startDayKey
        }
        if lhs.endDayKey != rhs.endDayKey {
            return lhs.endDayKey > rhs.endDayKey
        }
        return lhs.title < rhs.title
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizedColorID(_ value: String?) -> String? {
        guard let trimmedValue = normalizedOptionalText(value) else { return nil }
        return CalendarEventColor(rawValue: trimmedValue)?.rawValue
    }
}
