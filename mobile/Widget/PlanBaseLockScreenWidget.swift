import PlanBaseCore
import SwiftUI
import WidgetKit

private struct PlanBaseLockScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
    let availability: PlanBaseLockScreenAvailability

    var summary: LockScreenWidgetDaySummary? {
        snapshot.lockScreenSummary(onDayKey: DayKey.key(for: date))
    }
}

private enum PlanBaseLockScreenAvailability: Equatable {
    case availableContent
    case availableEmpty
    case needsRefresh
    case requiresAppUpdate

    var message: String {
        switch self {
        case .availableContent:
            ""
        case .availableEmpty:
            "오늘 계획이 없어요"
        case .needsRefresh:
            "PlanBase를 열면 갱신돼요"
        case .requiresAppUpdate:
            "PlanBase를 업데이트해 주세요"
        }
    }
}

private struct PlanBaseLockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBaseLockScreenEntry {
        entry(at: Date(), snapshot: .lockScreenPreview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBaseLockScreenEntry) -> Void
    ) {
        let date = Date()
        if context.isPreview {
            completion(entry(at: date, snapshot: .lockScreenPreview))
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
        let entries = dates.map { date in
            entry(at: date, snapshot: result.snapshot, state: result.state)
        }
        let refreshDate = refreshDate(after: dates.last ?? now)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    private func loadEntry(at date: Date) -> PlanBaseLockScreenEntry {
        let result = loadSnapshot(at: date)
        return entry(at: date, snapshot: result.snapshot, state: result.state)
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

    private func entry(
        at date: Date,
        snapshot: CalendarWidgetSnapshot,
        state: PlanBaseWidgetSnapshotAvailability = .available
    ) -> PlanBaseLockScreenEntry {
        let availability: PlanBaseLockScreenAvailability
        switch state {
        case .unsupportedNewerSchema:
            availability = .requiresAppUpdate
        case .available:
            if let summary = snapshot.lockScreenSummary(
                onDayKey: DayKey.key(for: date)
            ) {
                availability = summary.hasContent ? .availableContent : .availableEmpty
            } else {
                availability = .needsRefresh
            }
        case .missing, .corrupt, .staleCoverage:
            availability = .needsRefresh
        }
        return PlanBaseLockScreenEntry(
            date: date,
            snapshot: snapshot,
            availability: availability
        )
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

    private func refreshDate(after lastEntryDate: Date) -> Date {
        CalendarWidgetSnapshot.lockScreenTimelineRefreshDate(after: lastEntryDate)
    }
}

private struct PlanBaseLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanBaseLockScreenEntry

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
        .widgetURL(PlanBaseDeepLink.boardTodayURL())
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private var inlineContent: some View {
        switch entry.availability {
        case .availableContent:
            if let summary = entry.summary {
                Label(
                    "할 일 \(summary.remainingTaskCount) · 일정 \(summary.eventCount)",
                    systemImage: "checklist"
                )
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityLabel(
                        "오늘 할 일 \(summary.remainingTaskCount)개, 일정 \(summary.eventCount)개"
                    )
            }
        case .availableEmpty:
            Label("오늘 계획이 없어요", systemImage: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        case .needsRefresh, .requiresAppUpdate:
            Text(entry.availability.message)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var circularContent: some View {
        ZStack {
            AccessoryWidgetBackground()

            switch entry.availability {
            case .availableContent, .availableEmpty:
                if let summary = entry.summary {
                    if summary.remainingTaskCount > 0 {
                        VStack(spacing: 0) {
                            Text("\(summary.remainingTaskCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .widgetAccentable()
                            Text("할 일")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    } else if summary.eventCount > 0 {
                        VStack(spacing: 0) {
                            Text("\(summary.eventCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .widgetAccentable()
                            Text("일정")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    } else {
                        Image(systemName: "checkmark")
                            .font(.title3.bold())
                            .widgetAccentable()
                    }
                }
            case .needsRefresh:
                Image(systemName: "arrow.clockwise")
                    .font(.title3.bold())
                    .widgetAccentable()
            case .requiresAppUpdate:
                Image(systemName: "arrow.down.app")
                    .font(.title3.bold())
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(circularAccessibilityLabel)
    }

    @ViewBuilder
    private var rectangularContent: some View {
        switch entry.availability {
        case .availableContent:
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "할 일 \(summary.remainingTaskCount) · 완료 \(summary.doneCount) · 일정 \(summary.eventCount)"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                    if let focusTitle = summary.focusTitle,
                       let focusKind = summary.focusKind {
                        Label(
                            focusTitle,
                            systemImage: focusSymbol(for: focusKind)
                        )
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
            }
        case .availableEmpty:
            Label("오늘 계획이 없어요", systemImage: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
        case .needsRefresh:
            Label(entry.availability.message, systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
        case .requiresAppUpdate:
            Label(entry.availability.message, systemImage: "arrow.down.app")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
        }
    }

    private var circularAccessibilityLabel: String {
        switch entry.availability {
        case .availableContent:
            if let summary = entry.summary {
                if summary.remainingTaskCount > 0 {
                    return "오늘 할 일 \(summary.remainingTaskCount)개"
                }
                if summary.eventCount > 0 {
                    return "오늘 일정 \(summary.eventCount)개"
                }
                return "오늘 할 일을 완료했어요"
            }
            return entry.availability.message
        case .availableEmpty:
            return entry.availability.message
        case .needsRefresh, .requiresAppUpdate:
            return entry.availability.message
        }
    }

    private func focusSymbol(
        for kind: LockScreenWidgetFocusKind
    ) -> String {
        switch kind {
        case .doingTask:
            "circle.dotted"
        case .event:
            "calendar"
        case .todoTask:
            "circle"
        }
    }
}

private extension CalendarWidgetSnapshot {
    static func lockScreenEmpty(at date: Date) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(
            generatedAt: date,
            themeID: AppThemePreset.defaultID,
            events: []
        )
    }

    static var lockScreenPreview: CalendarWidgetSnapshot {
        let today = Date()
        let coverage = LockScreenWidgetRules.coverageDayKeys(for: today)
        let summaries = (0..<LockScreenWidgetRules.coverageDayCount).map { offset in
            let date = DayKey.addingDays(offset, to: DayKey.startOfDay(for: today))
            return LockScreenWidgetDaySummary(
                dayKey: DayKey.key(for: date),
                todoCount: offset == 0 ? 3 : 0,
                doingCount: offset == 0 ? 1 : 0,
                doneCount: offset == 0 ? 2 : 0,
                eventCount: offset == 0 ? 2 : 0,
                focusTitle: offset == 0 ? "제품 출시 준비와 최종 확인" : nil,
                focusKind: offset == 0 ? .doingTask : nil
            )
        }
        return CalendarWidgetSnapshot(
            generatedAt: today,
            themeID: AppThemePreset.defaultID,
            events: [],
            lockScreenCoveredStartDayKey: coverage.startDayKey,
            lockScreenCoveredEndDayKey: coverage.endDayKey,
            lockScreenDaySummaries: summaries
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
        .description("잠금 화면에서 오늘의 작업과 일정을 간단히 확인합니다.")
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
            PlanBaseLockScreenWidgetView(entry: contentEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("Inline · 내용")
            PlanBaseLockScreenWidgetView(entry: contentEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular · 내용")
            PlanBaseLockScreenWidgetView(entry: eventOnlyEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular · 일정만")
            PlanBaseLockScreenWidgetView(entry: contentEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular · 긴 제목")
            PlanBaseLockScreenWidgetView(entry: emptyEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular · 정상 빈 상태")
            PlanBaseLockScreenWidgetView(entry: refreshEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular · 갱신 필요")
            PlanBaseLockScreenWidgetView(entry: updateEntry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular · 업데이트 필요")
        }
    }

    private static let contentEntry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenPreview,
        availability: .availableContent
    )

    private static let emptyEntry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenEmptyPreview,
        availability: .availableEmpty
    )

    private static let eventOnlyEntry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenEventOnlyPreview,
        availability: .availableContent
    )

    private static let refreshEntry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenEmpty(at: Date()),
        availability: .needsRefresh
    )

    private static let updateEntry = PlanBaseLockScreenEntry(
        date: Date(),
        snapshot: .lockScreenEmpty(at: Date()),
        availability: .requiresAppUpdate
    )
}

private extension CalendarWidgetSnapshot {
    static var lockScreenEmptyPreview: CalendarWidgetSnapshot {
        let today = Date()
        let coverage = LockScreenWidgetRules.coverageDayKeys(for: today)
        let summaries = (0..<LockScreenWidgetRules.coverageDayCount).map { offset in
            LockScreenWidgetDaySummary(
                dayKey: DayKey.key(
                    for: DayKey.addingDays(offset, to: DayKey.startOfDay(for: today))
                ),
                todoCount: 0,
                doingCount: 0,
                doneCount: 0,
                eventCount: 0
            )
        }
        return CalendarWidgetSnapshot(
            generatedAt: today,
            events: [],
            lockScreenCoveredStartDayKey: coverage.startDayKey,
            lockScreenCoveredEndDayKey: coverage.endDayKey,
            lockScreenDaySummaries: summaries
        )
    }

    static var lockScreenEventOnlyPreview: CalendarWidgetSnapshot {
        let today = Date()
        let dayKey = DayKey.key(for: today)
        return CalendarWidgetSnapshot(
            generatedAt: today,
            themeID: AppThemePreset.defaultID,
            events: [],
            lockScreenCoveredStartDayKey: dayKey,
            lockScreenCoveredEndDayKey: dayKey,
            lockScreenDaySummaries: [
                LockScreenWidgetDaySummary(
                    dayKey: dayKey,
                    todoCount: 0,
                    doingCount: 0,
                    doneCount: 0,
                    eventCount: 2,
                    focusTitle: "팀 일정 확인",
                    focusKind: .event
                )
            ]
        )
    }
}
#endif
