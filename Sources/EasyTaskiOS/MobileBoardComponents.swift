#if os(iOS)
import EasyTaskCore
import Foundation
import SwiftUI

struct BoardHeader: View {
    @Binding var selectedDate: Date
    var isTodayBoard: Bool
    var selectedDayKey: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                selectedDate = DayKey.addingDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 날짜")

            VStack(alignment: .leading, spacing: 2) {
                Text(DayKey.display(selectedDate))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(isTodayBoard ? "오늘 보드" : selectedDayKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("오늘") {
                selectedDate = DayKey.startOfDay(for: Date())
            }
            .buttonStyle(.bordered)

            Button {
                selectedDate = DayKey.addingDays(1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("다음 날짜")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

struct BoardEventStrip: View {
    var events: [CalendarEvent]

    var body: some View {
        if !events.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        Label(event.title, systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(CalendarEventPalette.color(for: event.color).opacity(0.18), in: Capsule())
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
        }
    }
}

struct BoardQuickAdd: View {
    @Binding var title: String
    var onAdd: () -> Void

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("해당 날짜에 할 일 입력", text: $title)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit(onAdd)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.headline)
            }
            .disabled(!canAdd)
            .accessibilityLabel("작업 추가")
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

struct BoardStatusPicker: View {
    @Binding var selectedStatus: TaskStatus

    var body: some View {
        Picker("상태", selection: $selectedStatus) {
            ForEach(TaskStatus.allCases) { status in
                Text(status.title).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct BoardTaskList: View {
    var tasks: [TodoTask]
    var selectedStatus: TaskStatus
    var onEdit: (TodoTask) -> Void
    var onDelete: (TodoTask) -> Void
    var onStatusChange: (TodoTask, TaskStatus) -> Void

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "\(selectedStatus.title) 작업 없음",
                    systemImage: "checklist",
                    description: Text("빠른 입력이나 템플릿으로 작업을 추가하세요.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(tasks) { task in
                    MobileTaskRow(
                        task: task,
                        onEdit: { onEdit(task) },
                        onDelete: { onDelete(task) },
                        onStatusChange: { onStatusChange(task, $0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: MobileLayout.bottomTabClearance)
        }
    }
}

private struct MobileTaskRow: View {
    var task: TodoTask
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onStatusChange: (TaskStatus) -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var cardColor: Color {
        switch status {
        case .todo: AppTheme.todo
        case .doing: AppTheme.doing
        case .done: AppTheme.done
        }
    }

    private var accentColor: Color {
        switch status {
        case .todo: AppTheme.secondaryText
        case .doing: AppTheme.event
        case .done: AppTheme.done
        }
    }

    private var cardFillOpacity: Double {
        status == .done ? 0.76 : 0.96
    }

    private var shadowOpacity: Double {
        switch status {
        case .todo: 0.10
        case .doing: 0.20
        case .done: 0.12
        }
    }

    private var priority: TaskPriority? {
        task.priority.flatMap(TaskPriority.init(rawValue:))
    }

    private var visibleTags: [String] {
        task.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasDetails: Bool {
        priority != nil ||
            task.estimatedMinutes != nil ||
            task.reminderAt != nil ||
            !visibleTags.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(AppTheme.cardText)
                    if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.cardMutedText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("작업 편집")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("작업 삭제")
                }
                .foregroundStyle(.secondary)
            }

            if hasDetails {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let priority {
                            MobileTaskDetailChip(
                                title: priority.title,
                                systemImage: "flag.fill"
                            )
                        }
                        if let estimatedMinutes = task.estimatedMinutes {
                            MobileTaskDetailChip(
                                title: EstimatedTimeFormatter.short(estimatedMinutes),
                                systemImage: "clock"
                            )
                        }
                        if let reminderAt = task.reminderAt {
                            MobileTaskDetailChip(
                                title: reminderAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ),
                                systemImage: "bell.fill"
                            )
                        }
                        ForEach(visibleTags, id: \.self) { tag in
                            MobileTaskDetailChip(title: "#\(tag)", systemImage: "tag")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MobileTaskStatusSlider(status: status, accentColor: accentColor) { nextStatus in
                onStatusChange(nextStatus)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(cardColor.opacity(cardFillOpacity))
        }
        .shadow(color: accentColor.opacity(shadowOpacity), radius: status == .doing ? 18 : 12, x: 0, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

private struct MobileTaskDetailChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.panel.opacity(0.52), in: Capsule())
    }
}

struct MobileStatusNotice: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "arrow.right.circle.fill")
            .font(.caption.weight(.bold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(AppTheme.eventText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.event.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MobileTaskStatusSlider: View {
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
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = width / CGFloat(max(statuses.count, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.input.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border.opacity(0.26), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.94))
                    .frame(width: max(segmentWidth - 6, 0), height: 34)
                    .offset(x: CGFloat(selectedIndex) * segmentWidth + 3)
                    .shadow(color: accentColor.opacity(0.22), radius: 8, x: 0, y: 3)
                    .animation(.snappy(duration: 0.18), value: selectedIndex)

                HStack(spacing: 0) {
                    ForEach(statuses) { nextStatus in
                        Text(nextStatus.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(nextStatus == status ? AppTheme.eventText : AppTheme.cardText)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        updateStatus(status(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("작업 상태")
        .accessibilityValue(status.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                updateStatus(status(offsetBy: 1))
            case .decrement:
                updateStatus(status(offsetBy: -1))
            @unknown default:
                break
            }
        }
    }

    private func updateStatus(_ nextStatus: TaskStatus) {
        guard nextStatus != status else { return }
        onChange(nextStatus)
    }

    private func status(at x: CGFloat, width: CGFloat) -> TaskStatus {
        guard width > 0 else { return status }
        let segmentWidth = width / CGFloat(max(statuses.count, 1))
        let index = min(max(Int(x / segmentWidth), 0), statuses.count - 1)
        return statuses[index]
    }

    private func status(offsetBy offset: Int) -> TaskStatus {
        let index = min(max(selectedIndex + offset, 0), statuses.count - 1)
        return statuses[index]
    }
}

#endif
