import SwiftData
import SwiftUI
import PlanBaseCore

struct KanbanColumn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var status: TaskStatus
    var tasks: [Task]
    var emptyTitle: String
    var selectedDayKey: String
    var onMove: (String, TaskStatus) -> Bool
    var onStatusChange: (Task, TaskStatus) -> Void
    var onTitleChange: (Task, String) -> Bool
    var onEdit: (Task) -> Void
    var onStartFocus: (Task) -> Void
    var onDelete: (Task) -> Void
    var onSaveToLibrary: (Task) -> Void
    var progressText: ((Task, Date) -> String?)? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isDropTargeted ? "arrow.down.circle" : status.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status == .doing ? AppTheme.accent : AppTheme.secondaryText)

                Text(isDropTargeted ? "\(title) 영역으로 이동" : title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                if !isDropTargeted {
                    Text("\(tasks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityLabel("\(tasks.count)개 작업")
                }

                Spacer(minLength: 4)

                if status == .doing, !tasks.isEmpty, !isDropTargeted {
                    doingFocusLauncher
                }
            }
            .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            .padding(.horizontal, 2)
            .help(status.guidanceText)

            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                LazyVStack(spacing: 10) {
                    if tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(status.emptyStateTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.primaryText)
                            Text(status.emptyStateDescription)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(tasks) { task in
                            TaskCard(
                                task: task,
                                selectedDayKey: selectedDayKey,
                                onStatusChange: onStatusChange,
                                onTitleChange: onTitleChange,
                                onEdit: onEdit,
                                onStartFocus: onStartFocus,
                                onDelete: onDelete,
                                onSaveToLibrary: onSaveToLibrary,
                                progressText: progressText?(task, timeline.date)
                            )
                            .draggable(task.instanceID.uuidString)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.input.opacity(0.42), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isDropTargeted ? AppTheme.accent : .clear, lineWidth: 2)
        }
        .dropDestination(for: String.self) { items, _ in
            isDropTargeted = false
            guard let item = items.first else { return false }
            return onMove(item, status)
        } isTargeted: { isTargeted in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                isDropTargeted = isTargeted
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) 컬럼, \(tasks.count)개 작업")
    }

    @ViewBuilder
    private var doingFocusLauncher: some View {
        if tasks.count == 1, let task = tasks.first {
            Button { onStartFocus(task) } label: {
                focusLauncherLabel
            }
            .buttonStyle(.plain)
            .help("\(displayTitle(for: task)) 집중 시작")
            .accessibilityLabel("진행 중인 작업으로 집중 시작")
        } else {
            Menu {
                ForEach(tasks) { task in
                    Button(displayTitle(for: task)) { onStartFocus(task) }
                }
            } label: {
                focusLauncherLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("집중할 진행 중 작업 선택")
            .accessibilityLabel("집중할 진행 중 작업 선택")
        }
    }

    private var focusLauncherLabel: some View {
        Label("집중 시작", systemImage: "timer")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 6)
            .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            .contentShape(Rectangle())
    }

    private func displayTitle(for task: Task) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없는 작업" : title
    }
}

