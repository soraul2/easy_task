import PlanBaseCore
import SwiftData
import SwiftUI

struct DesktopCalendarQueryRange: Hashable {
    let startDayKey: String
    let endDayKey: String

    init(visibleMonth: Date) {
        let dates = DayKey.monthGridDates(for: visibleMonth)
        let fallbackDayKey = DayKey.key(for: visibleMonth)
        startDayKey = dates.first.map(DayKey.key(for:)) ?? fallbackDayKey
        endDayKey = dates.last.map(DayKey.key(for:)) ?? fallbackDayKey
    }
}

struct DesktopCalendarMonthQueryHost<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @State private var events: [CalendarEvent] = []
    @Query private var templatePlacements: [TemplatePlacement]
    private let range: DesktopCalendarQueryRange
    private let content: ([CalendarEvent], [TemplatePlacement]) -> Content

    init(
        range: DesktopCalendarQueryRange,
        @ViewBuilder content: @escaping ([CalendarEvent], [TemplatePlacement]) -> Content
    ) {
        self.range = range
        _templatePlacements = Query(BoundedQueryService.templatePlacementsDescriptor(
            from: range.startDayKey,
            through: range.endDayKey
        ))
        self.content = content
    }

    var body: some View {
        content(events.filter { $0.modelContext != nil }, templatePlacements)
            .refreshVisibleData(key: "\(range.startDayKey):\(range.endDayKey)", domains: .calendar) {
                events = try BoundedQueryService.events(
                    overlappingStartDayKey: range.startDayKey, endDayKey: range.endDayKey,
                    in: modelContext)
            }
    }
}
