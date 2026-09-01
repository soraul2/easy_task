#if os(iOS)
import ActivityKit
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

struct PlanBaseTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanBaseTaskActivityAttributes.self) { context in
            TaskLiveActivityLockScreen(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        TaskLiveActivityActiveDot(themeID: context.state.themeID)
                        TaskLiveActivityElapsedText(
                            startedAt: context.state.elapsedTimerStartedAt,
                            style: .expanded
                        )
                    }
                }
            } compactLeading: {
                TaskLiveActivityCompactTitle(
                    title: context.state.title,
                    themeID: context.state.themeID
                )
            } compactTrailing: {
                TaskLiveActivityElapsedText(
                    startedAt: context.state.elapsedTimerStartedAt,
                    style: .compact
                )
            } minimal: {
                TaskLiveActivityElapsedText(
                    startedAt: context.state.elapsedTimerStartedAt,
                    style: .minimal
                )
            }
        }
    }
}

private struct TaskLiveActivityCompactTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.redactionReasons) private var redactionReasons

    let title: String
    let themeID: String?

    private var theme: TaskLiveActivityTheme {
        TaskLiveActivityTheme(themeID: themeID, colorScheme: colorScheme)
    }

    var body: some View {
        Text(redactionReasons.contains(.privacy) ? "진행" : title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: 46, alignment: .leading)
            .privacySensitive()
            .accessibilityLabel("진행 중인 작업 \(title)")
    }
}

private struct TaskLiveActivityElapsedText: View {
    enum Style {
        case compact
        case minimal
        case expanded

        var font: Font {
            switch self {
            case .compact:
                return .caption2.weight(.semibold)
            case .minimal:
                return .caption2.weight(.bold)
            case .expanded:
                return .headline
            }
        }

        var timeWidth: CGFloat {
            switch self {
            case .compact:
                return 50
            case .minimal:
                return 32
            case .expanded:
                return 72
            }
        }

        var minimumScaleFactor: CGFloat {
            switch self {
            case .minimal:
                return 0.65
            case .compact, .expanded:
                return 0.8
            }
        }
    }

    let startedAt: Date
    let style: Style

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(Self.elapsedText(startedAt: startedAt, now: timeline.date))
                .font(style.font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(style.minimumScaleFactor)
                .frame(width: style.timeWidth, alignment: .trailing)
                .accessibilityLabel("진행 시간")
        }
    }

    private static func elapsedText(startedAt: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TaskLiveActivityActiveDot: View {
    @Environment(\.colorScheme) private var colorScheme

    let themeID: String?

    private var theme: TaskLiveActivityTheme {
        TaskLiveActivityTheme(themeID: themeID, colorScheme: colorScheme)
    }

    var body: some View {
        Circle()
            .fill(theme.accent)
            .frame(width: 6, height: 6)
            .accessibilityLabel("작업 진행 중")
    }
}

private struct TaskLiveActivityLockScreen: View {
    @Environment(\.redactionReasons) private var redactionReasons

    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(redactedTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TaskLiveActivityActiveDot(themeID: context.state.themeID)
                        TaskLiveActivityElapsedText(
                            startedAt: context.state.elapsedTimerStartedAt,
                            style: .expanded
                        )
                    }

                    Text(context.state.progressText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TaskLiveActivityActions(context: context)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 88)
        .widgetURL(PlanBaseDeepLink.boardTodayURL())
    }

    private var redactedTitle: String {
        redactionReasons.contains(.privacy) ? "진행 중인 작업" : context.state.title
    }
}

private struct TaskLiveActivityActions: View {
    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 7) {
            if context.state.hasNextTask {
                Button(intent: AdvancePlanBaseTaskIntent(
                    taskID: context.state.taskID,
                    taskSessionID: context.state.taskSessionID
                )) {
                    TaskLiveActivityActionLabel(
                        systemImage: "arrow.right",
                        themeID: context.state.themeID
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다음 작업 진행")
            }

            completionControl
        }
    }

    @ViewBuilder
    private var completionControl: some View {
        if context.state.requiresCompletionConfirmation,
           let url = PlanBaseDeepLink.boardConfirmCompletionTodayURL(
               taskID: context.state.taskID
           ) {
            Link(destination: url) {
                TaskLiveActivityActionLabel(
                    systemImage: "checkmark",
                    themeID: context.state.themeID
                )
            }
            .accessibilityLabel("앱에서 완료 확인")
        } else {
            Button(intent: CompletePlanBaseTaskIntent(
                taskID: context.state.taskID,
                taskSessionID: context.state.taskSessionID
            )) {
                TaskLiveActivityActionLabel(
                    systemImage: "checkmark",
                    themeID: context.state.themeID
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("작업 완료")
        }
    }
}

private struct TaskLiveActivityActionLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let themeID: String?

    private var theme: TaskLiveActivityTheme {
        TaskLiveActivityTheme(themeID: themeID, colorScheme: colorScheme)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.accent)
            .frame(width: 48, height: 48)
            .background(
                theme.buttonBackground,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TaskLiveActivityTheme {
    let colors: AppThemeColorSet

    init(themeID: String?, colorScheme: ColorScheme) {
        colors = AppThemePreset
            .preset(for: themeID)
            .colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var accent: Color {
        colors.event.color
    }

    var buttonBackground: Color {
        accent.opacity(0.18)
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
        elapsedTimerStartedAt: Date().addingTimeInterval(-18_960),
        themeID: "roseLilac"
    )
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: PlanBaseTaskActivityAttributes(
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
        elapsedTimerStartedAt: Date().addingTimeInterval(-26_494),
        themeID: "roseLilac"
    )
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: PlanBaseTaskActivityAttributes(
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
        elapsedTimerStartedAt: Date().addingTimeInterval(-26_494),
        themeID: "roseLilac"
    )
}
#endif
#endif
