import AppIntents
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

private enum CalendarWidgetMonthSelectionStore {
    private static let selectedMonthDayKey = "calendarWidget.selectedMonthDayKey"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CalendarWidgetConstants.appGroupIdentifier)
    }

    static func selection(
        snapshot: CalendarWidgetSnapshot,
        referenceDate: Date
    ) -> CalendarWidgetMonthSelection {
        CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: defaults?.string(forKey: selectedMonthDayKey),
            snapshot: snapshot,
            referenceDate: referenceDate
        )
    }

    static func move(by monthDelta: Int, referenceDate: Date = Date()) {
        let snapshot = currentSnapshot(referenceDate: referenceDate)
        let selection = CalendarWidgetMonthNavigation.moving(
            selectedMonthDayKey: defaults?.string(forKey: selectedMonthDayKey),
            by: monthDelta,
            snapshot: snapshot,
            referenceDate: referenceDate
        )
        defaults?.set(DayKey.key(for: selection.month), forKey: selectedMonthDayKey)
    }

    static func reset() {
        defaults?.removeObject(forKey: selectedMonthDayKey)
    }

    private static func currentSnapshot(referenceDate: Date) -> CalendarWidgetSnapshot {
        do {
            return try CalendarWidgetSnapshotStore.read()
                ?? CalendarWidgetSnapshot(generatedAt: referenceDate, events: [])
        } catch {
            return CalendarWidgetSnapshot(generatedAt: referenceDate, events: [])
        }
    }
}

struct ChangeCalendarWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "캘린더 위젯 월 이동"
    static let description = IntentDescription("PlanBase 캘린더 위젯의 표시 월을 이동합니다.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "이동 방향")
    var monthDelta: Int

    init() {}

    init(monthDelta: Int) {
        self.monthDelta = monthDelta
    }

    func perform() async throws -> some IntentResult {
        CalendarWidgetMonthSelectionStore.move(by: monthDelta)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        return .result()
    }
}

struct ResetCalendarWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "이번 달 보기"
    static let description = IntentDescription("PlanBase 캘린더 위젯을 이번 달로 되돌립니다.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        CalendarWidgetMonthSelectionStore.reset()
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        return .result()
    }
}

private struct PlanBaseCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
    let availability: PlanBaseWidgetSnapshotAvailability
    let monthSelection: CalendarWidgetMonthSelection
}

private struct PlanBaseCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBaseCalendarEntry {
        let date = Date()
        let snapshot = CalendarWidgetSnapshot.preview
        return PlanBaseCalendarEntry(
            date: date,
            snapshot: snapshot,
            availability: .available,
            monthSelection: CalendarWidgetMonthNavigation.selection(
                selectedMonthDayKey: nil,
                snapshot: snapshot,
                referenceDate: date
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBaseCalendarEntry) -> Void
    ) {
        completion(entry(at: Date(), usesPreviewData: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PlanBaseCalendarEntry>) -> Void
    ) {
        let now = Date()
        let entry = entry(at: now, usesPreviewData: false)
        let nextDay = DayKey.addingDays(1, to: DayKey.startOfDay(for: now))
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }

    private func entry(at date: Date, usesPreviewData: Bool) -> PlanBaseCalendarEntry {
        if usesPreviewData {
            let snapshot = CalendarWidgetSnapshot.preview
            return makeEntry(
                date: date,
                snapshot: snapshot,
                availability: .available,
                usesStoredSelection: false
            )
        }

        do {
            guard let snapshot = try CalendarWidgetSnapshotStore.read() else {
                return makeEntry(
                    date: date,
                    snapshot: .empty(at: date),
                    availability: .missing
                )
            }
            let availability: PlanBaseWidgetSnapshotAvailability = snapshot.covers(
                dayKey: DayKey.key(for: date)
            ) ? .available : .staleCoverage
            return makeEntry(
                date: date,
                snapshot: snapshot,
                availability: availability
            )
        } catch CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .unsupportedNewerSchema
            )
        } catch is DecodingError {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .corrupt
            )
        } catch {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .corrupt
            )
        }
    }

    private func makeEntry(
        date: Date,
        snapshot: CalendarWidgetSnapshot,
        availability: PlanBaseWidgetSnapshotAvailability,
        usesStoredSelection: Bool = true
    ) -> PlanBaseCalendarEntry {
        let monthSelection = usesStoredSelection
            ? CalendarWidgetMonthSelectionStore.selection(
                snapshot: snapshot,
                referenceDate: date
            )
            : CalendarWidgetMonthNavigation.selection(
                selectedMonthDayKey: nil,
                snapshot: snapshot,
                referenceDate: date
            )
        return PlanBaseCalendarEntry(
            date: date,
            snapshot: snapshot,
            availability: availability,
            monthSelection: monthSelection
        )
    }
}

private struct PlanBaseCalendarWidgetView: View {
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
                .frame(height: 13)

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
                .frame(height: 15)

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
        11
    }

    var dayBadgeSize: CGFloat {
        switch self {
        case .compact: 14
        case .expanded: 16
        }
    }

    var eventTopInset: CGFloat {
        switch self {
        case .compact: 15
        case .expanded: 17
        }
    }

    var laneHeight: CGFloat {
        switch self {
        case .compact: 3
        case .expanded: 14
        }
    }

    var barHeight: CGFloat {
        switch self {
        case .compact: 2
        case .expanded: 13
        }
    }

    var maximumLaneLimit: Int {
        switch self {
        case .compact: 3
        case .expanded: 3
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
                    .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.eventForeground(event.colorID))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 3)
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

@main
struct PlanBaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanBaseCalendarWidget()
        PlanBaseLockScreenWidget()
    }
}
