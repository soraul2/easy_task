#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileStatusNotice: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var message: String
    var tone: MobileNoticeTone = .success
    var destinationTitle: String? = nil
    var onShowDestination: () -> Void = {}
    var onUndo: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: tone.symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .foregroundStyle(tone == .error ? Color.red : AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message)
                .accessibilityIdentifier("board-status-notice")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { actions }
            } else {
                HStack(spacing: 16) { actions }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .onChange(of: message) { _, message in AccessibilityNotification.Announcement(message).post() }
    }

    @ViewBuilder
    private var actions: some View {
        if let destinationTitle {
            Button(action: onShowDestination) {
                Text(destinationTitle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("board-status-destination")
        }
        if let onUndo {
            Button(action: onUndo) {
                Text("완료 실행 취소")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("board-completion-undo")
        }
    }
}

struct MobileTaskStatusSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var taskTitle: String
    var status: TaskStatus
    var accentColor: Color
    var onChange: (TaskStatus) -> Void

    private var statuses: [TaskStatus] {
        TaskStatus.allCases
    }

    private var selectedIndex: Int {
        statuses.firstIndex(of: status) ?? 0
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityStatusMenu
            } else {
                compactStatusSlider
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(taskTitle) 상태 변경")
    }

    private var accessibilityStatusMenu: some View {
        Menu {
            ForEach(statuses) { nextStatus in
                Button {
                    updateStatus(nextStatus)
                } label: {
                    Label(nextStatus.title, systemImage: nextStatus.systemImage)
                }
                .disabled(nextStatus == status)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: status.systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("작업 상태")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(AppTheme.input.opacity(0.60), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border.opacity(0.50), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("\(taskTitle)-status-menu")
        .accessibilityLabel("\(taskTitle) 작업 상태")
        .accessibilityValue(status.title)
        .accessibilityHint("두 번 탭하여 작업 상태 선택")
    }

    private var compactStatusSlider: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = width / CGFloat(max(statuses.count, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.input.opacity(0.60))

                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.selectedTab)
                    .frame(width: max(segmentWidth - 6, 0), height: 42)
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    .offset(x: CGFloat(selectedIndex) * segmentWidth + 3)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selectedIndex)

                HStack(spacing: 0) {
                    ForEach(statuses) { nextStatus in
                        Button {
                            updateStatus(nextStatus)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: nextStatus.systemImage)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(nextStatus == status ? accentColor : AppTheme.secondaryText)
                                Text(nextStatus.title)
                                    .font(.caption.weight(nextStatus == status ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.90)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(nextStatus == status
                                ? AppTheme.primaryText
                                : AppTheme.secondaryText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MobilePressFeedbackButtonStyle())
                        .accessibilityLabel("\(taskTitle) \(nextStatus.title) 상태")
                        .accessibilityValue(nextStatus == status ? "현재 상태" : "변경 가능")
                        .accessibilityHint(nextStatus == status
                            ? "현재 선택된 상태예요"
                            : "두 번 탭하여 \(nextStatus.title)로 변경해요")
                        .accessibilityAddTraits(nextStatus == status ? .isSelected : [])
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 48)
    }

    private func updateStatus(_ nextStatus: TaskStatus) {
        guard nextStatus != status else { return }
        onChange(nextStatus)
    }
}

struct MobilePressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}

#endif