struct TaskCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var task: Task
    var selectedDayKey: String
    var onStatusChange: (Task, TaskStatus) -> Void
    var onTitleChange: (Task, String) -> Bool
    var onEdit: (Task) -> Void
    var onStartFocus: (Task) -> Void
    var onDelete: (Task) -> Void
    var onSaveToLibrary: (Task) -> Void
    var progressText: String?
    @State private var draftTitle = ""
    @State private var isHovered = false
    @FocusState private var isTitleFocused: Bool

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var isLifted: Bool {
        isHovered || isTitleFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                TextField("작업", text: $draftTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status == .done ? AppTheme.secondaryText : AppTheme.primaryText)
                    .strikethrough(status == .done && !isTitleFocused)
                    .lineLimit(1...4)
                    .frame(maxWidth: .infinity, minHeight: PlanBaseControlMetrics.minimumTargetSize, alignment: .topLeading)
                    .focused($isTitleFocused)
                    .onSubmit(commitTitle)
                    .onChange(of: isTitleFocused) { _, isFocused in
                        if !isFocused { commitTitle() }
                    }

                Menu {
                    Button("작업 편집", systemImage: "square.and.pencil") { onEdit(task) }
                    Button("자주 쓰는 작업으로 저장", systemImage: "bookmark") { onSaveToLibrary(task) }
                    Divider()
                    Button("작업 삭제", systemImage: "trash", role: .destructive) { onDelete(task) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                               height: PlanBaseControlMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("작업 편집 및 메뉴")
                .accessibilityLabel("\(task.title) 작업 메뉴")
            }

            if task.plannedDayKey < DayKey.today && status != .done {
                Label("\(task.plannedDayKey)에서 이월", systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let priority = task.priority.flatMap(TaskPriority.init(rawValue:)) {
                Label(priority.title, systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if task.estimatedMinutes != nil || progressText != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { timeDetails }
                    VStack(alignment: .leading, spacing: 5) { timeDetails }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }

            if let reminderAt = task.reminderAt {
                Label(reminderText(for: reminderAt), systemImage: reminderSystemImage(for: reminderAt))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TaskCardChecklistSection(
                taskID: task.id,
                taskTitle: task.title,
                isExpandable: status == .doing
            )

            Rectangle()
                .fill(AppTheme.border.opacity(0.45))
                .frame(height: 1)
                .padding(.top, 2)

            HStack(spacing: 6) {
                statusMenu
                Spacer(minLength: 0)

                if status != .done {
                    Button { onStartFocus(task) } label: {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                                   height: PlanBaseControlMetrics.minimumTargetSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("이 작업으로 집중 시작")
                    .accessibilityLabel("\(task.title) 집중 시작")
                }

                Button { onStatusChange(task, status.primaryActionStatus) } label: {
                    Label(status.primaryActionTitle, systemImage: status.primaryActionSystemImage)
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                }
                .buttonStyle(PlanBaseButtonStyle(status == .doing ? .primary : .secondary))
                .help("\(task.title) 작업을 \(status.primaryActionStatus.title) 상태로 변경")
                .accessibilityLabel("\(task.title) \(status.primaryActionTitle)")
            }
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isTitleFocused ? AppTheme.accent : (status == .doing ? AppTheme.accent.opacity(0.36) : AppTheme.border.opacity(0.70)),
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .offset(y: isLifted && !reduceMotion ? -1 : 0)
        .shadow(color: .black.opacity(isLifted ? 0.08 : 0.025), radius: isLifted ? 8 : 3, y: isLifted ? 4 : 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isLifted)
        .onHover { isHovered = $0 }
        .onAppear { draftTitle = task.title }
        .onChange(of: task.title) { _, title in
            if !isTitleFocused { draftTitle = title }
        }
    }

    @ViewBuilder
    private var timeDetails: some View {
        if let estimatedMinutes = task.estimatedMinutes {
            Label("예상 \(EstimatedTimeFormatter.short(estimatedMinutes))", systemImage: "clock")
                .fixedSize(horizontal: false, vertical: true)
        }
        if let progressText {
            Label(progressText, systemImage: "clock.arrow.circlepath")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("진행 상태로 둔 시간, \(progressText)")
                .accessibilityHint("집중 타이머의 집중 시간과 별도로 기록해요")
                .help("진행 상태로 둔 누적 시간이에요. 집중 타이머의 집중 시간과는 달라요.")
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { nextStatus in
                Button { onStatusChange(task, nextStatus) } label: {
                    Label(nextStatus.title, systemImage: nextStatus == status ? "checkmark" : nextStatus.systemImage)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status == .doing ? AppTheme.accent : AppTheme.secondaryText)
                Text(status.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("현재 \(status.title) · 다른 상태로 변경")
        .accessibilityLabel("\(task.title) 상태")
        .accessibilityValue(status.title)
        .accessibilityHint("다른 상태를 선택할 수 있어요")
    }

    private func reminderText(for reminderAt: Date) -> String {
        let formatted = reminderAt.formatted(date: .abbreviated, time: .shortened)
        if status == .done { return "설정했던 알림 · \(formatted)" }
        if reminderAt <= Date() { return "지난 알림 · \(formatted)" }
        return formatted
    }

    private func reminderSystemImage(for reminderAt: Date) -> String {
        status == .done || reminderAt <= Date() ? "bell.slash" : "bell"
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
        draftTitle = onTitleChange(task, trimmedTitle) ? trimmedTitle : task.title
    }
}

private struct TaskCardChecklistSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            progressLabel
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
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
                                            ? AppTheme.accent
                                            : AppTheme.secondaryText)
                                    Text(item.title)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted
                                            ? AppTheme.secondaryText
                                            : AppTheme.primaryText)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity,
                                       minHeight: PlanBaseControlMetrics.minimumTargetSize,
                                       alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.isCompleted ? "미완료로 변경" : "완료로 변경")
                            .accessibilityLabel("\(item.title) 체크리스트 항목")
                            .accessibilityValue(item.isCompleted ? "완료" : "미완료")
                        }
                    }
                    .padding(.leading, 2)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(saveErrorMessage)
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
        .foregroundStyle(AppTheme.secondaryText)
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
