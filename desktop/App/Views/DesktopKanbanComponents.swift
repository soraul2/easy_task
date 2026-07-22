import SwiftData
import SwiftUI
import EasyTaskCore

struct KanbanColumn: View {
    var title: String
    var status: TaskStatus
    var tasks: [Task]
    var emptyTitle: String
    var selectedDayKey: String
    var onMove: (String, TaskStatus) -> Bool
    var onStatusChange: (Task, TaskStatus) -> Void
    var onTitleChange: (Task, String) -> Bool
    var onEdit: (Task) -> Void
    var onDelete: (Task) -> Void

    private var tint: Color {
        switch status {
        case .todo: AppTheme.columnTodo
        case .doing: AppTheme.columnDoing
        case .done: AppTheme.columnDone
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                Spacer()
            }

            LazyVStack(spacing: 10) {
                if tasks.isEmpty {
                    Text(emptyTitle)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task,
                            selectedDayKey: selectedDayKey,
                            onStatusChange: onStatusChange,
                            onTitleChange: onTitleChange,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                        .draggable(task.id.uuidString)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            return onMove(item, status)
        }
    }
}

struct TaskCard: View {
    @Bindable var task: Task
    var selectedDayKey: String
    var onStatusChange: (Task, TaskStatus) -> Void
    var onTitleChange: (Task, String) -> Bool
    var onEdit: (Task) -> Void
    var onDelete: (Task) -> Void
    @State private var draftTitle = ""
    @State private var isHovered = false
    @FocusState private var isTitleFocused: Bool

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var background: Color {
        switch status {
        case .todo: AppTheme.todo
        case .doing: AppTheme.doing
        case .done: AppTheme.done
        }
    }

    private var isLifted: Bool {
        isHovered || isTitleFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("작업", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.cardText)
                        .focused($isTitleFocused)
                        .onSubmit(commitTitle)
                        .onChange(of: isTitleFocused) { _, isFocused in
                            if !isFocused {
                                commitTitle()
                            }
                        }

                    if task.plannedDayKey < DayKey.today && status != .done {
                        Text("\(task.plannedDayKey)에서 이월")
                            .font(.caption)
                            .foregroundStyle(AppTheme.cardMutedText)
                    }

                    if let reminderAt = task.reminderAt {
                        Label(
                            reminderAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "bell"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.cardMutedText)
                        .lineLimit(1)
                    }

                    TaskCardChecklistSection(
                        taskID: task.id,
                        taskTitle: task.title,
                        isExpandable: status == .doing
                    )
                }
                Spacer()
                Button {
                    onEdit(task)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.cardMutedText)
                .help("작업 상세 편집")

                Button(role: .destructive) {
                    onDelete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.cardMutedText)
                .help("작업 삭제")
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(TaskStatus.allCases) { status in
                        Button(status.title) {
                            onStatusChange(task, status)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(status.title)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.cardText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.input.opacity(0.34), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.border.opacity(0.72), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()

                if let priority = task.priority.flatMap(TaskPriority.init(rawValue:)) {
                    Text(priority.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.cardText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.input.opacity(0.30), in: Capsule())
                }

                if let estimatedMinutes = task.estimatedMinutes {
                    Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.cardText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.input.opacity(0.30), in: Capsule())
                }

                Spacer()

                Label("드래그", systemImage: "hand.draw")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(AppTheme.cardMutedText)
                    .help("다른 컬럼으로 드래그해서 상태 변경")
            }
        }
        .padding(14)
        .background {
            LightweightTaskCardBackground(baseColor: background, isLifted: isLifted)
        }
        .foregroundStyle(AppTheme.cardText)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isLifted ? 1.01 : 1.0)
        .offset(y: isLifted ? -2 : 0)
        .shadow(color: .black.opacity(isLifted ? 0.28 : 0.20), radius: isLifted ? 14 : 8, x: 0, y: isLifted ? 10 : 5)
        .animation(.snappy(duration: 0.18), value: isLifted)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            draftTitle = task.title
        }
        .onChange(of: task.title) { _, title in
            if !isTitleFocused {
                draftTitle = title
            }
        }
    }

    private func commitTitle() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            draftTitle = task.title
            return
        }
        guard trimmedTitle != task.title else {
            draftTitle = trimmedTitle
            return
        }

        if onTitleChange(task, trimmedTitle) {
            draftTitle = trimmedTitle
        } else {
            draftTitle = task.title
        }
    }
}

private struct TaskCardChecklistSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var checklistItems: [TaskChecklistItem]
    @State private var isExpanded = false
    @State private var saveErrorMessage: String?

    let taskTitle: String
    let isExpandable: Bool

    init(taskID: UUID, taskTitle: String, isExpandable: Bool) {
        self.taskTitle = taskTitle
        self.isExpandable = isExpandable
        _checklistItems = Query(TaskChecklistService.descriptor(taskID: taskID))
    }

    private var progress: ChecklistProgress {
        TaskChecklistService.progress(in: checklistItems)
    }

    var body: some View {
        if !progress.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if isExpandable {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            progressLabel
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "체크리스트 접기" : "체크리스트 펼치기")
                    .accessibilityLabel("\(taskTitle) 체크리스트")
                    .accessibilityValue(
                        "\(progress.completedCount)개 완료, 전체 \(progress.totalCount)개, " +
                        (isExpanded ? "펼쳐짐" : "접힘")
                    )
                } else {
                    progressLabel
                }

                if isExpandable, isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(checklistItems) { item in
                            Button {
                                toggleCompletion(of: item)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: item.isCompleted
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .foregroundStyle(item.isCompleted
                                            ? AppTheme.event
                                            : AppTheme.cardMutedText)
                                    Text(item.title)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted
                                            ? AppTheme.cardMutedText
                                            : AppTheme.cardText)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.isCompleted ? "미완료로 변경" : "완료로 변경")
                            .accessibilityLabel("\(item.title) 체크리스트 항목")
                            .accessibilityValue(item.isCompleted ? "완료" : "미완료")
                        }
                    }
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .onChange(of: isExpandable) { _, canExpand in
                if !canExpand {
                    isExpanded = false
                }
            }
        }
    }

    private var progressLabel: some View {
        Label(
            "\(progress.completedCount)/\(progress.totalCount)",
            systemImage: progress.isComplete ? "checkmark.circle.fill" : "checklist"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.cardMutedText)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func toggleCompletion(of item: TaskChecklistItem) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskChecklistService.setCompletion(!item.isCompleted, for: item)
            }
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "체크 상태를 저장하지 못했습니다."
        }
    }
}

struct TaskChecklistProgressLabel: View {
    @Query private var checklistItems: [TaskChecklistItem]

    init(taskID: UUID) {
        _checklistItems = Query(TaskChecklistService.descriptor(taskID: taskID))
    }

    var body: some View {
        let progress = TaskChecklistService.progress(in: checklistItems)

        if !progress.isEmpty {
            Label(
                "\(progress.completedCount)/\(progress.totalCount)",
                systemImage: "checklist"
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .help("체크리스트 \(progress.completedCount)/\(progress.totalCount) 완료")
        }
    }
}

struct LightweightTaskCardBackground: View {
    var baseColor: Color
    var isLifted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(baseColor)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [
                            Color.white.opacity(isLifted ? 0.22 : 0.12),
                            Color.clear,
                            Color.black.opacity(isLifted ? 0.10 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border.opacity(isLifted ? 0.95 : 0.75), lineWidth: 1)
            }
    }
}
