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
    @Environment(\.colorScheme) private var colorScheme
    let entry: EasyTaskCalendarEntry

    private var theme: CalendarWidgetTheme {
        CalendarWidgetTheme(
            themeID: entry.snapshot.themeID,
            colorScheme: colorScheme
        )
    }

    private var contentPadding: CGFloat {
        family == .systemSmall ? 14 : 12
    }

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                LargeMonthCalendarWidget(entry: entry, theme: theme)
            case .systemMedium:
                MonthCalendarWidget(entry: entry, theme: theme)
            default:
                TodayCalendarWidget(entry: entry, theme: theme)
            }
        }
        .padding(contentPadding)
        .containerBackground(for: .widget) {
            theme.background
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
}

private struct TodayCalendarWidget: View {
    let entry: EasyTaskCalendarEntry
    let theme: CalendarWidgetTheme

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
                    .foregroundStyle(theme.primaryText)

                Text(entry.date, format: .dateTime.month(.wide).weekday(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if events.isEmpty {
                Spacer(minLength: 0)
                Label("등록된 이벤트 없음", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(events) { event in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(theme.eventColor(event.colorID))
                                .frame(width: 7, height: 7)

                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.primaryText)
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
    let theme: CalendarWidgetTheme

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
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 0)

                Text("PlanBase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
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
                                events: entry.snapshot.events(onDayKey: DayKey.key(for: date)),
                                theme: theme
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
        case 0: theme.sundayText
        default: theme.secondaryText
        }
    }
}

private struct MonthDayCell: View {
    let date: Date
    let visibleMonth: Date
    let events: [CalendarWidgetEventSnapshot]
    let theme: CalendarWidgetTheme

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
                        Circle().fill(theme.accent)
                    }
                }

            HStack(spacing: 2) {
                ForEach(Array(events.prefix(2))) { event in
                    Circle()
                        .fill(theme.eventColor(event.colorID))
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
            return theme.accentForeground
        }
        guard DayKey.isSameMonth(date, visibleMonth) else {
            return theme.secondaryText.opacity(0.42)
        }
        return weekday == 1 ? theme.sundayText : theme.primaryText
    }

    private var dayAccessibilityLabel: String {
        let eventText = events.isEmpty ? "이벤트 없음" : "이벤트 \(events.count)개"
        return "\(DayKey.display(date)), \(eventText)"
    }
}

