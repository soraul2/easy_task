#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct BoardTaskList: View {
    var tasks: [TodoTask]
    var selectedStatus: TaskStatus
    var isEmbeddedInScrollView = false
    var onEdit: (TodoTask) -> Void
    var onStartFocus: (TodoTask) -> Void
    var onDelete: (TodoTask) -> Void
    var onSaveToLibrary: (TodoTask) -> Void
    var onStatusChange: (TodoTask, TaskStatus) -> Void
    var progressText: ((TodoTask, Date) -> String?)? = nil
    @State private var expandedTaskID: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Group {
                if isEmbeddedInScrollView {
                    LazyVStack(spacing: 12) {
                        taskRows(at: timeline.date)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, MobileLayout.bottomTabClearance)
                    .accessibilityIdentifier("board-task-list")
                } else {
                    List {
                        taskRows(at: timeline.date)
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("board-task-list")
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(height: MobileLayout.bottomTabClearance)
                    }
                }
            }
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

    @ViewBuilder
    private func taskRows(at date: Date) -> some View {
        if tasks.isEmpty {
            ContentUnavailableView(
                selectedStatus.emptyStateTitle,
                systemImage: selectedStatus.systemImage,
                description: Text(selectedStatus.emptyStateDescription)
            )
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("board-empty-\(selectedStatus.rawValue)")
        } else {
            if selectedStatus == .doing {
                MobileDoingFocusLauncher(
                    tasks: tasks,
                    onStartFocus: onStartFocus
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(tasks.filter { $0.modelContext != nil }) { task in
                MobileTaskRow(
                    task: task,
                    isChecklistExpanded: expandedTaskID == task.id,
                    onChecklistExpansionChange: { shouldExpand in
                        expandedTaskID = shouldExpand ? task.id : nil
                    },
                    onEdit: { onEdit(task) },
                    onStartFocus: { onStartFocus(task) },
                    onDelete: { onDelete(task) },
                    onSaveToLibrary: { onSaveToLibrary(task) },
                    onStatusChange: { onStatusChange(task, $0) },
                    progressText: progressText?(task, date)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }
}

private struct MobileDoingFocusLauncher: View {
    var tasks: [TodoTask]
    var onStartFocus: (TodoTask) -> Void

    var body: some View {
        Group {
            if tasks.count == 1, let task = tasks.first {
                Button {
                    onStartFocus(task)
                } label: {
                    launcherLabel(
                        detail: displayTitle(for: task),
                        trailingSystemImage: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(tasks) { task in
                        Button(displayTitle(for: task)) {
                            onStartFocus(task)
                        }
                    }
                } label: {
                    launcherLabel(
                        detail: "진행 중인 작업 \(tasks.count)개 중 선택",
                        trailingSystemImage: "chevron.down"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("board-doing-focus-launcher")
        .accessibilityLabel(tasks.count == 1
            ? "진행 중인 작업으로 집중 시작"
            : "집중할 진행 중 작업 선택")
    }

    private func launcherLabel(
        detail: String,
        trailingSystemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(AppTheme.event.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("집중 시작")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.cardText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.cardMutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: trailingSystemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.cardMutedText)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(AppTheme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.event.opacity(0.45), lineWidth: 1)
        }
    }

    private func displayTitle(for task: TodoTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없는 작업" : title
    }
}

// A disappearing row can render once more after SwiftData detaches a deleted model.
// Keep display values independent; actions still resolve through the board's persistence boundary.
private struct MobileTaskCardContent {
    let id: UUID
    let title: String
    let note: String?
    let status: String
    let priority: String?
    let tags: [String]
    let estimatedMinutes: Int?
    let reminderAt: Date?

    init(_ task: TodoTask) {
        id = task.id
        title = task.title
        note = task.note
        status = task.status
        priority = task.priority
        tags = task.tags
        estimatedMinutes = task.estimatedMinutes
        reminderAt = task.reminderAt
    }
}

private struct MobileTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var task: MobileTaskCardContent
    var isChecklistExpanded: Bool
    var onChecklistExpansionChange: (Bool) -> Void
    var onEdit: () -> Void
    var onStartFocus: () -> Void
    var onDelete: () -> Void
    var onSaveToLibrary: () -> Void
    var onStatusChange: (TaskStatus) -> Void
    var progressText: String?
    @Query private var checklistItemRows: [TaskChecklistItem]
    @State private var checklistSaveError: String?

    init(
        task: TodoTask,
        isChecklistExpanded: Bool,
        onChecklistExpansionChange: @escaping (Bool) -> Void,
        onEdit: @escaping () -> Void,
        onStartFocus: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSaveToLibrary: @escaping () -> Void,
        onStatusChange: @escaping (TaskStatus) -> Void,
        progressText: String? = nil
    ) {
        self.task = MobileTaskCardContent(task)
        self.isChecklistExpanded = isChecklistExpanded
        self.onChecklistExpansionChange = onChecklistExpansionChange
        self.onEdit = onEdit
        self.onStartFocus = onStartFocus
        self.onDelete = onDelete
        self.onSaveToLibrary = onSaveToLibrary
        self.onStatusChange = onStatusChange
        self.progressText = progressText
        _checklistItemRows = Query(TaskChecklistService.descriptor(taskID: task.id))
    }

    private var checklistItems: [TaskChecklistItem] {
        checklistItemRows.filter { $0.modelContext != nil }
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
        1
    }

    private var shadowOpacity: Double {
        switch status {
        case .todo: 0.025
        case .doing: 0.05
        case .done: 0.025
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

    private var reminderPresentation: (title: String, systemImage: String)? {
        guard let reminderAt = TaskReminderRules.normalizedDate(task.reminderAt) else {
            return nil
        }
        let formatted = reminderAt.formatted(date: .abbreviated, time: .shortened)
        if status == .done {
            return ("설정했던 알림 · \(formatted)", "bell.slash.fill")
        }
        if reminderAt <= Date() {
            return ("지난 알림 · \(formatted)", "bell.slash.fill")
        }
        return (formatted, "bell.fill")
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
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        taskTitleButton
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            taskActionButtons
                        }
                    }
                } else {
                    HStack(alignment: .top) {
                        taskTitleButton
                        taskActionButtons
                    }
                }
            }

            if hasDetailChips {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            detailChips
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                detailChips
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let progressText {
                Label(progressText, systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.cardMutedText)
                    .accessibilityLabel("진행 시간 \(progressText)")
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
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(accentColor.opacity(status == .doing ? 0.42 : 0.24), lineWidth: 1)
        }
        .shadow(
            color: accentColor.opacity(shadowOpacity),
            radius: 6,
            x: 0,
            y: 3
        )
        .shadow(color: .black.opacity(0.025), radius: 2, x: 0, y: 1)
    }

    private var taskTitleButton: some View {
        Button(action: onEdit) { taskText.frame(minHeight: 44, alignment: .topLeading).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(task.title) 작업 편집")
            .accessibilityLabel("\(task.title) 작업 편집")
            .accessibilityValue(task.note ?? "")
            .accessibilityHint("제목, 메모와 체크리스트를 확인하고 편집해요")
    }

    private var taskText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                .font(.headline)
                .strikethrough(status == .done)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(status == .done
                    ? AppTheme.cardMutedText
                    : AppTheme.cardText)
            if let note = task.note,
               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.cardMutedText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailChips: some View {
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
        if let reminderPresentation {
            MobileTaskDetailChip(
                title: reminderPresentation.title,
                systemImage: reminderPresentation.systemImage
            )
            .accessibilityIdentifier("\(task.title) 알림 기록")
        }
        if status != .doing {
            MobileChecklistProgressChip(progress: checklistProgress)
                .accessibilityIdentifier("\(task.title)-checklist-progress")
        }
        ForEach(visibleTags, id: \.self) { tag in
            MobileTaskDetailChip(title: "#\(tag)", systemImage: "tag")
        }
    }

    private var taskActionButtons: some View {
        HStack(spacing: 8) {
            if status != .done {
                Button(action: onStartFocus) {
                    Image(systemName: "timer")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(AppTheme.panel.opacity(0.78), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("\(task.title) 집중 시작")
                .accessibilityLabel("\(task.title) 집중 시작")
            }

            Menu {
                Button("작업 편집", systemImage: "pencil", action: onEdit)
                Button("자주 쓰는 작업으로 저장", systemImage: "bookmark", action: onSaveToLibrary)
                Button("작업 삭제", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(AppTheme.panel.opacity(0.78), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("\(task.title) 작업 메뉴")
            .accessibilityLabel("\(task.title) 작업 메뉴")
        }
        .foregroundStyle(AppTheme.cardMutedText)
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
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
            .accessibilityIdentifier("\(task.title)-checklist-progress")
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
                                        ? AppTheme.accent
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                minHeight: 36,
                alignment: .leading
            )
            .background(
                AppTheme.panel.opacity(0.52),
                in: RoundedRectangle(
                    cornerRadius: dynamicTypeSize.isAccessibilitySize ? 10 : 18
                )
            )
    }
}

#endif
