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
    @Query private var events: [CalendarEvent]
    @Query private var templatePlacements: [TemplatePlacement]
    private let content: ([CalendarEvent], [TemplatePlacement]) -> Content

    init(
        range: DesktopCalendarQueryRange,
        @ViewBuilder content: @escaping ([CalendarEvent], [TemplatePlacement]) -> Content
    ) {
        _events = Query(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: range.startDayKey,
            endDayKey: range.endDayKey
        ))
        _templatePlacements = Query(BoundedQueryService.templatePlacementsDescriptor(
            from: range.startDayKey,
            through: range.endDayKey
        ))
        self.content = content
    }

    var body: some View {
        content(events, templatePlacements)
    }
}
