import AppIntents
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

struct PlanBasePlannerEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
    let availability: PlanBaseWidgetSnapshotAvailability
    let monthSelection: CalendarWidgetMonthSelection
}

struct PlanBasePlannerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBasePlannerEntry {
        makeEntry(
            date: Date(),
            snapshot: .preview,
            availability: .available,
            usesStoredSelection: false
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBasePlannerEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(loadEntry(at: Date()))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PlanBasePlannerEntry>) -> Void
    ) {
        let now = Date()
        let firstEntry = loadEntry(at: now)
        let entryDates = firstEntry.availability == .available
            ? firstEntry.snapshot.plannerTimelineEntryDates(startingAt: now)
            : [now]
        let entries = entryDates.map { date in
            makeEntry(
                date: date,
                snapshot: firstEntry.snapshot,
                availability: firstEntry.availability
            )
        }
        let refreshDate = CalendarWidgetSnapshot.lockScreenTimelineRefreshDate(
            after: entries.last?.date ?? now
        )
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    private func loadEntry(at date: Date) -> PlanBasePlannerEntry {
        do {
            guard let snapshot = try CalendarWidgetSnapshotStore.read() else {
                return makeEntry(
                    date: date,
                    snapshot: .empty(at: date),
                    availability: .missing
                )
            }
            guard snapshot.covers(dayKey: DayKey.key(for: date)) else {
                return makeEntry(
                    date: date,
                    snapshot: .empty(at: date, themeID: snapshot.themeID),
                    availability: .staleCoverage
                )
            }
            return makeEntry(
                date: date,
                snapshot: snapshot,
                availability: .available
            )
        } catch CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .unsupportedNewerSchema
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
    ) -> PlanBasePlannerEntry {
        let monthSelection = usesStoredSelection
            ? PlannerWidgetMonthSelectionStore.selection(
                snapshot: snapshot,
                referenceDate: date
            )
            : CalendarWidgetMonthNavigation.selection(
                selectedMonthDayKey: nil,
                snapshot: snapshot,
                referenceDate: date
            )
        return PlanBasePlannerEntry(
            date: date,
            snapshot: snapshot,
            availability: availability,
            monthSelection: monthSelection
        )
    }
}

struct PlanBasePlannerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: PlanBasePlannerEntry

    private var theme: CalendarWidgetTheme {
        CalendarWidgetTheme(
            themeID: entry.snapshot.themeID,
            colorScheme: colorScheme,
            renderingMode: renderingMode
        )
    }

    private var contentPadding: CGFloat {
        switch family {
        case .systemMedium:
            13
        case .systemExtraLarge:
            12
        default:
            11
        }
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                PlannerMediumContent(entry: entry, theme: theme)
            } else {
                GeometryReader { proxy in
                    PlannerWidgetAdaptiveContent(
                        entry: entry,
                        theme: theme,
                        family: family,
                        size: proxy.size
                    )
                }
            }
        }
        .padding(contentPadding)
        .containerBackground(for: .widget) {
            theme.background
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
}

