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
        let refreshDate = min(
            now.addingTimeInterval(30 * 60),
            DayKey.addingDays(1, to: DayKey.startOfDay(for: now))
        )
        completion(Timeline(
            entries: [entry(at: now)],
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
        guard let snapshot = entry.snapshot,
              snapshot.dayKey == DayKey.key(for: entry.date) else {
            return nil
        }
        return snapshot
    }

    var body: some View {
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

    private var circularView: some View {
        Gauge(value: progress) {
            Image(systemName: "checkmark.circle")
        } currentValueLabel: {
            Text(snapshot?.doneCount ?? 0, format: .number)
                .font(.headline.monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("PlanBase", systemImage: "checkmark.circle")
                .font(.caption2.weight(.semibold))
            Text(snapshot?.focusTitle ?? emptyTitle)
                .font(.headline)
                .lineLimit(1)
                .privacySensitive()
            Text(summaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineView: some View {
        Label(summaryText, systemImage: "checkmark.circle")
    }

    private var cornerView: some View {
        Text(snapshot?.remainingTaskCount ?? 0, format: .number)
            .font(.headline.monospacedDigit())
            .widgetLabel {
                Gauge(value: progress) {
                    Text("오늘")
                }
            }
    }

    private var progress: Double {
        guard let snapshot, snapshot.totalTaskCount > 0 else { return 0 }
        return Double(snapshot.doneCount) / Double(snapshot.totalTaskCount)
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
