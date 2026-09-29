#if os(iOS)
import ActivityKit
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit
#if DEBUG
import OSLog
#endif

private extension PlanBaseTaskActivityAttributes.ContentState {
    var isBreakTime: Bool {
        focusPhaseRawValue == FocusTimerPhase.breakTime.rawValue
    }

    var focusPhaseTitle: String {
        isBreakTime ? "휴식" : "집중"
    }
}

struct PlanBaseTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanBaseTaskActivityAttributes.self) { context in
            TaskLiveActivityLockScreen(context: context)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if !context.state.isTodo {
                            TaskLiveActivityActiveDot(themeID: context.state.themeID)
                        }
                        TaskLiveActivityTimeText(
                            state: context.state,
                            style: .expanded
                        )
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TaskLiveActivityActions(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TaskLiveActivityExpandedTitle(title: context.state.title, isTodo: context.state.isTodo)
                }
            } compactLeading: {
                TaskLiveActivityCompactTitle(
                    title: context.state.title,
                    isTodo: context.state.isTodo,
                    themeID: context.state.themeID
                )
            } compactTrailing: {
                TaskLiveActivityTimeText(
                    state: context.state,
                    style: .compact
                )
            } minimal: {
                TaskLiveActivityTimeText(
                    state: context.state,
                    style: .minimal
                )
            }
        }
    }
}

private struct TaskLiveActivityExpandedTitle: View {
    @Environment(\.redactionReasons) private var redactionReasons

    let title: String
    var isTodo = false

    var body: some View {
        Text(redactedTitle)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .privacySensitive()
            .accessibilityLabel(accessibilityTitle)
    }

    private var redactedTitle: String {
        redactionReasons.contains(.privacy) ? (isTodo ? "할 일" : "진행 중인 작업") : title
    }

    private var accessibilityTitle: String {
        redactionReasons.contains(.privacy)
            ? (isTodo ? "할 일" : "진행 중인 작업")
            : "\(isTodo ? "할 일" : "진행 중인 작업") \(title)"
    }
}

private struct TaskLiveActivityCompactTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.redactionReasons) private var redactionReasons

    let title: String
    var isTodo = false
    let themeID: String?

    private var theme: TaskLiveActivityTheme {
        TaskLiveActivityTheme(themeID: themeID, colorScheme: colorScheme)
    }

    var body: some View {
        Text(redactionReasons.contains(.privacy) ? (isTodo ? "할 일" : "진행") : title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: 46, alignment: .leading)
            .privacySensitive()
            .accessibilityLabel(redactionReasons.contains(.privacy) ? (isTodo ? "할 일" : "진행 중인 작업") : "\(isTodo ? "할 일" : "진행 중인 작업") \(title)")
    }
}

private extension TaskActivityTimerPresentation {
    var timerText: Text {
        switch self {
        case .elapsed(let startedAt):
            return Text(startedAt, style: .timer)
        case .countdown(let interval):
            return Text(timerInterval: interval, countsDown: true, showsHours: false)
        case .paused(let remainingSeconds):
            // A stored duration is static. A past date interval can clamp to zero in
            // WidgetKit even with pauseTime, so use Foundation's duration formatting.
            return Text(Duration.seconds(remainingSeconds.rounded(.up)),
                        format: .time(pattern: .minuteSecond))
        case .invalid:
            return Text("—")
        case .todo:
            return Text("할 일")
        }
    }
}

private struct TaskLiveActivityTimeText: View {
    enum Style {
        case compact
        case minimal
        case expanded

