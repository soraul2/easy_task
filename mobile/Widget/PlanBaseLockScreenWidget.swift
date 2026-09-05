#if os(iOS)
import PlanBaseCore
import SwiftUI
import WidgetKit

private enum PlanBaseLockScreenAvailability: Equatable {
    case available
    case needsRefresh
    case requiresAppUpdate

    var message: String {
        switch self {
        case .available: ""
        case .needsRefresh: "앱을 열어 갱신"
        case .requiresAppUpdate: "업데이트 필요"
        }
    }
}

private struct PlanBaseLockScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
    let snapshotState: PlanBaseWidgetSnapshotAvailability

    var dayKey: String { DayKey.key(for: date) }

    var summary: LockScreenWidgetDaySummary? {
        snapshot.lockScreenSummary(onDayKey: dayKey)
    }

    var previews: [PlannerWidgetTaskPreview]? {
        snapshot.plannerTaskPreviews(onDayKey: dayKey)
    }

    var taskPresentation: LockScreenWidgetTaskPresentation? {
        guard let summary, let previews else { return nil }
        return LockScreenWidgetRules.taskPresentation(summary: summary, previews: previews)
    }

    var taskAvailability: PlanBaseLockScreenAvailability {
        availability(hasCoverage: summary != nil && previews != nil)
    }

    var calendarAvailability: PlanBaseLockScreenAvailability {
        availability(hasCoverage: snapshot.covers(dayKey: dayKey))
    }

    var events: [CalendarWidgetEventSnapshot] {
        snapshot.events(onDayKey: dayKey)
    }

    var eventCount: Int {
        snapshot.totalEventCount(onDayKey: dayKey)
    }

    private func availability(hasCoverage: Bool) -> PlanBaseLockScreenAvailability {
        switch snapshotState {
        case .unsupportedNewerSchema:
            .requiresAppUpdate
        case .available:
            hasCoverage ? .available : .needsRefresh
        case .missing, .corrupt, .staleCoverage:
            .needsRefresh
        }
    }
}

private struct PlanBaseLockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBaseLockScreenEntry {
        PlanBaseLockScreenEntry(
            date: Date(),
            snapshot: .lockScreenPreview,
            snapshotState: .available
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBaseLockScreenEntry) -> Void
    ) {
        let date = Date()
        if context.isPreview {
            completion(PlanBaseLockScreenEntry(
                date: date,
                snapshot: .lockScreenPreview,
                snapshotState: .available
            ))
        } else {
            completion(loadEntry(at: date))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PlanBaseLockScreenEntry>) -> Void
    ) {
        let now = Date()
        let result = loadSnapshot(at: now)
        let dates = timelineDates(now: now, snapshot: result.snapshot, state: result.state)
        let entries = dates.map {
            PlanBaseLockScreenEntry(
                date: $0,
                snapshot: result.snapshot,
                snapshotState: result.state
            )
        }
        completion(Timeline(
            entries: entries,
            policy: .after(CalendarWidgetSnapshot.lockScreenTimelineRefreshDate(
                after: dates.last ?? now
            ))
        ))
    }

    private func loadEntry(at date: Date) -> PlanBaseLockScreenEntry {
        let result = loadSnapshot(at: date)
        return PlanBaseLockScreenEntry(
            date: date,
            snapshot: result.snapshot,
            snapshotState: result.state
        )
    }

    private func loadSnapshot(
        at date: Date
    ) -> (snapshot: CalendarWidgetSnapshot, state: PlanBaseWidgetSnapshotAvailability) {
        do {
            guard let snapshot = try CalendarWidgetSnapshotStore.read() else {
                return (.lockScreenEmpty(at: date), .missing)
            }
            return (snapshot, .available)
        } catch CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion {
            return (.lockScreenEmpty(at: date), .unsupportedNewerSchema)
        } catch {
            return (.lockScreenEmpty(at: date), .corrupt)
        }
    }

    private func timelineDates(
        now: Date,
        snapshot: CalendarWidgetSnapshot,
        state: PlanBaseWidgetSnapshotAvailability
    ) -> [Date] {
        guard state == .available,
              snapshot.hasLockScreenCoverage(dayKey: DayKey.key(for: now)) else {
            return [now]
        }
        return snapshot.lockScreenTimelineEntryDates(startingAt: now)
    }
}

