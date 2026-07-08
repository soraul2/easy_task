import SwiftData
import SwiftUI
import EasyTaskCore

private enum BoardSheet: Identifiable {
    case carryover
    case templates
    case taskDetail(UUID)
    case dailyReview

    var id: String {
        switch self {
        case .carryover: "carryover"
        case .templates: "templates"
        case .taskDetail(let id): "taskDetail-\(id.uuidString)"
        case .dailyReview: "dailyReview"
        }
    }
}

struct BoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var events: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @Binding var selectedDate: Date
    @State private var quickTitle = ""
    @State private var presentedSheet: BoardSheet?
    @State private var templateName = ""

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var todayKey: String { DayKey.today }

    private var boardEvents: [CalendarEvent] {
        events
            .filter { $0.startDayKey <= selectedDayKey && selectedDayKey <= $0.endDayKey }
            .sorted { $0.startDayKey < $1.startDayKey }
    }

    private var boardTasks: [Task] {
        if selectedDayKey == todayKey {
            let visible = tasks.filter { $0.archivedAt == nil }
            return visible.filter { task in
                if task.status == TaskStatus.done.rawValue {
                    return task.completedDayKey == todayKey
                }
                return task.plannedDayKey == todayKey
            }
        }

        return tasks.filter { task in
            if task.status == TaskStatus.done.rawValue {
                return (task.completedDayKey ?? task.plannedDayKey) == selectedDayKey
            }
            return task.archivedAt == nil && task.plannedDayKey == selectedDayKey
        }
    }

    private var carryoverTasks: [Task] {
        tasks
            .filter {
                $0.archivedAt == nil &&
                    $0.status != TaskStatus.done.rawValue &&
                    $0.plannedDayKey < todayKey
            }
            .sorted {
                if $0.plannedDayKey == $1.plannedDayKey {
                    return $0.order < $1.order
                }
                return $0.plannedDayKey < $1.plannedDayKey
            }
    }

    private var todoTasks: [Task] {
        boardTasks
            .filter { $0.status == TaskStatus.todo.rawValue }
            .sorted { $0.order < $1.order }
    }

    private var doingTasks: [Task] {
        boardTasks
            .filter { $0.status == TaskStatus.doing.rawValue }
            .sorted { $0.order < $1.order }
    }

    private var doneTasks: [Task] {
        boardTasks
            .filter { $0.status == TaskStatus.done.rawValue }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    eventStrip
                    quickCreate
                    kanbanBoard
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .carryover:
                CarryoverSheet(
                    tasks: carryoverTasks,
                    onBringToToday: bringToToday,
                    onCompleteAll: completeAllCarryoverTasks,
                    onDelete: deleteTask
                )
            case .templates:
                TemplateLibrarySheet(
                    templates: templates,
                    items: templateItems,
                    templateName: $templateName,
                    currentBoardTasks: boardTasks
                        .filter { $0.plannedDayKey == selectedDayKey }
                        .sorted { $0.order < $1.order },
                    onApply: { template in
                        TemplateService.applyTemplate(
                            template,
                            items: templateItems,
                            selectedDate: selectedDate,
                            existingTasks: tasks,
                            in: modelContext
                        )
                        presentedSheet = nil
                    },
                    onSaveCurrentBoard: { sourceTasks in
                        guard !sourceTasks.isEmpty else { return }
                        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }

                        TemplateService.saveTemplate(
                            named: trimmedName,
                            from: sourceTasks,
                            in: modelContext
                        )
                        templateName = ""
                        presentedSheet = nil
                    }
                )
            case .taskDetail(let id):
                if let task = tasks.first(where: { $0.id == id }) {
                    TaskDetailSheet(task: task)
                } else {
                    EmptySheetState(
                        symbol: "square.and.pencil",
                        title: "작업을 찾을 수 없음",
                        message: "이미 삭제되었거나 더 이상 사용할 수 없는 작업입니다."
                    )
                    .padding(22)
                    .frame(width: 380)
                    .background(AppTheme.panel)
                }
            case .dailyReview:
                DailyReviewSheet(selectedDate: selectedDate)
            }
        }
        .onAppear {
            TaskRules.archiveIfNeeded(tasks)
        }
        .onChange(of: selectedDate) {
            TaskRules.archiveIfNeeded(tasks)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                selectedDate = DayKey.addingDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Text(DayKey.display(selectedDate))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(minWidth: 210, alignment: .leading)

            Button("오늘") {
                selectedDate = DayKey.startOfDay(for: Date())
            }
            .buttonStyle(.bordered)

            Button {
                selectedDate = DayKey.addingDays(1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                presentedSheet = .dailyReview
            } label: {
                Label("회고 작성", systemImage: "book.closed")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .help("현재 날짜의 회고 작성")

            Button {
                presentedSheet = .carryover
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "tray")
                    Text("이월함")
                    if !carryoverTasks.isEmpty {
                        Text("\(carryoverTasks.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .help("과거 미완료 작업을 오늘 보드로 가져오기")

            Button {
                templateName = "\(DayKey.key(for: selectedDate)) 템플릿"
                presentedSheet = .templates
            } label: {
                Label("템플릿", systemImage: "square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .help("템플릿 적용 또는 현재 보드 저장")
        }
    }

    @ViewBuilder
    private var eventStrip: some View {
        if !boardEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("오늘의 이벤트")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                ForEach(boardEvents) { event in
                    HStack {
                        Capsule()
                            .fill(CalendarEventPalette.color(for: event.color))
                            .frame(width: 8, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("\(event.startDayKey) - \(event.endDayKey)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Text(CalendarEventTimeline.badgeText(for: event))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                        Button(role: .destructive) {
                            modelContext.delete(event)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppTheme.secondaryText)
                        .help("이벤트 삭제")
                    }
                    .padding(12)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var quickCreate: some View {
        HStack(spacing: 10) {
            TextField("해당 날짜에 할 일 입력", text: $quickTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.primaryText)
                .onSubmit(addQuickTask)
            Button {
                addQuickTask()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var kanbanBoard: some View {
        HStack(alignment: .top, spacing: 14) {
            KanbanColumn(
                title: TaskStatus.todo.title,
                status: .todo,
                tasks: todoTasks,
                emptyTitle: "할 일 없음",
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onEdit: editTask,
                onDelete: deleteTask
            )

            KanbanColumn(
                title: TaskStatus.doing.title,
                status: .doing,
                tasks: doingTasks,
                emptyTitle: "진행 중인 작업 없음",
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onEdit: editTask,
                onDelete: deleteTask
            )

            KanbanColumn(
                title: TaskStatus.done.title,
                status: .done,
                tasks: doneTasks,
                emptyTitle: "완료한 작업 없음",
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onEdit: editTask,
                onDelete: deleteTask
            )
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let task = Task(
            title: title,
            status: .todo,
            plannedAt: selectedDate,
            order: TaskRules.nextOrder(in: tasks, status: .todo)
        )
        modelContext.insert(task)
        quickTitle = ""
    }

    private func moveTask(idString: String, to status: TaskStatus) -> Bool {
        guard let id = UUID(uuidString: idString),
              let task = tasks.first(where: { $0.id == id }) else {
            return false
        }

        TaskRules.applyStatus(status, to: task)
        task.order = TaskRules.nextOrder(in: tasks, status: status)
        return true
    }

    private func moveTask(_ task: Task, to status: TaskStatus) {
        TaskRules.applyStatus(status, to: task)
        task.order = TaskRules.nextOrder(in: tasks, status: status)
    }

    private func bringToToday(_ task: Task) {
        task.plannedAt = DayKey.startOfDay(for: Date())
        task.plannedDayKey = todayKey
        task.status = TaskStatus.todo.rawValue
        task.order = TaskRules.nextOrder(in: tasks, status: .todo)
        task.updatedAt = Date()
    }

    private func completeAllCarryoverTasks() {
        let now = Date()
        var nextDoneOrder = TaskRules.nextOrder(in: tasks, status: .done)

        for task in carryoverTasks {
            TaskRules.applyStatus(.done, to: task, now: now)
            task.order = nextDoneOrder
            nextDoneOrder += 100
        }
    }

    private func deleteTask(_ task: Task) {
        modelContext.delete(task)
    }

    private func editTask(_ task: Task) {
        presentedSheet = .taskDetail(task.id)
    }
}

struct TaskDetailSheet: View {
    var task: Task
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var selectedPriority: TaskPriority?
    @State private var tagsText: String
    @State private var estimatedMinutesText: String

    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _selectedPriority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
            }

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

            HStack {
                Spacer()

                Button("취소") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    save()
                } label: {
                    Label("저장", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(AppTheme.panel)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        task.title = trimmedTitle
        task.note = trimmedNote.isEmpty ? nil : trimmedNote
        task.priority = selectedPriority?.rawValue
        task.tags = parsedTags()
        task.estimatedMinutes = parsedEstimatedMinutes()
        task.updatedAt = Date()
        dismiss()
    }

    private func parsedEstimatedMinutes() -> Int? {
        let digits = estimatedMinutesText.filter(\.isNumber)
        guard let minutes = Int(digits), minutes > 0 else { return nil }
        return min(minutes, 24 * 60)
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

struct CarryoverSheet: View {
    var tasks: [Task]
    var onBringToToday: (Task) -> Void
    var onCompleteAll: () -> Void
    var onDelete: (Task) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이월함")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("과거 날짜의 미완료 작업을 오늘 할 일로 가져오거나 완료 처리합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if !tasks.isEmpty {
                    Button {
                        onCompleteAll()
                    } label: {
                        Label("모두 완료 처리", systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("이월함의 모든 작업을 완료 상태로 변경")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            if tasks.isEmpty {
                EmptySheetState(
                    symbol: "tray",
                    title: "이월할 작업 없음",
                    message: "과거 날짜에 남아 있는 미완료 작업이 없습니다."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(tasks) { task in
                            CarryoverTaskRow(
                                task: task,
                                onBringToToday: onBringToToday,
                                onDelete: onDelete
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 480)
        .background(AppTheme.panel)
    }
}

struct TemplateLibrarySheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    @Binding var templateName: String
    var currentBoardTasks: [Task]
    var onApply: (TaskTemplate) -> Void
    var onSaveCurrentBoard: ([Task]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedScope: TemplateListScope = .favorites
    @State private var excludedTaskIDs: Set<UUID> = []

    private var canSaveCurrentBoard: Bool {
        !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !includedBoardTasks.isEmpty
    }

    private var includedBoardTasks: [Task] {
        currentBoardTasks.filter { !excludedTaskIDs.contains($0.id) }
    }

    private var excludedBoardTaskCount: Int {
        currentBoardTasks.count - includedBoardTasks.count
    }

    private var visibleTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(
            templates,
            items: items,
            query: searchText,
            scope: selectedScope
        )
    }

    private var emptyTemplateTitle: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "즐겨찾기한 템플릿 없음"
        }
        return "검색 결과 없음"
    }

    private var emptyTemplateMessage: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "전체보기에서 자주 쓰는 템플릿에 별표를 눌러 추가하세요."
        }
        return "템플릿 이름이나 포함된 작업명으로 다시 검색해보세요."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("템플릿")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("저장한 작업 묶음을 현재 날짜에 적용하거나 현재 보드를 템플릿으로 저장합니다.")
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
            }

            HStack(alignment: .top, spacing: 18) {
                templateList
                saveCurrentBoardPanel
            }
        }
        .padding(22)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 430, idealHeight: 540)
        .background(AppTheme.panel)
        .onAppear {
            selectedScope = TemplateListRules.preferredScope(for: templates)
            excludedTaskIDs = []
        }
        .onChange(of: currentBoardTasks.map(\.id)) { _, ids in
            excludedTaskIDs.formIntersection(Set(ids))
        }
    }

    @ViewBuilder
    private var templateList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("저장된 템플릿")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TemplateScopePicker(scope: $selectedScope)

            TemplateSearchField(text: $searchText)

            if templates.isEmpty {
                EmptySheetState(
                    symbol: "square.on.square",
                    title: "저장된 템플릿 없음",
                    message: "현재 보드의 작업을 저장하면 이곳에서 다시 적용할 수 있습니다."
                )
            } else if visibleTemplates.isEmpty {
                EmptySheetState(
                    symbol: selectedScope == .favorites ? "star" : "magnifyingglass",
                    title: emptyTemplateTitle,
                    message: emptyTemplateMessage
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            TemplateRow(
                                template: template,
                                items: itemsForTemplate(template),
                                onApply: {
                                    onApply(template)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var saveCurrentBoardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("현재 보드 저장")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TextField("템플릿 이름", text: $templateName)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .onSubmit {
                    if canSaveCurrentBoard {
                        onSaveCurrentBoard(includedBoardTasks)
                    }
                }

            HStack(spacing: 8) {
                Text(currentBoardTaskSummary)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                if excludedBoardTaskCount > 0 {
                    Button("제외 초기화") {
                        excludedTaskIDs = []
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.event)
                }
            }

            currentBoardTaskList

            Button {
                onSaveCurrentBoard(includedBoardTasks)
            } label: {
                Label("템플릿으로 저장", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSaveCurrentBoard)

            Spacer()
        }
        .padding(14)
        .frame(width: 290, alignment: .topLeading)
        .frame(minHeight: 260, alignment: .topLeading)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var currentBoardTaskSummary: String {
        if excludedBoardTaskCount > 0 {
            return "저장 대상 \(includedBoardTasks.count)개 · 제외 \(excludedBoardTaskCount)개"
        }
        return "현재 날짜의 작업 \(includedBoardTasks.count)개"
    }

    @ViewBuilder
    private var currentBoardTaskList: some View {
        if includedBoardTasks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("저장할 작업 없음")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(includedBoardTasks) { task in
                        TemplateSourceTaskRow(
                            task: task,
                            onExclude: {
                                excludedTaskIDs.insert(task.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 180)
        }
    }

    private func itemsForTemplate(_ template: TaskTemplate) -> [TaskTemplateItem] {
        TemplateListRules.itemsForTemplate(template, in: items)
    }
}

struct TemplateSourceTaskRow: View {
    var task: Task
    var onExclude: () -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var statusColor: Color {
        switch status {
        case .todo: AppTheme.secondaryText
        case .doing: AppTheme.event
        case .done: AppTheme.done
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Button {
                onExclude()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("템플릿 저장 대상에서 제외")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct TemplateRow: View {
    @Bindable var template: TaskTemplate
    var items: [TaskTemplateItem]
    var onApply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                template.isFavorite.toggle()
                template.updatedAt = Date()
            } label: {
                Image(systemName: template.isFavorite ? "star.fill" : "star")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(template.isFavorite ? Color.yellow : AppTheme.secondaryText)
            .help(template.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                }

                if items.isEmpty {
                    Text("비어 있는 템플릿")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text(items.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            Button("적용") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(items.isEmpty)
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct EmptySheetState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(18)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct CarryoverTaskRow: View {
    var task: Task
    var onBringToToday: (Task) -> Void
    var onDelete: (Task) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(task.plannedDayKey)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                onBringToToday(task)
            } label: {
                Label("오늘로", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(10)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct KanbanColumn: View {
    var title: String
    var status: TaskStatus
    var tasks: [Task]
    var emptyTitle: String
    var selectedDayKey: String
    var onMove: (String, TaskStatus) -> Bool
    var onStatusChange: (Task, TaskStatus) -> Void
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

        task.title = trimmedTitle
        task.updatedAt = Date()
        draftTitle = trimmedTitle
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
