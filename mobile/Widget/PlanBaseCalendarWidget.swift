import PlanBaseCore
import SwiftUI
import WidgetKit

struct PlanBaseCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.kind,
            provider: PlanBaseCalendarProvider()
        ) { entry in
            PlanBaseCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("PlanBase 캘린더")
        .description("오늘의 이벤트와 월간 일정을 앱 테마로 홈 화면에서 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#if DEBUG
private struct PlanBaseCalendarWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            PlanBaseCalendarWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Small · 오늘")
            PlanBaseCalendarWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Medium · 월간 막대")
            PlanBaseCalendarWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("Large · 월간 제목")
            PlanBaseCalendarWidgetView(entry: refreshEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Small · 갱신 필요")
        }
    }

    private static let previewDate = Date()
    private static let previewSnapshot = CalendarWidgetSnapshot.preview

    private static let availableEntry = PlanBaseCalendarEntry(
        date: previewDate,
        snapshot: previewSnapshot,
        availability: .available,
        monthSelection: CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: nil,
            snapshot: previewSnapshot,
            referenceDate: previewDate
        )
    )

    private static let refreshEntry = PlanBaseCalendarEntry(
        date: previewDate,
        snapshot: .empty(at: previewDate),
        availability: .missing,
        monthSelection: CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: nil,
            snapshot: .empty(at: previewDate),
            referenceDate: previewDate
        )
    )
}
#endif
