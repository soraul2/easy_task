import EasyTaskCore
import SwiftUI
import WidgetKit

private struct EasyTaskCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
}

private struct EasyTaskCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> EasyTaskCalendarEntry {
        EasyTaskCalendarEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (EasyTaskCalendarEntry) -> Void
    ) {
        completion(entry(at: Date(), usesPreviewData: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<EasyTaskCalendarEntry>) -> Void
    ) {
        let now = Date()
        let entry = entry(at: now, usesPreviewData: false)
        let nextDay = DayKey.addingDays(1, to: DayKey.startOfDay(for: now))
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }

    private func entry(at date: Date, usesPreviewData: Bool) -> EasyTaskCalendarEntry {
        let snapshot: CalendarWidgetSnapshot
        if usesPreviewData {
            snapshot = .preview
        } else {
            snapshot = (try? CalendarWidgetSnapshotStore.read()) ?? .empty(at: date)
        }
        return EasyTaskCalendarEntry(date: date, snapshot: snapshot)
    }
}

private struct EasyTaskCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EasyTaskCalendarEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                MonthCalendarWidget(entry: entry)
            default:
                TodayCalendarWidget(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            Color(.secondarySystemBackground)
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
}

private struct TodayCalendarWidget: View {
    let entry: EasyTaskCalendarEntry

    private var dayKey: String {
        DayKey.key(for: entry.date)
    }

    private var events: [CalendarWidgetEventSnapshot] {
        Array(entry.snapshot.events(onDayKey: dayKey).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, format: .dateTime.day())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(entry.date, format: .dateTime.month(.wide).weekday(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if events.isEmpty {
                Spacer(minLength: 0)
                Label("등록된 이벤트 없음", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(events) { event in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(eventColor(event.colorID))
                                .frame(width: 7, height: 7)

                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(EasyTaskDeepLink.calendarURL(dayKey: dayKey))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todayAccessibilityLabel)
    }

    private var todayAccessibilityLabel: String {
        guard !events.isEmpty else {
            return "\(DayKey.display(entry.date)), 등록된 이벤트 없음"
        }
        return "\(DayKey.display(entry.date)), 이벤트 \(events.count)개, \(events.map(\.title).joined(separator: ", "))"
    }
}

private struct MonthCalendarWidget: View {
    let entry: EasyTaskCalendarEntry

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 18), spacing: 2),
        count: 7
    )

    private var month: Date {
        DayKey.startOfMonth(for: entry.date)
    }

    private var dates: [Date] {
        DayKey.monthGridDates(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(DayKey.monthTitle(month))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("PlanBase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(DayKey.weekdaySymbols().enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(weekdayColor(for: index))
                        .frame(maxWidth: .infinity)
                }

                ForEach(dates, id: \.self) { date in
                    if let url = EasyTaskDeepLink.calendarURL(dayKey: DayKey.key(for: date)) {
                        Link(destination: url) {
                            MonthDayCell(
                                date: date,
                                visibleMonth: month,
                                events: entry.snapshot.events(onDayKey: DayKey.key(for: date))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func weekdayColor(for index: Int) -> Color {
        switch index {
        case 0: .red
        case 6: .secondary
        default: .secondary
        }
    }
}

private struct MonthDayCell: View {
    let date: Date
    let visibleMonth: Date
    let events: [CalendarWidgetEventSnapshot]

    private var weekday: Int {
        DayKey.calendar.component(.weekday, from: date)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(DayKey.dayNumber(date))
                .font(.system(size: 9, weight: DayKey.isToday(date) ? .bold : .medium))
                .foregroundStyle(dayForegroundStyle)
                .frame(width: 16, height: 12)
                .background {
                    if DayKey.isToday(date) {
                        Circle().fill(Color.accentColor)
                    }
                }

            HStack(spacing: 2) {
                ForEach(Array(events.prefix(2))) { event in
                    Circle()
                        .fill(eventColor(event.colorID))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel)
    }

    private var dayForegroundStyle: Color {
        if DayKey.isToday(date) {
            return .white
        }
        guard DayKey.isSameMonth(date, visibleMonth) else {
            return Color.secondary.opacity(0.45)
        }
        return weekday == 1 ? .red : .primary
    }

    private var dayAccessibilityLabel: String {
        let eventText = events.isEmpty ? "이벤트 없음" : "이벤트 \(events.count)개"
        return "\(DayKey.display(date)), \(eventText)"
    }
}

private func eventColor(_ colorID: String) -> Color {
    switch CalendarEventColor(rawValue: colorID) {
    case .red: .red
    case .green: .green
    case .purple: .purple
    case .orange: .orange
    case .teal: .teal
    case .blue, .none: .blue
    }
}

private extension CalendarWidgetSnapshot {
    static func empty(at date: Date) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(generatedAt: date, events: [])
    }

    static var preview: CalendarWidgetSnapshot {
        let today = Date()
        let todayKey = DayKey.key(for: today)
        let tomorrowKey = DayKey.key(for: DayKey.addingDays(1, to: today))
        return CalendarWidgetSnapshot(
            generatedAt: today,
            events: [
                CalendarWidgetEventSnapshot(
                    id: UUID(),
                    title: "프로젝트 정리",
                    startDayKey: todayKey,
                    endDayKey: todayKey,
                    colorID: CalendarEventColor.blue.rawValue
                ),
                CalendarWidgetEventSnapshot(
                    id: UUID(),
                    title: "운동 루틴",
                    startDayKey: todayKey,
                    endDayKey: tomorrowKey,
                    colorID: CalendarEventColor.green.rawValue
                )
            ]
        )
    }
}

struct EasyTaskCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.kind,
            provider: EasyTaskCalendarProvider()
        ) { entry in
            EasyTaskCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("PlanBase 캘린더")
        .description("오늘의 이벤트 또는 월간 일정을 홈 화면에서 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EasyTaskWidgetBundle: WidgetBundle {
    var body: some Widget {
        EasyTaskCalendarWidget()
    }
}
