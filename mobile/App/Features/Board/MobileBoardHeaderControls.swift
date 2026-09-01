#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct BoardHeader: View {
    @Binding var selectedDate: Date
    var isTodayBoard: Bool
    var selectedDayKey: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    dateSummary
                    HStack(spacing: 12) {
                        previousDayButton
                        Spacer(minLength: 8)
                        todayButton
                        Spacer(minLength: 8)
                        nextDayButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    previousDayButton
                    dateSummary
                    Spacer()
                    todayButton
                    nextDayButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var dateSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DayKey.display(selectedDate))
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("board-date-title")
            Text(isTodayBoard ? "오늘 보드" : selectedDayKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var previousDayButton: some View {
        Button {
            selectedDate = DayKey.addingDays(-1, to: selectedDate)
        } label: {
            Image(systemName: "chevron.left")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("이전 날짜")
    }

    private var todayButton: some View {
        Button("오늘") {
            selectedDate = DayKey.startOfDay(for: Date())
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
    }

    private var nextDayButton: some View {
        Button {
            selectedDate = DayKey.addingDays(1, to: selectedDate)
        } label: {
            Image(systemName: "chevron.right")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("다음 날짜")
    }
}

struct BoardEventStrip: View {
    var events: [CalendarEvent]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !events.isEmpty {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events) { event in
                            accessibleEventRow(event)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(events) { event in
                                compactEventLabel(event)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func accessibleEventRow(_ event: CalendarEvent) -> some View {
        Label {
            Text(event.title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("board-event-summary")
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            CalendarEventPalette.color(for: event.color).opacity(0.18),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .foregroundStyle(AppTheme.primaryText)
    }

    private func compactEventLabel(_ event: CalendarEvent) -> some View {
        Label(event.title, systemImage: "calendar")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                CalendarEventPalette.color(for: event.color).opacity(0.18),
                in: Capsule()
            )
            .foregroundStyle(AppTheme.primaryText)
    }
}

struct BoardQuickAdd: View {
    @Binding var title: String
    let focusRequestID: UUID?
    var onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isTitleFocused: Bool

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    titleField
                    Button(action: submit) {
                        Label("작업 추가", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
                    .accessibilityLabel("작업 추가")
                }
            } else {
                HStack(spacing: 8) {
                    titleField
                    Button(action: submit) {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .disabled(!canAdd)
                    .accessibilityLabel("작업 추가")
                }
            }
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTitleFocused ? AppTheme.event : AppTheme.border.opacity(0.78),
                    lineWidth: isTitleFocused ? 2 : 1.25
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: focusRequestID) { _, requestID in
            guard requestID != nil else { return }
            isTitleFocused = true
        }
    }

    private var titleField: some View {
        TextField(
            dynamicTypeSize.isAccessibilitySize ? "할 일 입력" : "해당 날짜에 할 일 입력",
            text: $title
        )
        .textFieldStyle(.plain)
        .focused($isTitleFocused)
        .submitLabel(.done)
        .onSubmit(submit)
        .accessibilityLabel("해당 날짜에 할 일 입력")
    }

    private func submit() {
        guard canAdd else { return }
        onAdd()
        if title.isEmpty {
            isTitleFocused = false
        }
    }
}

struct BoardStatusPicker: View {
    @Binding var selectedStatus: TaskStatus
    var taskCount: (TaskStatus) -> Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityStatusMenu
            } else {
                HStack(spacing: 8) {
                    statusButtons
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("보드 상태 필터")
    }

    private var accessibilityStatusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    selectedStatus = status
                } label: {
                    Label(
                        "\(status.title), \(taskCount(status))개",
                        systemImage: status.systemImage
                    )
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedStatus.systemImage)
                Text(selectedStatus.title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(taskCount(selectedStatus))개")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier("board-status-filter-menu")
        .accessibilityLabel("보드 상태 필터")
        .accessibilityValue("\(selectedStatus.title), \(taskCount(selectedStatus))개")
        .accessibilityHint("두 번 탭하여 표시할 작업 상태 선택")
    }

    @ViewBuilder
    private var statusButtons: some View {
        ForEach(TaskStatus.allCases) { status in
            BoardStatusFilterButton(
                status: status,
                count: taskCount(status),
                isSelected: status == selectedStatus
            ) {
                selectedStatus = status
            }
        }
    }
}

private struct BoardStatusFilterButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var status: TaskStatus
    var count: Int
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    countLabel
                    selectionIndicator
                }
                Text(status.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
            .background(
                isSelected ? AppTheme.panel : AppTheme.input.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? accent : AppTheme.border.opacity(0.45),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: isSelected ? accent.opacity(0.16) : .clear,
                radius: 10,
                y: 5
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(MobilePressFeedbackButtonStyle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isSelected)
        .accessibilityIdentifier("board-status-filter-\(status.rawValue)")
        .accessibilityLabel("\(status.title), \(count)개")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .accessibilityHint("\(status.title) 작업을 보여줘요")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
    }

    private var countLabel: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.selectedTab.opacity(isSelected ? 0.46 : 0.20), in: Capsule())
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
        }
    }

    private var accent: Color {
        switch status {
        case .todo: AppTheme.secondaryText
        case .doing: AppTheme.event
        case .done: AppTheme.done
        }
    }
}

#endif