        var font: Font {
            switch self {
            case .compact:
                return .caption2.weight(.semibold)
            case .minimal:
                // iOS 27 also uses minimal content in the narrow landscape island.
                // Date-based Text needs room for the complete HH:MM:SS value.
                return .system(size: 7, weight: .bold)
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

    let state: PlanBaseTaskActivityAttributes.ContentState
    let style: Style

    var body: some View {
        timerContent
            .id(state.timerIdentity)
#if DEBUG
            .onAppear {
                if case .invalid(let reason) = state.timerPresentation {
                    Logger(subsystem: "com.soraul2.easytask", category: "LiveTimer")
                        .error("Invalid timer payload: \(reason.rawValue, privacy: .public), revision: \(state.focusRevision ?? -1)")
                }
            }
#endif
    }

    @ViewBuilder
    private var timerContent: some View {
        if case .todo = state.timerPresentation {
            if style == .minimal {
                Image(systemName: "circle").font(.caption2.weight(.bold)).accessibilityLabel("할 일")
            } else {
                Text("할 일").font(style.font).foregroundStyle(.secondary)
            }
        } else {
            timerText
                .font(style.font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(style.minimumScaleFactor)
                .multilineTextAlignment(.trailing)
                .frame(width: style.timeWidth, alignment: .trailing)
                .accessibilityLabel(timerLabel)
                .accessibilityValue(timerText)
        }
    }

    private var timerText: Text { state.timerPresentation.timerText }

    private var timerLabel: String {
        switch state.timerPresentation {
        case .countdown: return "\(state.focusPhaseTitle) 남은 시간"
        case .paused: return "일시정지된 \(state.focusPhaseTitle) 남은 시간"
        case .elapsed: return "진행 시간"
        case .invalid: return "시간 확인 필요"
        case .todo: return "할 일"
        }
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
            .accessibilityHidden(true)
    }
}

private struct TaskLiveActivityLockScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.redactionReasons) private var redactionReasons

    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    private var theme: TaskLiveActivityTheme {
        TaskLiveActivityTheme(themeID: context.state.themeID, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(redactedTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if !context.state.isTodo {
                            TaskLiveActivityActiveDot(themeID: context.state.themeID)
                        }
                        TaskLiveActivityTimeText(
                            state: context.state,
                            style: .expanded
                        )
                    }

                    if context.state.isFocusSession {
                        Text("\(context.state.focusPhaseTitle) \(context.state.isFocusPaused ? "일시정지" : "중")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(context.state.progressText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
#if DEBUG
                if context.attributes.activityID == PlanBaseTaskActivityAttributes.timerAuditActivityID {
                    HStack {
                        Text("Native control")
                        context.state.timerPresentation.timerText
                    }
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("live-timer-native-control")
                }
#endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TaskLiveActivityActions(context: context)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 88)
        // A known opaque surface keeps accent controls readable over any wallpaper.
        .background(theme.surface)
        .activityBackgroundTint(theme.surface)
        .widgetURL(
            context.state.focusSessionID.flatMap(PlanBaseDeepLink.focusURL(sessionID:))
                ?? PlanBaseDeepLink.boardTodayURL()
        )
    }

    private var redactedTitle: String {
        redactionReasons.contains(.privacy) ? (context.state.isTodo ? "할 일" : "진행 중인 작업") : context.state.title
    }
}

private struct TaskLiveActivityActions: View {
    let context: ActivityViewContext<PlanBaseTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 7) {
            if let focusSessionID = context.state.focusSessionID,
               let focusRevision = context.state.focusRevision {
                if context.state.isFocusPaused {
                    Button(intent: ResumePlanBaseFocusIntent(
                        sessionID: focusSessionID,
                        revision: focusRevision
                    )) {
                        TaskLiveActivityActionLabel(
                            systemImage: "play.fill",
                            themeID: context.state.themeID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(context.state.isBreakTime ? "휴식 계속" : "다시 집중")
                } else {
                    Button(intent: PausePlanBaseFocusIntent(
                        sessionID: focusSessionID,
                        revision: focusRevision
                    )) {
                        TaskLiveActivityActionLabel(
                            systemImage: "pause.fill",
                            themeID: context.state.themeID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(context.state.focusPhaseTitle) 일시정지")
                }

                Button(intent: StopPlanBaseFocusIntent(
                    sessionID: focusSessionID,
                    revision: focusRevision
                )) {
                    TaskLiveActivityActionLabel(
                        systemImage: "stop.fill",
                        themeID: context.state.themeID
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(context.state.isBreakTime ? "휴식 건너뛰기" : "집중 마치기")
            } else if context.state.hasNextTask {
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
                .accessibilityLabel("표시할 작업 변경")
            }

            if context.state.isTodo {
                Button(intent: StartPlanBaseTaskIntent(
                    taskID: context.state.taskID, selectionToken: context.state.taskSessionID
                )) {
                    TaskLiveActivityActionLabel(systemImage: "play.fill", themeID: context.state.themeID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이 작업 시작")
            } else if !context.state.isFocusSession {
                completionControl
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
            .accessibilityLabel("이 작업 완료")
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
    let appearance: AppThemeAppearance

    init(themeID: String?, colorScheme: ColorScheme) {
        appearance = AppThemeAppearance(colorScheme: colorScheme)
        colors = AppThemePreset
            .preset(for: themeID)
            .colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var accent: Color {
        colors.accent(forSystemAppearance: appearance).color
    }

    var buttonBackground: Color {
        accent.opacity(0.18)
    }

    var surface: Color {
        ThemeColorToken(hex: appearance == .dark ? "#1C1C1E" : "#FFFFFF").color
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