private struct PlannerWidgetAdaptiveContent: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme
    let family: WidgetFamily
    let size: CGSize

    private var usesExpandedDensity: Bool {
        family == .systemExtraLarge && size.width >= 520
    }

    private var spacing: CGFloat {
        usesExpandedDensity ? 12 : 9
    }

    private var calendarRatio: CGFloat {
        usesExpandedDensity ? 0.62 : 0.58
    }

    private var usesHorizontalLayout: Bool {
        let usableWidth = size.width - spacing
        let calendarWidth = usableWidth * calendarRatio
        let taskWidth = usableWidth - calendarWidth
        return size.width >= 270 && calendarWidth >= 150 && taskWidth >= 110
    }

    var body: some View {
        if usesHorizontalLayout {
            let calendarWidth = (size.width - spacing) * calendarRatio
            HStack(spacing: spacing) {
                PlannerMonthCalendarPane(
                    entry: entry,
                    theme: theme,
                    usesExpandedDensity: usesExpandedDensity
                )
                .frame(width: calendarWidth)

                taskLink
            }
        } else {
            VStack(spacing: 8) {
                PlannerMonthCalendarPane(
                    entry: entry,
                    theme: theme,
                    usesExpandedDensity: false
                )
                .frame(maxHeight: .infinity)

                taskLink
                    .frame(height: max(92, size.height * 0.38))
            }
        }
    }

    @ViewBuilder
    private var taskLink: some View {
        if let url = PlanBaseDeepLink.boardTodayURL() {
            Link(destination: url) {
                PlannerTodayTaskPane(
                    entry: entry,
                    theme: theme,
                    usesExpandedDensity: usesExpandedDensity
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(taskAccessibilityLabel)
            .privacySensitive()
        } else {
            PlannerTodayTaskPane(
                entry: entry,
                theme: theme,
                usesExpandedDensity: usesExpandedDensity
            )
        }
    }

    private var taskAccessibilityLabel: String {
        plannerTaskAccessibilityLabel(for: entry)
    }
}

private struct PlannerMediumContent: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme

    var body: some View {
        GeometryReader { proxy in
            let taskWidth = min(150, max(124, proxy.size.width * 0.44))

            HStack(spacing: 10) {
                taskLink
                    .frame(width: taskWidth)

                Rectangle()
                    .fill(theme.border.opacity(0.72))
                    .frame(width: 0.5)

                PlannerMediumMonthPane(entry: entry, theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var taskLink: some View {
        if let url = PlanBaseDeepLink.boardTodayURL() {
            Link(destination: url) {
                PlannerMediumTodayPane(entry: entry, theme: theme)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plannerTaskAccessibilityLabel(for: entry))
            .privacySensitive()
        } else {
            PlannerMediumTodayPane(entry: entry, theme: theme)
        }
    }
}

private struct PlannerMediumTodayPane: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme

    private let maximumVisibleTaskCount = 2

    private var dayKey: String {
        DayKey.key(for: entry.date)
    }

    private var summary: LockScreenWidgetDaySummary? {
        entry.snapshot.lockScreenSummary(onDayKey: dayKey)
    }

    private var previews: [PlannerWidgetTaskPreview]? {
        entry.snapshot.plannerTaskPreviews(onDayKey: dayKey)
    }

    private var isAvailable: Bool {
        entry.availability == .available && summary != nil && previews != nil
    }

    private var displayedPreviews: [PlannerWidgetTaskPreview] {
        Array((previews ?? []).prefix(maximumVisibleTaskCount))
    }

    private var overflowCount: Int {
        max(0, (summary?.remainingTaskCount ?? 0) - displayedPreviews.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.date, format: .dateTime.month(.wide).day())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            if let summary, isAvailable {
                Text("남은 \(summary.remainingTaskCount) · 완료 \(summary.doneCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }

            if !isAvailable {
                Text(entry.availability.taskMessage)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(3)
            } else if summary?.remainingTaskCount == 0 {
                Text("오늘 할 일이 없어요")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayedPreviews, id: \.renderID) { preview in
                        PlannerWidgetTaskRow(
                            preview: preview,
                            theme: theme,
                            usesExpandedDensity: false
                        )
                    }

                    if overflowCount > 0 {
                        Text("+\(overflowCount)개 더")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .padding(.leading, 17)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct PlannerMediumMonthPane: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 0),
        count: 7
    )

    private var month: Date {
        DayKey.startOfMonth(for: entry.date)
    }

    private var dates: [Date] {
        DayKey.adaptiveMonthGridDates(for: month)
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(Array(DayKey.weekdaySymbols().enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(index == 0 ? theme.sundayText : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)

            GeometryReader { proxy in
                let rowCount = max(1, dates.count / 7)
                let rowHeight = proxy.size.height / CGFloat(rowCount)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(dates, id: \.self) { date in
                        mediumDayCell(for: date)
                            .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediumDayCell(for date: Date) -> some View {
        if DayKey.isSameMonth(date, month),
           let url = PlanBaseDeepLink.calendarURL(dayKey: DayKey.key(for: date)) {
            let eventCount = entry.snapshot.totalEventCount(onDayKey: DayKey.key(for: date))

            Link(destination: url) {
                VStack(spacing: 1) {
                    Text(DayKey.dayNumber(date))
                        .font(.system(
                            size: 8,
                            weight: DayKey.isToday(date) ? .bold : .medium
                        ))
                        .foregroundStyle(
                            DayKey.isToday(date) ? theme.accentForeground : dayForeground(for: date)
                        )
                        .frame(width: 13, height: 13)
                        .background {
                            if DayKey.isToday(date) {
                                Circle()
                                    .fill(theme.accent)
                                    .widgetAccentable()
                            }
                        }

                    Circle()
                        .fill(eventCount > 0 ? theme.accent : Color.clear)
                        .frame(width: 2.5, height: 2.5)
                        .widgetAccentable()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dayAccessibilityLabel(for: date, eventCount: eventCount))
        } else {
            Color.clear
        }
    }

    private func dayForeground(for date: Date) -> Color {
        DayKey.calendar.component(.weekday, from: date) == 1
            ? theme.sundayText
            : theme.primaryText
    }

    private func dayAccessibilityLabel(for date: Date, eventCount: Int) -> String {
        eventCount > 0
            ? "\(DayKey.display(date)), 이벤트 \(eventCount)개"
            : "\(DayKey.display(date)), 이벤트 없음"
    }
}

private func plannerTaskAccessibilityLabel(for entry: PlanBasePlannerEntry) -> String {
    let dayKey = DayKey.key(for: entry.date)
    guard entry.availability == .available,
          let summary = entry.snapshot.lockScreenSummary(onDayKey: dayKey),
          let previews = entry.snapshot.plannerTaskPreviews(onDayKey: dayKey) else {
        return entry.availability.taskMessage
    }
    guard summary.remainingTaskCount > 0 else {
        return "오늘 할 일이 없어요. 오늘 보드 열기"
    }
    let titles = previews.map(\.title).joined(separator: ", ")
    let overflowCount = max(0, summary.remainingTaskCount - previews.count)
    let overflow = overflowCount > 0 ? ", 외 \(overflowCount)개" : ""
    return "오늘 남은 작업 \(summary.remainingTaskCount)개, 완료 \(summary.doneCount)개, \(titles)\(overflow). 오늘 보드 열기"
}

private struct PlannerMonthCalendarPane: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme
    let usesExpandedDensity: Bool

    private var style: CalendarWidgetMonthGridStyle {
        usesExpandedDensity ? .plannerExpanded : .plannerCompact
    }

    private var month: Date {
        entry.monthSelection.month
    }

    private var dates: [Date] {
        DayKey.adaptiveMonthGridDates(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesExpandedDensity ? 3 : 2) {
            PlannerWidgetMonthHeader(
                monthSelection: entry.monthSelection,
                theme: theme,
                style: style
            )

            CalendarWidgetWeekdayHeader(theme: theme, style: style)
                .frame(height: style.weekdayHeaderHeight)

            GeometryReader { proxy in
                CalendarWidgetMonthGrid(
                    snapshot: entry.snapshot,
                    month: month,
                    dates: dates,
                    theme: theme,
                    style: style,
                    size: proxy.size
                )
            }
        }
        .overlay(alignment: .bottomLeading) {
            if entry.availability != .available {
                PlannerWidgetRefreshBadge(
                    message: entry.availability.calendarMessage,
                    theme: theme
                )
            }
        }
    }
}

private struct PlannerWidgetMonthHeader: View {
    let monthSelection: CalendarWidgetMonthSelection
    let theme: CalendarWidgetTheme
    let style: CalendarWidgetMonthGridStyle

    var body: some View {
        HStack(spacing: 2) {
            Button(intent: ResetPlannerWidgetMonthIntent()) {
                Text(DayKey.monthTitle(monthSelection.month))
                    .font(.system(size: style.monthHeaderFontSize, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("플래너를 이번 달로 이동")

            Spacer(minLength: 4)

            monthButton(
                systemName: "chevron.left",
                label: "플래너 이전 달",
                delta: -1,
                isEnabled: monthSelection.canMoveBackward
            )
            monthButton(
                systemName: "chevron.right",
                label: "플래너 다음 달",
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
        Button(intent: ChangePlannerWidgetMonthIntent(monthDelta: delta)) {
            Image(systemName: systemName)
                .font(.system(size: style.monthControlFontSize, weight: .semibold))
                .foregroundStyle(theme.secondaryText.opacity(isEnabled ? 1 : 0.28))
                .frame(width: style.monthControlWidth, height: style.monthHeaderHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

private struct PlannerTodayTaskPane: View {
    let entry: PlanBasePlannerEntry
    let theme: CalendarWidgetTheme
    let usesExpandedDensity: Bool

    private var dayKey: String {
        DayKey.key(for: entry.date)
    }

    private var summary: LockScreenWidgetDaySummary? {
        entry.snapshot.lockScreenSummary(onDayKey: dayKey)
    }

    private var previews: [PlannerWidgetTaskPreview]? {
        entry.snapshot.plannerTaskPreviews(onDayKey: dayKey)
    }

    private var isAvailable: Bool {
        entry.availability == .available && summary != nil && previews != nil
    }

    private var displayedPreviews: [PlannerWidgetTaskPreview] {
        Array((previews ?? []).prefix(PlannerWidgetRules.maximumPreviewCountPerDay))
    }

    private var overflowCount: Int {
        max(0, (summary?.remainingTaskCount ?? 0) - displayedPreviews.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesExpandedDensity ? 9 : 7) {
            header

            Rectangle()
                .fill(theme.border.opacity(0.7))
                .frame(height: 0.5)

            if !isAvailable {
                unavailableContent
            } else if summary?.remainingTaskCount == 0 {
                emptyContent
            } else {
                taskList
            }
        }
        .padding(usesExpandedDensity ? 12 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(theme.border.opacity(0.8), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("오늘")
                    .font(.system(
                        size: usesExpandedDensity ? 17 : 15,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(entry.date, format: .dateTime.month(.wide).day().weekday(.abbreviated))
                .font(.system(size: usesExpandedDensity ? 11 : 9, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            if let summary, isAvailable {
                Text("남은 \(summary.remainingTaskCount) · 완료 \(summary.doneCount)")
                    .font(.system(size: usesExpandedDensity ? 11 : 9, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent)
                .widgetAccentable()

            Text(entry.availability.taskMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var emptyContent: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: usesExpandedDensity ? 22 : 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .widgetAccentable()

            Text("오늘 할 일이 없어요")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: usesExpandedDensity ? 7 : 6) {
            ForEach(displayedPreviews, id: \.renderID) { preview in
                PlannerWidgetTaskRow(
                    preview: preview,
                    theme: theme,
                    usesExpandedDensity: usesExpandedDensity
                )
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)개 더 있어요")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .padding(.leading, usesExpandedDensity ? 21 : 18)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PlannerWidgetTaskRow: View {
    let preview: PlannerWidgetTaskPreview
    let theme: CalendarWidgetTheme
    let usesExpandedDensity: Bool

    var body: some View {
        HStack(spacing: usesExpandedDensity ? 8 : 6) {
            Image(systemName: preview.status == .doing ? "play.circle.fill" : "circle")
                .font(.system(size: usesExpandedDensity ? 13 : 11, weight: .semibold))
                .foregroundStyle(
                    preview.status == .doing ? theme.accent : theme.secondaryText
                )
                .widgetAccentable()

            Text(preview.title)
                .font(.system(size: usesExpandedDensity ? 13 : 11, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlannerWidgetRefreshBadge: View {
    let message: String
    let theme: CalendarWidgetTheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.accent)
                .widgetAccentable()

            Text(message)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(theme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.border, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct PlanBasePlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.plannerKind,
            provider: PlanBasePlannerProvider()
        ) { entry in
            PlanBasePlannerWidgetView(entry: entry)
        }
        .configurationDisplayName("PlanBase 플래너")
        .description(widgetDescription)
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }

    private var widgetDescription: String {
#if os(macOS)
        "이번 달 일정과 오늘 작업을 바탕화면에서 함께 확인합니다."
#else
        "이번 달 일정과 오늘 작업을 홈 화면에서 함께 확인합니다."
#endif
    }
}

#if DEBUG
private struct PlanBasePlannerWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            PlanBasePlannerWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Planner · Medium")
            PlanBasePlannerWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("Planner · Large")
            PlanBasePlannerWidgetView(entry: availableEntry)
                .previewContext(WidgetPreviewContext(family: .systemExtraLarge))
                .previewDisplayName("Planner · Extra Large")
            PlanBasePlannerWidgetView(entry: refreshEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("Planner · 갱신 필요")
        }
    }

    private static let previewDate = Date()
    private static let previewSnapshot = CalendarWidgetSnapshot.preview
    private static let availableEntry = PlanBasePlannerEntry(
        date: previewDate,
        snapshot: previewSnapshot,
        availability: .available,
        monthSelection: CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: nil,
            snapshot: previewSnapshot,
            referenceDate: previewDate
        )
    )
    private static let refreshSnapshot = CalendarWidgetSnapshot.empty(at: previewDate)
    private static let refreshEntry = PlanBasePlannerEntry(
        date: previewDate,
        snapshot: refreshSnapshot,
        availability: .missing,
        monthSelection: CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: nil,
            snapshot: refreshSnapshot,
            referenceDate: previewDate
        )
    )
}
#endif