private struct LargeMonthCalendarWidget: View {
    let entry: EasyTaskCalendarEntry
    let theme: CalendarWidgetTheme

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 32), spacing: 2),
        count: 7
    )

    private var month: Date {
        DayKey.startOfMonth(for: entry.date)
    }

    private var dates: [Date] {
        DayKey.monthGridDates(for: month)
    }

    private var monthEventCount: Int {
        let startKey = DayKey.key(for: month)
        let endKey = DayKey.key(
            for: DayKey.addingDays(-1, to: DayKey.addingMonths(1, to: month))
        )
        return entry.snapshot.events.filter {
            $0.startDayKey <= endKey && $0.endDayKey >= startKey
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DayKey.monthTitle(month))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 0)

                Text("이벤트 \(monthEventCount)개")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 2) {
                ForEach(Array(DayKey.weekdaySymbols().enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(index == 0 ? theme.sundayText : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            GeometryReader { proxy in
                let rowHeight = max(34, (proxy.size.height - 10) / 6)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(dates, id: \.self) { date in
                        if let url = EasyTaskDeepLink.calendarURL(dayKey: DayKey.key(for: date)) {
                            Link(destination: url) {
                                LargeMonthDayCell(
                                    date: date,
                                    visibleMonth: month,
                                    events: entry.snapshot.events(onDayKey: DayKey.key(for: date)),
                                    theme: theme
                                )
                                .frame(height: rowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct LargeMonthDayCell: View {
    let date: Date
    let visibleMonth: Date
    let events: [CalendarWidgetEventSnapshot]
    let theme: CalendarWidgetTheme

    private var isInVisibleMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var visibleEvents: [CalendarWidgetEventSnapshot] {
        guard isInVisibleMonth else { return [] }
        return Array(events.prefix(2))
    }

    private var weekday: Int {
        DayKey.calendar.component(.weekday, from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(DayKey.dayNumber(date))
                    .font(.system(size: 10, weight: DayKey.isToday(date) ? .bold : .semibold))
                    .foregroundStyle(dayForeground)
                    .frame(width: 17, height: 17)
                    .background {
                        if DayKey.isToday(date) {
                            Circle().fill(theme.accent)
                        }
                    }

                Spacer(minLength: 0)

                if isInVisibleMonth && events.count > visibleEvents.count {
                    Text("+\(events.count - visibleEvents.count)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            ForEach(visibleEvents) { event in
                Text(event.title)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(theme.eventForeground(event.colorID))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, minHeight: 11, maxHeight: 11, alignment: .leading)
                    .background(theme.eventColor(event.colorID), in: RoundedRectangle(cornerRadius: 2))
                    .privacySensitive()
            }

            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 3))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .stroke(theme.border.opacity(isInVisibleMonth ? 0.55 : 0.2), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel)
    }

    private var dayForeground: Color {
        if DayKey.isToday(date) {
            return theme.accentForeground
        }
        guard isInVisibleMonth else {
            return theme.secondaryText.opacity(0.38)
        }
        return weekday == 1 ? theme.sundayText : theme.primaryText
    }

    private var cellBackground: Color {
        isInVisibleMonth ? theme.panel.opacity(0.76) : theme.input.opacity(0.24)
    }

    private var dayAccessibilityLabel: String {
        guard isInVisibleMonth, !events.isEmpty else {
            return "\(DayKey.display(date)), 이벤트 없음"
        }
        return "\(DayKey.display(date)), 이벤트 \(events.count)개, \(events.map(\.title).joined(separator: ", "))"
    }
}

private struct CalendarWidgetTheme {
    let colors: AppThemeColorSet

    init(themeID: String?, colorScheme: ColorScheme) {
        colors = AppThemePreset
            .preset(for: themeID)
            .colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var background: LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var primaryText: Color { colors.primaryText.color }
    var secondaryText: Color { colors.secondaryText.color }
    var panel: Color { colors.panel.color }
    var input: Color { colors.input.color }
    var border: Color { colors.border.color }
    var accent: Color { colors.event.color }
    var accentForeground: Color { readableForeground(on: colors.event) }
    var sundayText: Color { eventToken(CalendarEventColor.red.rawValue).color }

    func eventColor(_ colorID: String) -> Color {
        eventToken(colorID).color
    }

    func eventForeground(_ colorID: String) -> Color {
        readableForeground(on: eventToken(colorID))
    }

    private func eventToken(_ colorID: String) -> ThemeColorToken {
        let index = CalendarEventColor(rawValue: colorID)?.paletteIndex ?? 0
        guard colors.eventPalette.indices.contains(index) else {
            return colors.event
        }
        return colors.eventPalette[index]
    }

    private func readableForeground(on background: ThemeColorToken) -> Color {
        let black = ThemeColorToken(hex: "#000000")
        let white = ThemeColorToken(hex: "#FFFFFF")
        let candidates = [colors.eventText, colors.primaryText, black, white]
        let token = candidates.first {
            $0.contrastRatio(to: background) >= 4.5
        } ?? candidates.max {
            $0.contrastRatio(to: background) < $1.contrastRatio(to: background)
        } ?? white
        return token.color
    }
}

private extension CalendarWidgetSnapshot {
    static func empty(at date: Date) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(
            generatedAt: date,
            themeID: AppThemePreset.defaultID,
            events: []
        )
    }

    static var preview: CalendarWidgetSnapshot {
        let today = Date()
        let todayKey = DayKey.key(for: today)
        let tomorrowKey = DayKey.key(for: DayKey.addingDays(1, to: today))
        return CalendarWidgetSnapshot(
            generatedAt: today,
            themeID: "roseLilac",
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
        .description("오늘의 이벤트와 월간 일정을 앱 테마로 홈 화면에서 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct EasyTaskWidgetBundle: WidgetBundle {
    var body: some Widget {
        EasyTaskCalendarWidget()
    }
}
