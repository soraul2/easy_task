import Foundation

@available(watchOS 11, *)
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

    /// Compare the values the editor displays, without treating nil/default storage
    /// representations or source metadata as an additional user edit.
    public func hasSameEditorValues(as other: Self) -> Bool {
        title == other.title &&
            DayKey.startOfDay(for: startAt) == DayKey.startOfDay(for: other.startAt) &&
            DayKey.startOfDay(for: endAt) == DayKey.startOfDay(for: other.endAt) &&
            (note ?? "") == (other.note ?? "") &&
            CalendarEventReuseRules.effectiveColor(color) == CalendarEventReuseRules.effectiveColor(other.color)
    }

    public var includedDayCount: Int {
        CalendarEventReuseRules.includedDayCount(
            from: startAt,
            through: endAt
        )
    }
}

@available(watchOS 11, *)
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

    public var details: String {
        let colorTitle = CalendarEventColor(rawValue: CalendarEventReuseRules.effectiveColor(color))!.title
        return "\(includedDayCount)일 · \(colorTitle)"
    }

    public var summary: String {
        "\(title) · \(details) · \(note == nil ? "메모 없음" : "메모 있음")"
    }
}

/// An editor-local value snapshot. No SwiftData models are retained while typing.
@available(watchOS 11, *)
struct CalendarEventRecommendationCandidate: Sendable {
    var normalizedTitle: String
    var recommendation: CalendarEventRecommendation
    var instanceSortKey: String
}

/// A local, one-step receipt. It never mutates the source event or persistent data.
@available(watchOS 11, *)
public struct CalendarEventRecommendationApplication: Equatable, Sendable {
    public let before: CalendarEventReuseDraft
    public private(set) var after: CalendarEventReuseDraft
    public let recommendation: CalendarEventRecommendation
    public private(set) var preservedExistingNote: Bool

    public init(recommendation: CalendarEventRecommendation, draft: CalendarEventReuseDraft) {
        self.recommendation = recommendation
        before = draft
        after = CalendarEventReuseRules.applying(recommendation, to: draft)
        preservedExistingNote = CalendarEventReuseRules.normalizedOptionalText(draft.note) != nil &&
            CalendarEventReuseRules.normalizedOptionalText(draft.note) !=
            CalendarEventReuseRules.normalizedOptionalText(recommendation.note)
    }

    public var canUndo: Bool { !before.hasSameEditorValues(as: after) }
    public var canReplaceNote: Bool {
        preservedExistingNote && CalendarEventReuseRules.normalizedOptionalText(recommendation.note) != nil
    }

    public var feedback: String {
        let message = canUndo ? "‘\(recommendation.title)’을 입력했어요" : "이미 같은 내용이 입력되어 있어요"
        return preservedExistingNote ? message + ". 작성한 메모는 유지했어요" : message
    }

    public func replacingNote() -> Self {
        guard canReplaceNote else { return self }
        var result = self
        result.after.note = CalendarEventReuseRules.normalizedOptionalText(recommendation.note)
        result.preservedExistingNote = false
        return result
    }
}

@available(watchOS 11, *)
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
        return recommendations(
            forNormalizedTitle: normalizedQuery,
            fromCandidates: recommendationCandidates(from: events),
            excludingEventID: excludingEventID,
            limit: limit
        )
    }

    static func recommendationCandidates(from events: [CalendarEvent]) -> [CalendarEventRecommendationCandidate] {
        // Converge logical IDs before title matching, including renamed versions.
        // Pre-sort once; each rank bucket below then keeps the same recency order.
        activeRepresentatives(events).map { event in
            let title = event.title
            let instanceID = event.instanceID
            return CalendarEventRecommendationCandidate(
                normalizedTitle: normalizedTitle(title),
                recommendation: CalendarEventRecommendation(
                    eventID: event.id,
                    instanceID: instanceID,
                    title: title,
                    includedDayCount: includedDayCount(from: event.startAt, through: event.endAt),
                    note: normalizedOptionalText(event.note),
                    color: effectiveColor(event.color),
                    updatedAt: event.updatedAt
                ),
                instanceSortKey: instanceID.uuidString
            )
        }.sorted { lhs, rhs in
            if lhs.recommendation.updatedAt != rhs.recommendation.updatedAt {
                return lhs.recommendation.updatedAt > rhs.recommendation.updatedAt
            }
            return lhs.instanceSortKey > rhs.instanceSortKey
        }
    }

    static func recommendations(
        forNormalizedTitle query: String,
        fromCandidates candidates: [CalendarEventRecommendationCandidate],
        excludingEventID: UUID? = nil,
        limit: Int = recommendationLimit
    ) -> [CalendarEventRecommendation] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let allowsContains = query.count >= 2
        var ranked: [[CalendarEventRecommendationCandidate]] = [[], [], []]
        for candidate in candidates where candidate.recommendation.eventID != excludingEventID {
            if candidate.normalizedTitle == query { ranked[0].append(candidate) }
            else if candidate.normalizedTitle.hasPrefix(query) { ranked[1].append(candidate) }
            else if allowsContains && candidate.normalizedTitle.contains(query) { ranked[2].append(candidate) }
        }

        var seenSettings: Set<RecommendationSettingsKey> = []
        var result: [CalendarEventRecommendation] = []
        for candidate in ranked.joined() {
            let recommendation = candidate.recommendation
            let key = RecommendationSettingsKey(
                title: candidate.normalizedTitle,
                includedDayCount: recommendation.includedDayCount,
                note: recommendation.note,
                color: recommendation.color
            )
            guard seenSettings.insert(key).inserted else { continue }
            result.append(recommendation)
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
            title: recommendation.title,
            startAt: normalizedStart,
            endAt: DayKey.addingDays(
                max(1, recommendation.includedDayCount) - 1,
                to: normalizedStart
            ),
            note: normalizedOptionalText(draft.note) == nil
                ? (normalizedOptionalText(recommendation.note) ?? draft.note)
                : draft.note,
            color: effectiveColor(recommendation.color),
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

    static func normalizedOptionalText(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func effectiveColor(_ value: String?) -> String {
        CalendarEventColor(rawValue: value ?? "")?.rawValue ?? CalendarEventPalette.defaultColor
    }

    private struct RecommendationSettingsKey: Hashable {
        var title: String
        var includedDayCount: Int
        var note: String?
        var color: String?
    }
}
