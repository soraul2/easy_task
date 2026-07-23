import SwiftData
import SwiftUI
import PlanBaseCore

private struct PendingDesktopDetailCompletion {
    var taskID: UUID
    var title: String
    var reminderAt: Date
}

struct TaskDetailSheet: View {
    var task: Task
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var status: TaskStatus
    @State private var plannedDate: Date
    @State private var selectedPriority: TaskPriority?
    @State private var tagsText: String
    @State private var estimatedMinutesText: String
    @State private var checklistDrafts: [ChecklistItemDraft] = []
    @State private var newChecklistTitle = ""
    @State private var isChecklistLoaded = false
    @State private var checklistLoadFailureMessage: String?
    @State private var persistenceFailureMessage: String?
    @State private var pendingTaskCompletion: PendingDesktopDetailCompletion?
    @FocusState private var isNewChecklistItemFocused: Bool

    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _selectedPriority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isChecklistLoaded
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DetailFieldLabel("제목")
                    TextField("작업 제목", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(10)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }

                    DetailFieldLabel("보드 날짜")
                    DatePicker("보드 날짜", selection: $plannedDate, displayedComponents: .date)
                        .labelsHidden()

                    if let reminderAt = task.reminderAt {
                        DetailFieldLabel(reminderFieldTitle(for: reminderAt))
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                reminderAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: reminderSystemImage(for: reminderAt)
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                            Text(
                                "알림은 iPhone에서 설정·실행됩니다. " +
                                    "Mac에서는 동기화된 시각만 표시합니다."
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    DetailFieldLabel("상태")
                    Picker("상태", selection: $status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    DetailFieldLabel("메모")
                    TextEditor(text: $note)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }

                    checklistEditor

                    DetailFieldLabel("우선순위")
                    Picker("우선순위", selection: $selectedPriority) {
                        Text("없음").tag(nil as TaskPriority?)
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority as TaskPriority?)
                        }
                    }
                    .pickerStyle(.segmented)