private struct PlanBaseLockScreenWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: PlanBaseLockScreenEntry

    private var theme: CalendarWidgetTheme {
        CalendarWidgetTheme(
            themeID: entry.snapshot.themeID,
            colorScheme: colorScheme,
            renderingMode: renderingMode
        )
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularContent
            case .accessoryRectangular:
                rectangularContent
            default:
                inlineContent
            }
        }
        .foregroundStyle(theme.primaryText)
        .tint(theme.accent)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var inlineContent: some View {
        if let url = PlanBaseDeepLink.calendarTodayURL() {
            Link(destination: url) {
                switch entry.calendarAvailability {
                case .available:
                    inlineEventContent
                case .needsRefresh, .requiresAppUpdate:
                    Label(entry.calendarAvailability.message, systemImage: "calendar")
                }
            }
        }
    }

    @ViewBuilder
    private var inlineEventContent: some View {
        if entry.eventCount == 0 {
            Label("일정 없음", systemImage: "calendar")
        } else if redactionReasons.contains(.privacy) {
            Label("일정 \(entry.eventCount)개", systemImage: "calendar")
        } else if let title = entry.events.first?.title, !title.isEmpty {
            Label {
                Text(entry.eventCount > 1 ? "\(title) · +\(entry.eventCount - 1)" : title)
                    .privacySensitive()
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Label("일정 \(entry.eventCount)개", systemImage: "calendar")
        }
    }

    private var circularContent: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let url = PlanBaseDeepLink.boardNewTaskTodayURL() {
                Link(destination: url) {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .bold))
                        .widgetAccentable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel("오늘 할 일 추가")
            }
        }
    }

    @ViewBuilder
    private var rectangularContent: some View {
        switch entry.taskAvailability {
        case .available:
            if let presentation = entry.taskPresentation {
                taskRow(presentation)
            }
        case .needsRefresh, .requiresAppUpdate:
            if let url = PlanBaseDeepLink.boardTodayURL() {
                Link(destination: url) {
                    Label(entry.taskAvailability.message, systemImage: "checklist")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ presentation: LockScreenWidgetTaskPresentation) -> some View {
        switch presentation.state {
        case .startable:
            if let taskID = presentation.taskID {
                Button(intent: StartPlanBaseTaskIntent(taskID: taskID)) {
                    compactTaskRow(
                        presentation,
                        leadingSymbol: nil,
                        trailingActionSymbol: "play.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(taskAccessibilityLabel(for: presentation)), 작업 진행하기"
                )
            } else if let url = PlanBaseDeepLink.boardTodayURL() {
                Link(destination: url) {
                    compactTaskRow(
                        presentation,
                        leadingSymbol: nil,
                        trailingActionSymbol: "play.fill"
                    )
                }
            }
        case .doing:
            if let url = PlanBaseDeepLink.boardTodayURL() {
                Link(destination: url) {
                    compactTaskRow(presentation, leadingSymbol: "circle.fill")
                }
            }
        case .complete:
            if let url = PlanBaseDeepLink.boardTodayURL() {
                Link(destination: url) {
                    compactTaskRow(presentation, leadingSymbol: "checkmark")
                }
            }
        case .empty:
            if let url = PlanBaseDeepLink.boardTodayURL() {
                Link(destination: url) {
                    compactTaskRow(presentation, leadingSymbol: nil)
                }
            }
        }
    }

    private func compactTaskRow(
        _ presentation: LockScreenWidgetTaskPresentation,
        leadingSymbol: String?,
        trailingActionSymbol: String? = nil
    ) -> some View {
        HStack(spacing: 5) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 10, weight: .bold))
                    .widgetAccentable()
            }
            Text(privateTaskTitle(for: presentation))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .privacySensitive()
            Spacer(minLength: 4)
            if presentation.totalCount > 0 {
                Text(presentation.progressText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if let trailingActionSymbol {
                Image(systemName: trailingActionSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24, height: 24)
                    .background(theme.accent.opacity(0.18), in: Circle())
                    .widgetAccentable()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel(for: presentation))
    }

    private func privateTaskTitle(
        for presentation: LockScreenWidgetTaskPresentation
    ) -> String {
        guard redactionReasons.contains(.privacy) else { return presentation.title }
        return switch presentation.state {
        case .doing: "진행 중"
        case .startable: "시작 가능"
        case .complete, .empty: presentation.title
        }
    }

    private func taskAccessibilityLabel(
        for presentation: LockScreenWidgetTaskPresentation
    ) -> String {
        let title = privateTaskTitle(for: presentation)
        guard presentation.totalCount > 0 else { return title }
        return "\(title), 오늘 전체 \(presentation.totalCount)개 중 \(presentation.completedCount)개 완료"
    }
}

private extension CalendarWidgetSnapshot {
    static func lockScreenEmpty(at date: Date) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(generatedAt: date, events: [])
    }

    static var lockScreenPreview: CalendarWidgetSnapshot {
        let today = Date()
        let dayKey = DayKey.key(for: today)
        let coverage = LockScreenWidgetRules.coverageDayKeys(for: today)
        let summaries = (0..<LockScreenWidgetRules.coverageDayCount).map { offset in
            LockScreenWidgetDaySummary(
                dayKey: DayKey.key(for: DayKey.addingDays(offset, to: today)),
                todoCount: offset == 0 ? 2 : 0,
                doingCount: offset == 0 ? 1 : 0,
                doneCount: offset == 0 ? 3 : 0,
                eventCount: offset == 0 ? 2 : 0
            )
        }
        return CalendarWidgetSnapshot(
            generatedAt: today,
            events: [CalendarWidgetEventSnapshot(
                id: UUID(),
                title: "팀 미팅",
                startDayKey: dayKey,
                endDayKey: dayKey,
                colorID: CalendarEventPalette.defaultColor
            )],
            lockScreenCoveredStartDayKey: coverage.startDayKey,
            lockScreenCoveredEndDayKey: coverage.endDayKey,
            lockScreenDaySummaries: summaries,
            plannerTaskPreviewsByDayKey: [
                dayKey: [PlannerWidgetTaskPreview(
                    id: UUID(),
                    title: "기획서 작성",
                    status: .doing,
                    order: 0
                )]
            ]
        )
    }
}

struct PlanBaseLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CalendarWidgetConstants.lockScreenKind,
            provider: PlanBaseLockScreenProvider()
        ) { entry in
            PlanBaseLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("PlanBase 오늘")
        .description("오늘 일정 확인, 작업 시작, 빠른 추가를 잠금 화면에서 사용합니다.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

#if DEBUG
private struct PlanBaseLockScreenWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            PlanBaseLockScreenWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("오늘 일정")
            PlanBaseLockScreenWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("빠른 추가")
            PlanBaseLockScreenWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("오늘 작업")
        }
    }

    private static let entry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenPreview,
        snapshotState: .available
    )
}
#endif
#endif
