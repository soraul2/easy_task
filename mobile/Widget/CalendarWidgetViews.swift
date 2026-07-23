import AppIntents
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

struct PlanBaseCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: PlanBaseCalendarEntry

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
            if entry.availability == .available {
                switch family {
                case .systemLarge:
                    LargeMonthCalendarWidget(entry: entry, theme: theme)
                case .systemMedium:
                    MonthCalendarWidget(entry: entry, theme: theme)
                default:
                    TodayCalendarWidget(entry: entry, theme: theme)
                }
            } else {
                CalendarWidgetUnavailableView(entry: entry, theme: theme)
            }
        }
        .padding(contentPadding)
        .containerBackground(for: .widget) {
            theme.background
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
}

private struct CalendarWidgetUnavailableView: View {
    let entry: PlanBaseCalendarEntry
    let theme: CalendarWidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.accent)

            Text(entry.availability.calendarMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .widgetURL(PlanBaseDeepLink.calendarURL(dayKey: DayKey.key(for: entry.date)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.availability.calendarMessage)
    }
}

private struct TodayCalendarWidget: View {
    let entry: PlanBaseCalendarEntry
    let theme: CalendarWidgetTheme

    private var dayKey: String {
        DayKey.key(for: entry.date)
    }

    private var allEvents: [CalendarWidgetEventSnapshot] {
        entry.snapshot.events(onDayKey: dayKey)
    }

    private var events: [CalendarWidgetEventSnapshot] {
        Array(allEvents.prefix(4))
    }