                    DetailFieldLabel("예상 시간")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach([15, 30, 60, 120], id: \.self) { minutes in
                                Button(EstimatedTimeFormatter.short(minutes)) {
                                    estimatedMinutesText = String(minutes)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button("없음") {
                                estimatedMinutesText = ""
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            TextField("직접 입력", text: $estimatedMinutesText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("분")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(10)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                    }

                    DetailFieldLabel("태그")
                    TextField("쉼표로 구분해서 입력", text: $tagsText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(10)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                }
                .padding(22)
            }

            Divider()

            footer
                .padding(22)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 560, idealHeight: 720)
        .background(AppTheme.panel)
        .task(id: task.id) {
            loadChecklist()
        }
        .alert(
            "예정된 알림이 있습니다",
            isPresented: Binding(
                get: { pendingTaskCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingTaskCompletion = nil
                    }
                }
            ),
            presenting: pendingTaskCompletion
        ) { pending in
            Button("완료하기", role: .destructive) {
                pendingTaskCompletion = nil
                save(taskID: pending.taskID)
            }
            Button("취소", role: .cancel) {}
        } message: { pending in
            Text(
                "\"\(pending.title)\" 작업을 완료하면 " +
                    "\(pending.reminderAt.formatted(date: .abbreviated, time: .shortened)) " +
                    "iPhone 예약 알림이 중지됩니다. " +
                    "알림 설정 기록은 계속 유지됩니다."
            )
        }
        .persistenceFailureAlert(message: $persistenceFailureMessage)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("작업 상세 편집")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("\(task.plannedDayKey)에 배치된 작업")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("편집 취소")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("취소") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button {
                requestSave()
            } label: {
                Label("저장", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var checklistEditor: some View {
        HStack(spacing: 8) {
            DetailFieldLabel("체크리스트")

            if isChecklistLoaded, !checklistDrafts.isEmpty {
                let completedCount = checklistDrafts.filter(\.isCompleted).count
                Text("\(completedCount)/\(checklistDrafts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }

        if isChecklistLoaded {
            VStack(spacing: 8) {
                ForEach($checklistDrafts) { $draft in
                    ChecklistDraftEditorRow(
                        draft: $draft,
                        onDelete: {
                            deleteChecklistItem(draft.id)
                        },
                        onDrop: { sourceID, placeAfter in
                            moveChecklistItem(
                                sourceID,
                                relativeTo: draft.id,
                                placeAfter: placeAfter
                            )
                        }
                    )
                }

                HStack(spacing: 8) {
                    TextField("체크리스트 항목", text: $newChecklistTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText)
                        .focused($isNewChecklistItemFocused)
                        .onSubmit(addChecklistItem)

                    Button {
                        addChecklistItem()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.secondaryText)
                    .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("체크리스트 항목 추가")
                }
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
        } else if let checklistLoadFailureMessage {
            HStack(spacing: 10) {
                Label(checklistLoadFailureMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button {
                    loadChecklist()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("체크리스트 다시 불러오기")
            }
            .padding(10)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 42)
        }
    }

    private func requestSave() {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        if status == .done,
           currentStatus != .done,
           let reminderAt = TaskReminderRules.upcomingReminderDate(for: task, now: Date()) {
            pendingTaskCompletion = PendingDesktopDetailCompletion(
                taskID: task.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderAt
            )
            return
        }
        save(taskID: task.id)
    }

    private func save(taskID: UUID) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }
        if !newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addChecklistItem()
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = parsedTags()
        let estimateInput = parsedEstimatedMinutesInput()
        if let errorMessage = estimateInput.errorMessage {
            persistenceFailureMessage = errorMessage
            return
        }
        let estimatedMinutes = estimateInput.value
        let checklistDrafts = normalizedChecklistDrafts()
        let newPlannedAt = DayKey.startOfDay(for: plannedDate)
        let newDayKey = DayKey.key(for: newPlannedAt)
        let now = Date()

        do {
            guard let activeTask = try modelContext.fetch(
                BoundedQueryService.taskDescriptor(id: taskID)
            ).first else {
                persistenceFailureMessage = "작업이 변경되어 저장하지 못했습니다."
                return
            }
            let oldDayKey = activeTask.plannedDayKey
            let oldStatus = TaskStatus(rawValue: activeTask.status) ?? .todo

            try PersistenceCommandService.perform(in: modelContext) {
                let nextOrder: Double?
                if oldDayKey != newDayKey || oldStatus != status {
                    nextOrder = try BoundedQueryService.nextOrder(
                        in: modelContext,
                        dayKey: newDayKey,
                        status: status
                    )
                } else {
                    nextOrder = nil
                }

                if oldStatus != status {
                    TaskRules.applyStatus(status, to: activeTask, completionDayKey: newDayKey)
                }

                if oldDayKey != newDayKey || nextOrder != nil {
                    TaskRules.move(activeTask, to: newPlannedAt, order: nextOrder)
                }

                activeTask.title = trimmedTitle
                activeTask.note = trimmedNote.isEmpty ? nil : trimmedNote
                activeTask.priority = selectedPriority?.rawValue
                activeTask.tags = tags
                activeTask.estimatedMinutes = estimatedMinutes
                activeTask.updatedAt = now

                TaskChecklistService.replaceItems(
                    for: activeTask.id,
                    drafts: checklistDrafts,
                    existingItems: try TaskChecklistService.items(
                        for: activeTask.id,
                        in: modelContext
                    ),
                    in: modelContext,
                    now: now
                )
            }
            dismiss()
        } catch {
            persistenceFailureMessage = "작업을 저장하지 못했습니다."
        }
    }

    private func reminderFieldTitle(for reminderAt: Date) -> String {
        if status == .done {
            return "설정했던 알림"
        }
        return reminderAt <= Date() ? "지난 알림" : "알림"
    }

    private func reminderSystemImage(for reminderAt: Date) -> String {
        status == .done || reminderAt <= Date() ? "bell.slash" : "bell"
    }

    private func parsedEstimatedMinutesInput() -> (value: Int?, errorMessage: String?) {
        let value = estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil) }
        guard let minutes = Int(value), (1...(24 * 60)).contains(minutes) else {
            return (nil, "예상 시간은 1~1440분 사이의 숫자로 입력해 주세요.")
        }
        return (minutes, nil)
    }

    private func parsedTags() -> [String] {
        var seen = Set<String>()
        return tagsText
            .split(separator: ",")
            .compactMap { rawTag in
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, !seen.contains(tag) else { return nil }
                seen.insert(tag)
                return tag
            }
    }

    private func loadChecklist() {
        checklistLoadFailureMessage = nil
        do {
            let items = try TaskChecklistService.items(for: task.id, in: modelContext)
            checklistDrafts = TaskChecklistService.drafts(from: items)
            renumberChecklistDrafts()
            isChecklistLoaded = true
        } catch {
            checklistDrafts = []
            isChecklistLoaded = false
            checklistLoadFailureMessage = "체크리스트를 불러오지 못했습니다."
        }
    }

    private func addChecklistItem() {
        let itemTitle = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemTitle.isEmpty else { return }

        checklistDrafts.append(ChecklistItemDraft(
            title: itemTitle,
            order: Double(checklistDrafts.count + 1) * 100
        ))
        newChecklistTitle = ""
        isNewChecklistItemFocused = true
    }

    private func deleteChecklistItem(_ id: UUID) {
        checklistDrafts.removeAll { $0.id == id }
        renumberChecklistDrafts()
    }

    private func moveChecklistItem(
        _ sourceID: UUID,
        relativeTo targetID: UUID,
        placeAfter: Bool
    ) -> Bool {
        guard sourceID != targetID,
              let sourceIndex = checklistDrafts.firstIndex(where: { $0.id == sourceID }) else {
            return false
        }

        let movedDraft = checklistDrafts.remove(at: sourceIndex)
        guard let targetIndex = checklistDrafts.firstIndex(where: { $0.id == targetID }) else {
            checklistDrafts.insert(movedDraft, at: sourceIndex)
            return false
        }

        let insertionIndex = min(targetIndex + (placeAfter ? 1 : 0), checklistDrafts.count)
        checklistDrafts.insert(movedDraft, at: insertionIndex)
        renumberChecklistDrafts()
        return true
    }

    private func renumberChecklistDrafts() {
        for index in checklistDrafts.indices {
            checklistDrafts[index].order = Double(index + 1) * 100
        }
    }

    private func normalizedChecklistDrafts() -> [ChecklistItemDraft] {
        checklistDrafts
            .compactMap { draft -> ChecklistItemDraft? in
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return ChecklistItemDraft(
                    id: draft.id,
                    title: title,
                    isCompleted: draft.isCompleted,
                    order: draft.order
                )
            }
            .enumerated()
            .map { index, draft in
                var draft = draft
                draft.order = Double(index + 1) * 100
                return draft
            }
    }
}

private struct ChecklistDraftEditorRow: View {
    @Binding var draft: ChecklistItemDraft
    var onDelete: () -> Void
    var onDrop: (UUID, Bool) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                draft.isCompleted.toggle()
            } label: {
                Image(systemName: draft.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(draft.isCompleted ? AppTheme.done : AppTheme.secondaryText)
            .help(draft.isCompleted ? "완료 해제" : "완료 표시")

            TextField("체크리스트 항목", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.primaryText)
                .strikethrough(draft.isCompleted)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("체크리스트 항목 삭제")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .draggable(draft.id.uuidString)
                .help("드래그해서 순서 변경")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 42)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isDropTargeted ? AppTheme.event : AppTheme.border,
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .dropDestination(for: String.self) { items, location in
            guard let idString = items.first,
                  let sourceID = UUID(uuidString: idString) else {
                return false
            }
            return onDrop(sourceID, location.y > 21)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }
}

struct DetailFieldLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
    }
}
