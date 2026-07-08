#if os(iOS)
#if !XCODE_APP_BUNDLE
import EasyTaskCore
#endif
import SwiftData
import SwiftUI

private enum MobileBoardSheet: Identifiable {
    case task(TodoTask)
    case carryover
    case templates
    case review

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .carryover: "carryover"
        case .templates: "templates"
        case .review: "review"
        }
    }
}

struct MobileBoardView: View {
    @Binding var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var isTodayBoard: Bool { selectedDayKey == DayKey.today }

    private var boardTasks: [TodoTask] {
        tasks
            .filter { task in
                guard task.archivedAt == nil else { return false }
                if task.plannedDayKey == selectedDayKey { return true }
                return isTodayBoard && task.status != TaskStatus.done.rawValue && task.plannedDayKey < selectedDayKey
            }
            .sorted { $0.order < $1.order }
    }

    private var statusTasks: [TodoTask] {
        boardTasks.filter { $0.status == selectedStatus.rawValue }
    }

    private var dayEvents: [CalendarEvent] {
        events
            .filter { $0.startDayKey <= selectedDayKey && selectedDayKey <= $0.endDayKey }
            .sorted { $0.startDayKey < $1.startDayKey }
    }

    private var carryoverTasks: [TodoTask] {
        tasks
            .filter { $0.archivedAt == nil && $0.status != TaskStatus.done.rawValue && $0.plannedDayKey < selectedDayKey }
            .sorted { $0.plannedDayKey < $1.plannedDayKey }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BoardHeader(
                    selectedDate: $selectedDate,
                    isTodayBoard: isTodayBoard,
                    selectedDayKey: selectedDayKey
                )
                BoardEventStrip(events: dayEvents)
                BoardQuickAdd(title: $quickTitle, onAdd: addQuickTask)
                BoardStatusPicker(selectedStatus: $selectedStatus)
                BoardTaskList(
                    tasks: statusTasks,
                    selectedStatus: selectedStatus,
                    onEdit: { presentedSheet = .task($0) },
                    onDelete: { modelContext.delete($0) }
                )
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("칸반")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { presentedSheet = .carryover } label: {
                        Label("이월함", systemImage: "tray")
                    }
                    Button { presentedSheet = .templates } label: {
                        Label("템플릿", systemImage: "square.on.square")
                    }
                    Button { presentedSheet = .review } label: {
                        Label("회고", systemImage: "book.closed")
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .task(let task):
                    MobileTaskDetailSheet(task: task)
                case .carryover:
                    MobileCarryoverSheet(tasks: carryoverTasks, targetDate: selectedDate)
                case .templates:
                    MobileTemplateLibrarySheet(
                        templates: templates,
                        items: templateItems,
                        selectedDate: selectedDate,
                        existingTasks: tasks
                    )
                case .review:
                    MobileReviewComposerSheet(selectedDate: selectedDate)
                }
            }
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = TodoTask(
            title: title,
            status: .todo,
            plannedAt: selectedDate,
            order: TaskRules.nextOrder(in: boardTasks, status: .todo)
        )
        modelContext.insert(task)
        quickTitle = ""
        selectedStatus = .todo
    }
}

private struct BoardHeader: View {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(DayKey.display(selectedDate))
                    .font(.headline)
                Text(isTodayBoard ? "오늘 보드" : selectedDayKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

private struct BoardEventStrip: View {
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

private struct BoardQuickAdd: View {
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
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct BoardStatusPicker: View {
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

private struct BoardTaskList: View {
    var tasks: [TodoTask]
    var selectedStatus: TaskStatus
    var onEdit: (TodoTask) -> Void
    var onDelete: (TodoTask) -> Void

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
                        onDelete: { onDelete(task) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct MobileTaskRow: View {
    var task: TodoTask
    var onEdit: () -> Void
    var onDelete: () -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                    if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Menu {
                    ForEach(TaskStatus.allCases) { nextStatus in
                        Button(nextStatus.title) {
                            TaskRules.applyStatus(nextStatus, to: task)
                        }
                    }
                } label: {
                    Text(status.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.selectedTab.opacity(0.28), in: Capsule())
                }
            }

            HStack(spacing: 12) {
                if let estimatedMinutes = task.estimatedMinutes {
                    Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                }
                Spacer()
                Button("편집", action: onEdit)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MobileTaskDetailSheet: View {
    var task: TodoTask
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var priority: TaskPriority?
    @State private var estimatedMinutesText: String

    init(task: TodoTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _priority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("제목", text: $title)
                TextField("메모", text: $note, axis: .vertical)
                Picker("우선순위", selection: $priority) {
                    Text("없음").tag(nil as TaskPriority?)
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority as TaskPriority?)
                    }
                }
                TextField("예상 시간(분)", text: $estimatedMinutesText)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("작업 상세")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        task.title = trimmedTitle
        task.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        task.priority = priority?.rawValue
        task.estimatedMinutes = Int(estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines))
        task.updatedAt = Date()
    }
}

private struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var targetDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    ContentUnavailableView("이월할 작업 없음", systemImage: "tray")
                } else {
                    Section {
                        Button("모두 완료 처리") {
                            completeAll()
                        }
                    }
                    ForEach(tasks) { task in
                        Button {
                            moveToTargetDate(task)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text(task.plannedDayKey)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("이월함")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func completeAll() {
        for task in tasks {
            TaskRules.applyStatus(.done, to: task)
        }
        dismiss()
    }

    private func moveToTargetDate(_ task: TodoTask) {
        task.plannedAt = targetDate
        task.plannedDayKey = DayKey.key(for: targetDate)
        task.updatedAt = Date()
        dismiss()
    }
}

private struct MobileTemplateLibrarySheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var selectedDate: Date
    var existingTasks: [TodoTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("템플릿 검색", text: $searchText)
                    Picker("보기", selection: $scope) {
                        ForEach(TemplateListScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(filteredTemplates) { template in
                    let templateItems = TemplateListRules.itemsForTemplate(template, in: items)
                    Button {
                        apply(template, items: templateItems)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(template.name)
                                    .font(.headline)
                                if template.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("템플릿")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func apply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        TemplateService.applyTemplate(
            template,
            items: templateItems,
            selectedDate: selectedDate,
            existingTasks: existingTasks,
            in: modelContext
        )
        dismiss()
    }
}
#endif
