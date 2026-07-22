#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
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
    @State private var expandedTaskID: UUID?

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
                        isChecklistExpanded: expandedTaskID == task.id,
                        onChecklistExpansionChange: { shouldExpand in
                            expandedTaskID = shouldExpand ? task.id : nil
                        },
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
        .onChange(of: selectedStatus) { _, status in
            if status != .doing {
                expandedTaskID = nil
            }
        }
        .onChange(of: tasks.map(\.id)) { _, taskIDs in
            if let expandedTaskID, !taskIDs.contains(expandedTaskID) {
                self.expandedTaskID = nil
            }
        }
    }
}

private struct MobileTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    var task: TodoTask
    var isChecklistExpanded: Bool
    var onChecklistExpansionChange: (Bool) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onStatusChange: (TaskStatus) -> Void
    @Query private var checklistItems: [TaskChecklistItem]
    @State private var checklistSaveError: String?

    init(
        task: TodoTask,
        isChecklistExpanded: Bool,
        onChecklistExpansionChange: @escaping (Bool) -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onStatusChange: @escaping (TaskStatus) -> Void
    ) {
        self.task = task
        self.isChecklistExpanded = isChecklistExpanded
        self.onChecklistExpansionChange = onChecklistExpansionChange
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onStatusChange = onStatusChange
        _checklistItems = Query(TaskChecklistService.descriptor(taskID: task.id))
    }

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

    private var checklistProgress: ChecklistProgress {
        TaskChecklistService.progress(in: checklistItems)
    }

    private var hasDetailChips: Bool {
        priority != nil ||
            task.estimatedMinutes != nil ||
            task.reminderAt != nil ||
            !visibleTags.isEmpty ||
            (status != .doing && !checklistProgress.isEmpty)
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
                            .frame(width: 44, height: 44)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(task.title) 작업 편집")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(task.title) 작업 삭제")
                }
                .foregroundStyle(.secondary)
            }

            if hasDetailChips {
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
                        if status != .doing {
                            MobileChecklistProgressChip(progress: checklistProgress)
                        }
                        ForEach(visibleTags, id: \.self) { tag in
                            MobileTaskDetailChip(title: "#\(tag)", systemImage: "tag")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if status == .doing, !checklistProgress.isEmpty {
                checklistSection
            }

            MobileTaskStatusSlider(
                taskTitle: task.title,
                status: status,
                accentColor: accentColor
            ) { nextStatus in
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

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    onChecklistExpansionChange(!isChecklistExpanded)
                }
            } label: {
                HStack(spacing: 8) {
                    Label(
                        "\(checklistProgress.completedCount)/\(checklistProgress.totalCount)",
                        systemImage: checklistProgress.isComplete
                            ? "checkmark.circle.fill"
                            : "checklist"
                    )
                    .font(.caption.weight(.semibold))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isChecklistExpanded ? 180 : 0))
                }
                .foregroundStyle(AppTheme.cardMutedText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.panel.opacity(0.52), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("checklist-progress")
            .accessibilityLabel("\(task.title) 체크리스트")
            .accessibilityValue(
                "\(checklistProgress.completedCount)개 완료, " +
                "전체 \(checklistProgress.totalCount)개, " +
                (isChecklistExpanded ? "펼쳐짐" : "접힘")
            )
            .accessibilityHint(isChecklistExpanded ? "두 번 탭하여 접기" : "두 번 탭하여 펼치기")

            if isChecklistExpanded {
                VStack(spacing: 0) {
                    ForEach(checklistItems) { item in
                        Button {
                            toggleChecklistItem(item)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: item.isCompleted
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .foregroundStyle(item.isCompleted
                                        ? AppTheme.event
                                        : AppTheme.cardMutedText)
                                Text(item.title)
                                    .font(.subheadline)
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted
                                        ? AppTheme.cardMutedText
                                        : AppTheme.cardText)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title) 체크리스트 항목")
                        .accessibilityValue(item.isCompleted ? "완료" : "미완료")
                        .accessibilityHint(item.isCompleted
                            ? "두 번 탭하여 미완료로 변경"
                            : "두 번 탭하여 완료로 변경")

                        if item.id != checklistItems.last?.id {
                            Divider()
                                .overlay(AppTheme.border.opacity(0.35))
                        }
                    }
                }
                .background(AppTheme.input.opacity(0.44), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let checklistSaveError {
                Label(checklistSaveError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private func toggleChecklistItem(_ item: TaskChecklistItem) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskChecklistService.setCompletion(!item.isCompleted, for: item)
            }
            checklistSaveError = nil
        } catch {
            checklistSaveError = "체크 상태를 저장하지 못했습니다"
        }
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
            .accessibilityIdentifier("board-status-notice")
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MobileTaskStatusSlider: View {
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
                        Button {
                            updateStatus(nextStatus)
                        } label: {
                            Text(nextStatus.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(nextStatus == status
                                    ? AppTheme.eventText
                                    : AppTheme.cardText)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(taskTitle) \(nextStatus.title) 상태")
                        .accessibilityAddTraits(nextStatus == status ? .isSelected : [])
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        updateStatus(status(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 40)
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

}

#endif
