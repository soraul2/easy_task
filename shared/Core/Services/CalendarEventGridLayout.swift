import Foundation

public struct CalendarEventGridLayoutItem: Equatable, Hashable, Sendable {
    public let renderID: UUID
    public let eventID: UUID
    public let title: String
    public let startDayKey: String
    public let endDayKey: String
    public let updatedAt: Date?

    public init(
        renderID: UUID,
        eventID: UUID,
        title: String,
        startDayKey: String,
        endDayKey: String,
        updatedAt: Date? = nil
    ) {
        self.renderID = renderID
        self.eventID = eventID
        self.title = title
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.updatedAt = updatedAt
    }
}

public struct CalendarEventGridSegment: Equatable, Identifiable, Sendable {
    public let renderID: UUID
    public let eventID: UUID
    public let weekIndex: Int
    public let startColumn: Int
    public let span: Int
    public let lane: Int
    public let isDimmed: Bool

    public var id: String {
        "\(renderID.uuidString)-\(weekIndex)-\(startColumn)"
    }

    public init(
        renderID: UUID,
        eventID: UUID,
        weekIndex: Int,
        startColumn: Int,
        span: Int,
        lane: Int,
        isDimmed: Bool
    ) {
        self.renderID = renderID
        self.eventID = eventID
        self.weekIndex = weekIndex
        self.startColumn = startColumn
        self.span = span
        self.lane = lane
        self.isDimmed = isDimmed
    }
}

public struct CalendarEventGridLayoutResult: Equatable, Sendable {
    public let rowCount: Int
    public let segments: [CalendarEventGridSegment]
    public let displayedEventIDsByDayKey: [String: Set<UUID>]
    public let hiddenEventCountByDayKey: [String: Int]

    public init(
        rowCount: Int,
        segments: [CalendarEventGridSegment],
        displayedEventIDsByDayKey: [String: Set<UUID>],
        hiddenEventCountByDayKey: [String: Int]
    ) {
        self.rowCount = rowCount
        self.segments = segments
        self.displayedEventIDsByDayKey = displayedEventIDsByDayKey
        self.hiddenEventCountByDayKey = hiddenEventCountByDayKey
    }
}

public enum CalendarEventGridLayout {
    public static func make(
        items: [CalendarEventGridLayoutItem],
        dates: [Date],
        visibleMonth: Date,
        maximumLanes: Int,
        totalEventCountsByDayKey: [String: Int] = [:]
    ) -> CalendarEventGridLayoutResult {
        let maximumLanes = max(0, maximumLanes)
        let rowCount = dates.count / 7
        guard !dates.isEmpty, dates.count.isMultiple(of: 7) else {
            return CalendarEventGridLayoutResult(
                rowCount: 0,
                segments: [],
                displayedEventIDsByDayKey: [:],
                hiddenEventCountByDayKey: [:]
            )
        }

        let validItems = representativeItems(
            from: items.filter {
                DayKey.date(from: $0.startDayKey) != nil
                    && DayKey.date(from: $0.endDayKey) != nil
                    && $0.startDayKey <= $0.endDayKey
            }
        )
        .sorted(by: itemSort)
        let monthStartKey = DayKey.key(for: DayKey.startOfMonth(for: visibleMonth))
        let nextMonthStartKey = DayKey.key(
            for: DayKey.addingMonths(1, to: DayKey.startOfMonth(for: visibleMonth))
        )
        let dayKeys = dates.map(DayKey.key(for:))
        var segments: [CalendarEventGridSegment] = []
        var displayedEventIDsByDayKey: [String: Set<UUID>] = [:]

        for weekIndex in 0..<rowCount {
            let startOffset = weekIndex * 7
            let weekKeys = Array(dayKeys[startOffset..<(startOffset + 7)])
            guard let weekStartKey = weekKeys.first,
                  let weekEndKey = weekKeys.last else {
                continue
            }

            let overlappingItems = validItems.filter {
                $0.startDayKey <= weekEndKey && $0.endDayKey >= weekStartKey
            }
            var laneEndColumns: [Int] = []

            for item in overlappingItems {
                let segmentStartKey = max(item.startDayKey, weekStartKey)
                let segmentEndKey = min(item.endDayKey, weekEndKey)
                guard let startColumn = weekKeys.firstIndex(of: segmentStartKey),
                      let endColumn = weekKeys.firstIndex(of: segmentEndKey) else {
                    continue
                }

                let lane: Int
                if let availableLane = laneEndColumns.firstIndex(where: { $0 < startColumn }) {
                    lane = availableLane
                    laneEndColumns[availableLane] = endColumn
                } else if laneEndColumns.count < maximumLanes {
                    lane = laneEndColumns.count
                    laneEndColumns.append(endColumn)
                } else {
                    continue
                }

                segments.append(CalendarEventGridSegment(
                    renderID: item.renderID,
                    eventID: item.eventID,
                    weekIndex: weekIndex,
                    startColumn: startColumn,
                    span: endColumn - startColumn + 1,
                    lane: lane,
                    isDimmed: segmentEndKey < monthStartKey
                        || segmentStartKey >= nextMonthStartKey
                ))

                for column in startColumn...endColumn {
                    displayedEventIDsByDayKey[weekKeys[column], default: []]
                        .insert(item.eventID)
                }
            }
        }

        var allEventIDsByDayKey: [String: Set<UUID>] = [:]
        for dayKey in dayKeys {
            for item in validItems
            where item.startDayKey <= dayKey && dayKey <= item.endDayKey {
                allEventIDsByDayKey[dayKey, default: []].insert(item.eventID)
            }
        }

        var hiddenEventCountByDayKey: [String: Int] = [:]
        for dayKey in dayKeys {
            let totalCount = max(
                totalEventCountsByDayKey[dayKey] ?? 0,
                allEventIDsByDayKey[dayKey]?.count ?? 0
            )
            let displayedCount = displayedEventIDsByDayKey[dayKey]?.count ?? 0
            let hiddenCount = max(0, totalCount - displayedCount)
            if hiddenCount > 0 {
                hiddenEventCountByDayKey[dayKey] = hiddenCount
            }
        }

        return CalendarEventGridLayoutResult(
            rowCount: rowCount,
            segments: segments,
            displayedEventIDsByDayKey: displayedEventIDsByDayKey,
            hiddenEventCountByDayKey: hiddenEventCountByDayKey
        )
    }

    private static func itemSort(
        _ lhs: CalendarEventGridLayoutItem,
        _ rhs: CalendarEventGridLayoutItem
    ) -> Bool {
        if lhs.startDayKey != rhs.startDayKey {
            return lhs.startDayKey < rhs.startDayKey
        }
        if lhs.endDayKey != rhs.endDayKey {
            return lhs.endDayKey > rhs.endDayKey
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        if lhs.eventID != rhs.eventID {
            return lhs.eventID.uuidString < rhs.eventID.uuidString
        }
        return lhs.renderID.uuidString < rhs.renderID.uuidString
    }

    private static func representativeItems(
        from items: [CalendarEventGridLayoutItem]
    ) -> [CalendarEventGridLayoutItem] {
        Dictionary(grouping: items, by: \.eventID).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                let lhsUpdatedAt = lhs.updatedAt ?? .distantPast
                let rhsUpdatedAt = rhs.updatedAt ?? .distantPast
                if lhsUpdatedAt != rhsUpdatedAt {
                    return lhsUpdatedAt < rhsUpdatedAt
                }
                return lhs.renderID.uuidString < rhs.renderID.uuidString
            }
        }
    }
}
