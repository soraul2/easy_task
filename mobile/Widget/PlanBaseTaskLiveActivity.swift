#if os(iOS)
import ActivityKit
import PlanBaseCore
import SwiftUI
import WidgetKit

struct PlanBaseTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanBaseTaskActivityAttributes.self) { context in
            PlanBaseTaskLiveActivityLockView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlanBaseTaskLiveActivityElapsedTime(
                        startedAt: context.state.elapsedTimerStartedAt,
                        font: .headline,
                        showsIcon: true
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progressText)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer(minLength: 0)
                        PlanBaseTaskLiveActivityActionButtons(context: context)
                    }
                }
            } compactLeading: {
                PlanBaseTaskLiveActivityElapsedTime(
                    startedAt: context.state.elapsedTimerStartedAt,
                    font: .caption2.weight(.semibold),
                    showsIcon: false
                )
            } compactTrailing: {
                PlanBaseTaskLiveActivityCompactTitle(title: context.state.title)
            } minimal: {
                PlanBaseTaskLiveActivityElapsedTime(
                    startedAt: context.state.elapsedTimerStartedAt,
                    font: .caption2.weight(.bold),
                    showsIcon: false
                )
            }
            .keylineTint(Color.primary)
        }
    }
}

private struct PlanBaseTaskLiveActivityElapsedTime: View {
    let startedAt: Date
    let font: Font
    let showsIcon: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: "play.fill")
                    .accessibilityHidden(true)
            }

            Text(startedAt, style: .timer)
                .monospacedDigit()
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}

private struct PlanBaseTaskLiveActivityCompactTitle: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let title: String

    var body: some View {
        Text(redactionReasons.contains(.privacy) ? "진행 중" : title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: 84, alignment: .trailing)
            .privacySensitive()
            .accessibilityLabel("진행 중인 작업 \(title)")
    }
}

private struct PlanBaseTaskLiveActivityLockView: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(redactionReasons.contains(.privacy) ? "진행 중인 작업" : context.state.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()

                HStack(spacing: 8) {
                    PlanBaseTaskLiveActivityElapsedTime(
                        startedAt: context.state.elapsedTimerStartedAt,
                        font: .system(size: 14, weight: .bold, design: .rounded),
                        showsIcon: true
                    )

                    Text(context.state.progressText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlanBaseTaskLiveActivityActionButtons(context: context)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 88)
        .widgetURL(PlanBaseDeepLink.boardTodayURL())
    }
}

private struct PlanBaseTaskLiveActivityActionButtons: View {
    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 7) {
            completionControl

            if context.state.hasNextTask {
                Button(intent: AdvancePlanBaseTaskIntent(
                    taskID: context.state.taskID,
                    taskSessionID: context.state.taskSessionID
                )) {
                    PlanBaseTaskLiveActivityActionLabel(
                        title: "다음",
                        systemImage: "arrow.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다음 작업 진행")
            }
        }
    }

    @ViewBuilder
    private var completionControl: some View {
        if context.state.requiresCompletionConfirmation,
           let url = PlanBaseDeepLink.boardConfirmCompletionTodayURL(
               taskID: context.state.taskID
           ) {
            Link(destination: url) {
                PlanBaseTaskLiveActivityActionLabel(
                    title: "완료",
                    systemImage: "checkmark"
                )
            }
            .accessibilityLabel("앱에서 완료 확인")
        } else {
            Button(intent: CompletePlanBaseTaskIntent(
                taskID: context.state.taskID,
                taskSessionID: context.state.taskSessionID
            )) {
                PlanBaseTaskLiveActivityActionLabel(
                    title: "완료",
                    systemImage: "checkmark"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("작업 완료")
        }
    }
}

private struct PlanBaseTaskLiveActivityActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .frame(width: 58, height: 48)
        .background(.primary.opacity(0.13), in: RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
        ))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if DEBUG
#Preview("Live Activity", as: .content, using: PlanBaseTaskActivityAttributes(
    activityID: UUID(),
    dayKey: DayKey.today
)) {
    PlanBaseTaskLiveActivity()
} contentStates: {
    PlanBaseTaskActivityAttributes.ContentState(
        taskSessionID: "preview",
        taskID: UUID(),
        title: "기획서 작성",
        completedCount: 3,
        totalCount: 4,
        hasNextTask: true,
        requiresCompletionConfirmation: false,
        elapsedTimerStartedAt: Date().addingTimeInterval(-754)
    )
}
#endif
#endif