    private var hiddenEventCount: Int {
        max(0, entry.snapshot.totalEventCount(onDayKey: dayKey) - events.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, format: .dateTime.day())
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(entry.date, format: .dateTime.month(.wide).weekday(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if hiddenEventCount > 0 {
                    Text("+\(hiddenEventCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accentForeground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.accent, in: Capsule())
                }
            }

            if events.isEmpty {
                Spacer(minLength: 0)
                Label("오늘 일정이 없어요", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(events, id: \.renderID) { event in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(theme.eventColor(event.colorID))
                                .frame(width: 7, height: 7)

                            Text(event.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(PlanBaseDeepLink.calendarURL(dayKey: dayKey))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todayAccessibilityLabel)
    }

    private var todayAccessibilityLabel: String {
        guard !events.isEmpty else {
            return "\(DayKey.display(entry.date)), 오늘 일정이 없어요"
        }
        let totalCount = entry.snapshot.totalEventCount(onDayKey: dayKey)
        let overflowText = hiddenEventCount > 0 ? ", 외 \(hiddenEventCount)개" : ""
        return "\(DayKey.display(entry.date)), 이벤트 \(totalCount)개, \(events.map(\.title).joined(separator: ", "))\(overflowText)"
    }
}

private struct MonthCalendarWidget: View {
    let entry: PlanBaseCalendarEntry
    let theme: CalendarWidgetTheme

    private var month: Date {
        entry.monthSelection.month
    }

    private var dates: [Date] {
        DayKey.adaptiveMonthGridDates(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            CalendarWidgetMonthHeader(
                monthSelection: entry.monthSelection,
                theme: theme,
                style: .compact
            )

            CalendarWidgetWeekdayHeader(theme: theme, style: .compact)
                .frame(height: 9)

            GeometryReader { proxy in
                CalendarWidgetMonthGrid(
                    snapshot: entry.snapshot,
                    month: month,
                    dates: dates,
                    theme: theme,
                    style: .compact,
                    size: proxy.size
                )
            }
        }
    }
}

private struct LargeMonthCalendarWidget: View {
    let entry: PlanBaseCalendarEntry
    let theme: CalendarWidgetTheme

    private var month: Date {
        entry.monthSelection.month
    }

    private var dates: [Date] {
        DayKey.adaptiveMonthGridDates(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CalendarWidgetMonthHeader(
                monthSelection: entry.monthSelection,
                theme: theme,
                style: .expanded
            )

            CalendarWidgetWeekdayHeader(theme: theme, style: .expanded)
                .frame(height: 14)

            GeometryReader { proxy in
                CalendarWidgetMonthGrid(
                    snapshot: entry.snapshot,
                    month: month,
                    dates: dates,
                    theme: theme,
                    style: .expanded,
                    size: proxy.size
                )
            }
        }
    }
}

private struct CalendarWidgetMonthHeader: View {
    let monthSelection: CalendarWidgetMonthSelection
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle

    var body: some View {
        HStack(spacing: 2) {
            Button(intent: ResetCalendarWidgetMonthIntent()) {
                Text(DayKey.monthTitle(monthSelection.month))
                    .font(.system(size: style.monthHeaderFontSize, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이번 달로 이동")

            Spacer(minLength: 4)

            monthButton(
                systemName: "chevron.left",
                label: "이전 달",
                delta: -1,
                isEnabled: monthSelection.canMoveBackward
            )
            monthButton(
                systemName: "chevron.right",
                label: "다음 달",
                delta: 1,
                isEnabled: monthSelection.canMoveForward
            )
        }
        .frame(height: style.monthHeaderHeight)
    }

    @ViewBuilder
    private func monthButton(
        systemName: String,
        label: String,
        delta: Int,
        isEnabled: Bool
    ) -> some View {
        Button(intent: ChangeCalendarWidgetMonthIntent(monthDelta: delta)) {
            Image(systemName: systemName)
                .font(.system(
                    size: style.monthControlFontSize,
                    weight: .semibold
                ))
                .foregroundStyle(
                    theme.secondaryText.opacity(isEnabled ? 1 : 0.28)
                )
                .frame(
                    width: style.monthControlWidth,
                    height: style.monthHeaderHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

private enum CalendarWidgetMonthGridStyle: Equatable {
    case compact
    case expanded

    var monthHeaderFontSize: CGFloat {
        switch self {
        case .compact: 11
        case .expanded: 12
        }
    }

    var monthHeaderHeight: CGFloat {
        switch self {
        case .compact: 14
        case .expanded: 16
        }
    }

    var monthControlFontSize: CGFloat {
        switch self {
        case .compact: 9
        case .expanded: 10
        }
    }

    var monthControlWidth: CGFloat {
        switch self {
        case .compact: 22
        case .expanded: 24
        }
    }

    var dayFontSize: CGFloat {
        switch self {
        case .compact: 8
        case .expanded: 9
        }
    }

    var dayBadgeSize: CGFloat {
        switch self {
        case .compact: 10
        case .expanded: 14
        }
    }

    var eventTopInset: CGFloat {
        switch self {
        case .compact: 10
        case .expanded: 15
        }
    }

    var laneHeight: CGFloat {
        switch self {
        case .compact: 3
        case .expanded: 8.5
        }
    }

    var barHeight: CGFloat {
        switch self {
        case .compact: 2
        case .expanded: 8
        }
    }

    var maximumLaneLimit: Int {
        switch self {
        case .compact: 3
        case .expanded: 5
        }
    }
}

private struct CalendarWidgetWeekdayHeader: View {
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(DayKey.weekdaySymbols().enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(
                        size: style == .compact ? 7 : 9,
                        weight: .semibold
                    ))
                    .foregroundStyle(index == 0 ? theme.sundayText : theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.panel.opacity(0.55))
                    .overlay(alignment: .trailing) {
                        if index < 6 {
                            Rectangle()
                                .fill(theme.border.opacity(0.45))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border.opacity(0.6))
                .frame(height: 0.5)
        }
    }
}

private struct CalendarWidgetMonthGrid: View {
    let snapshot: CalendarWidgetSnapshot
    let month: Date
    let dates: [Date]
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle
    let size: CGSize

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 0),
        count: 7
    )

    var body: some View {
        let rowCount = max(1, dates.count / 7)
        let cellWidth = size.width / 7
        let rowHeight = size.height / CGFloat(rowCount)
        let lastLaneOffset = rowHeight - style.eventTopInset - style.barHeight
        let fittingLaneCount = lastLaneOffset < 0
            ? 0
            : Int(lastLaneOffset / style.laneHeight) + 1
        let maximumLanes = min(style.maximumLaneLimit, fittingLaneCount)
        let eventsByRenderID = Dictionary(
            snapshot.events.map { ($0.renderID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let layout = CalendarEventGridLayout.make(
            items: snapshot.events.map {
                CalendarEventGridLayoutItem(
                    renderID: $0.renderID,
                    eventID: $0.id,
                    title: $0.title,
                    startDayKey: $0.startDayKey,
                    endDayKey: $0.endDayKey
                )
            },
            dates: dates,
            visibleMonth: month,
            maximumLanes: maximumLanes,
            totalEventCountsByDayKey: snapshot.eventCountsByDayKey
        )

        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                    if let url = PlanBaseDeepLink.calendarURL(dayKey: DayKey.key(for: date)) {
                        Link(destination: url) {
                            CalendarWidgetMonthDayCell(
                                date: date,
                                visibleMonth: month,
                                events: snapshot.events(onDayKey: DayKey.key(for: date)),
                                totalEventCount: snapshot.totalEventCount(
                                    onDayKey: DayKey.key(for: date)
                                ),
                                hiddenEventCount: layout.hiddenEventCountByDayKey[
                                    DayKey.key(for: date)
                                ] ?? 0,
                                showsTrailingDivider: (index + 1) % 7 != 0,
                                showsBottomDivider: index < dates.count - 7,
                                theme: theme,
                                style: style
                            )
                            .frame(height: rowHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(layout.segments) { segment in
                if let event = eventsByRenderID[segment.renderID] {
                    CalendarWidgetEventBar(
                        event: event,
                        isDimmed: segment.isDimmed,
                        theme: theme,
                        style: style
                    )
                    .frame(
                        width: max(1, cellWidth * CGFloat(segment.span) - 2),
                        height: style.barHeight
                    )
                    .offset(
                        x: cellWidth * CGFloat(segment.startColumn) + 1,
                        y: rowHeight * CGFloat(segment.weekIndex)
                            + style.eventTopInset
                            + style.laneHeight * CGFloat(segment.lane)
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay {
            Rectangle()
                .stroke(theme.border.opacity(0.6), lineWidth: 0.5)
        }
        .clipped()
    }
}

private struct CalendarWidgetMonthDayCell: View {
    let date: Date
    let visibleMonth: Date
    let events: [CalendarWidgetEventSnapshot]
    let totalEventCount: Int
    let hiddenEventCount: Int
    let showsTrailingDivider: Bool
    let showsBottomDivider: Bool
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle

    private var isInVisibleMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var weekday: Int {
        DayKey.calendar.component(.weekday, from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                Text(DayKey.dayNumber(date))
                    .font(.system(
                        size: style.dayFontSize,
                        weight: DayKey.isToday(date) ? .bold : .medium
                    ))
                    .foregroundStyle(dayForeground)
                    .frame(width: style.dayBadgeSize, height: style.dayBadgeSize)
                    .background {
                        if DayKey.isToday(date) {
                            Circle().fill(theme.accent)
                        }
                    }

                Spacer(minLength: 0)

                if hiddenEventCount > 0 {
                    Text("+\(hiddenEventCount)")
                        .font(.system(
                            size: style == .compact ? 6 : 7,
                            weight: .bold
                        ))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, style == .compact ? 1 : 2)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cellBackground)
        .overlay(alignment: .trailing) {
            if showsTrailingDivider {
                Rectangle()
                    .fill(theme.border.opacity(0.5))
                    .frame(width: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(theme.border.opacity(0.5))
                    .frame(height: 0.5)
            }
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
        isInVisibleMonth ? theme.panel.opacity(0.66) : theme.input.opacity(0.25)
    }

    private var dayAccessibilityLabel: String {
        guard totalEventCount > 0 else {
            return "\(DayKey.display(date)), 이벤트 없음"
        }
        let titleText = events.prefix(3).map(\.title).joined(separator: ", ")
        let hiddenText = hiddenEventCount > 0 ? ", 외 \(hiddenEventCount)개" : ""
        guard !titleText.isEmpty else {
            return "\(DayKey.display(date)), 이벤트 \(totalEventCount)개\(hiddenText)"
        }
        return "\(DayKey.display(date)), 이벤트 \(totalEventCount)개, \(titleText)\(hiddenText)"
    }
}

private struct CalendarWidgetEventBar: View {
    let event: CalendarWidgetEventSnapshot
    let isDimmed: Bool
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle

    var body: some View {
        Group {
            switch style {
            case .compact:
                Capsule()
                    .fill(theme.eventColor(event.colorID))
            case .expanded:
                Text(event.title)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(theme.eventForeground(event.colorID))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        theme.eventColor(event.colorID),
                        in: RoundedRectangle(cornerRadius: 2)
                    )
                    .privacySensitive()
            }
        }
        .opacity(isDimmed ? 0.42 : 1)
    }
}
