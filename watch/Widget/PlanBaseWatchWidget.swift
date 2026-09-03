#if os(watchOS)
import PlanBaseCore
import SwiftUI
import WidgetKit

private struct PlanBaseWatchEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchWidgetSnapshot?
}

private struct PlanBaseWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBaseWatchEntry {
        PlanBaseWatchEntry(
            date: Date(),
            snapshot: WatchWidgetSnapshot(
                generatedAt: Date(),
                dayKey: DayKey.today,
                todoCount: 3,
                doingCount: 1,
                doneCount: 2,
                eventCount: 1,
                focusTitle: "집중 작업",
                focusKind: .doingTask
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBaseWatchEntry) -> Void
    ) {
        completion(entry(at: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PlanBaseWatchEntry>) -> Void
    ) {
        let now = Date()
        let storedSnapshot: WatchWidgetSnapshot?
        do {
            storedSnapshot = try WatchWidgetSnapshotStore.read()
        } catch {
            storedSnapshot = nil
        }
        var refreshDate = min(
            now.addingTimeInterval(30 * 60),
            DayKey.addingDays(1, to: DayKey.startOfDay(for: now))
        )
        if let deadline = storedSnapshot?.focusDeadline, deadline > now {
            refreshDate = min(refreshDate, deadline)
        }
        completion(Timeline(
            entries: [PlanBaseWatchEntry(date: now, snapshot: storedSnapshot)],
            policy: .after(refreshDate)
        ))
    }

    private func entry(at date: Date) -> PlanBaseWatchEntry {
        let snapshot = try? WatchWidgetSnapshotStore.read()
        return PlanBaseWatchEntry(date: date, snapshot: snapshot ?? nil)
    }
}

struct PlanBaseWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WatchWidgetConstants.kind,
            provider: PlanBaseWatchProvider()
        ) { entry in
            PlanBaseWatchWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("PlanBase 오늘")
        .description("오늘 할 일과 일정을 빠르게 확인합니다.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

private struct PlanBaseWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanBaseWatchEntry

    private var snapshot: WatchWidgetSnapshot? {
        guard let snapshot = entry.snapshot else { return nil }
        guard snapshot.hasActiveFocusTimer ||
                snapshot.dayKey == DayKey.key(for: entry.date) else {
            return nil
        }
        return snapshot
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            case .accessoryInline:
                inlineView
            case .accessoryCorner:
                cornerView
            default:
                rectangularView
            }
        }
        .widgetURL(
            snapshot?.focusSessionID.flatMap(PlanBaseDeepLink.focusURL(sessionID:))
                ?? PlanBaseDeepLink.boardTodayURL()
        )
    }

    private var circularView: some View {
        Gauge(value: progress) {
            Image(systemName: snapshot?.hasActiveFocusTimer == true
                ? focusSystemImage
                : "checkmark.circle")
        } currentValueLabel: {
            if snapshot?.hasActiveFocusTimer == true {
                Text(focusShortTime)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .minimumScaleFactor(0.65)
            } else {
                Text(snapshot?.doneCount ?? 0, format: .number)
                    .font(.headline.monospacedDigit())
            }
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                snapshot?.hasActiveFocusTimer == true ? focusPhaseTitle : "PlanBase",
                systemImage: snapshot?.hasActiveFocusTimer == true
                    ? focusSystemImage
                    : "checkmark.circle"
            )
                .font(.caption2.weight(.semibold))
            Text(snapshot?.focusTitle ?? emptyTitle)
                .font(.headline)
                .lineLimit(1)
                .privacySensitive()
            if snapshot?.hasActiveFocusTimer == true {
                focusTimeText
            } else {
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineView: some View {
        Label(
            snapshot?.hasActiveFocusTimer == true
                ? "\(focusPhaseTitle) \(focusShortTime)"
                : summaryText,
            systemImage: snapshot?.hasActiveFocusTimer == true
                ? focusSystemImage
                : "checkmark.circle"
        )
    }

    private var cornerView: some View {
        Group {
            if snapshot?.hasActiveFocusTimer == true {
                Image(systemName: focusSystemImage)
            } else {
                Text(snapshot?.remainingTaskCount ?? 0, format: .number)
                    .monospacedDigit()
            }
        }
            .font(.headline)
            .widgetLabel {
                Gauge(value: progress) {
                    Text(snapshot?.hasActiveFocusTimer == true ? focusPhaseTitle : "오늘")
                }
            }
    }

    private var progress: Double {
        if let snapshot,
           snapshot.hasActiveFocusTimer,
           let remaining = snapshot.focusRemainingSeconds(at: entry.date),
           let planned = snapshot.focusPlannedSeconds,
           planned > 0 {
            return 1 - remaining / TimeInterval(planned)
        }
        guard let snapshot, snapshot.totalTaskCount > 0 else { return 0 }
        return Double(snapshot.doneCount) / Double(snapshot.totalTaskCount)
    }

    @ViewBuilder
    private var focusTimeText: some View {
        if focusRemaining <= 0 {
            Text("완료 · Watch 앱에서 확인")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if snapshot?.focusRunState == .paused {
            Text("일시정지 · \(focusClock)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        } else if let deadline = snapshot?.focusDeadline, deadline > entry.date {
            Text(
                timerInterval: entry.date...deadline,
                pauseTime: nil,
                countsDown: true,
                showsHours: false
            )
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private var focusRemaining: TimeInterval {
        snapshot?.focusRemainingSeconds(at: entry.date) ?? 0
    }

    private var focusClock: String {
        let seconds = max(0, Int(focusRemaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var focusShortTime: String {
        guard focusRemaining > 0 else { return "끝" }
        if snapshot?.focusRunState == .paused { return "Ⅱ" }
        let minutes = max(1, Int(ceil(focusRemaining / 60)))
        return "\(minutes)m"
    }

    private var focusPhaseTitle: String {
        snapshot?.focusPhase == .breakTime ? "휴식" : "집중"
    }

    private var focusSystemImage: String {
        if focusRemaining <= 0 { return "checkmark.circle.fill" }
        if snapshot?.focusRunState == .paused { return "pause.circle.fill" }
        return snapshot?.focusPhase == .breakTime
            ? "cup.and.saucer.fill"
            : "timer"
    }

    private var summaryText: String {
        guard let snapshot else { return "Watch 앱에서 동기화" }
        return "남음 \(snapshot.remainingTaskCount) · 완료 \(snapshot.doneCount) · 일정 \(snapshot.eventCount)"
    }

    private var emptyTitle: String {
        snapshot == nil ? "데이터 준비 중" : "오늘 계획 완료"
    }
}

@main
struct PlanBaseWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanBaseWatchWidget()
    }
}
#endif
