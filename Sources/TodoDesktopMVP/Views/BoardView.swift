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

extension View {
    func persistenceFailureAlert(message: Binding<String?>) -> some View {
        alert(
            "저장 오류",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        message.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                message.wrappedValue = nil
            }
        } message: {
            Text(message.wrappedValue ?? "변경사항을 저장하지 못했습니다.")
        }
    }
}

struct BoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var selectedDayTaskRows: [Task]
    @Query private var carryoverTaskRows: [Task]
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @Binding var selectedDate: Date
    @State private var quickTitle = ""
    @State private var presentedSheet: BoardSheet?
    @State private var templateName = ""
    @State private var persistenceFailureMessage: String?

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var todayKey: String { DayKey.today }

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate

        let dayKey = DayKey.key(for: selectedDate.wrappedValue)
        _selectedDayTaskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
        _carryoverTaskRows = Query(
            BoundedQueryService.carryoverTasksDescriptor(before: DayKey.today)
        )
        _overlappingEventRows = Query(
            BoundedQueryService.eventsDescriptor(
                overlappingStartDayKey: dayKey,
                endDayKey: dayKey
            )
        )
    }

    private var boardEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey, in: overlappingEventRows)
    }

    private var boardTasks: [Task] {
        BoardQueryRules.tasksForBoard(
            selectedDayTaskRows,
            selectedDayKey: selectedDayKey,
            todayKey: todayKey
        )
    }

    private var carryoverTasks: [Task] {
        TaskRules.carryoverTasks(carryoverTaskRows, before: todayKey)
    }

    private var todoTasks: [Task] {
        BoardQueryRules.tasks(boardTasks, matching: .todo)
    }

    private var doingTasks: [Task] {
        BoardQueryRules.tasks(boardTasks, matching: .doing)
    }

    private var doneTasks: [Task] {
        BoardQueryRules.tasks(boardTasks, matching: .done)
    }

    private var boardFailureMessage: Binding<String?> {
        Binding(
            get: {
                switch presentedSheet {
                case nil:
                    persistenceFailureMessage
                case .some:
                    nil
                }
            },
            set: { persistenceFailureMessage = $0 }
        )
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
                    failureMessage: $persistenceFailureMessage,
                    onBringToToday: bringToToday,
                    onCompleteAll: completeAllCarryoverTasks,
                    onDelete: deleteTask
                )
            case .templates:
                TemplateLibrarySheet(
                    templates: templates,
                    items: templateItems,
                    templateName: $templateName,
                    failureMessage: $persistenceFailureMessage,
                    currentBoardTasks: boardTasks
                        .filter { $0.plannedDayKey == selectedDayKey }
                        .sorted { $0.order < $1.order },
                    onApply: { template in
                        let didApply = performPersistenceCommand(
                            failureMessage: "템플릿을 적용하지 못했습니다."
                        ) {
                            TemplateService.applyTemplate(
                                template,
                                items: templateItems,
                                selectedDate: selectedDate,
                                existingTasks: selectedDayTaskRows,
                                in: modelContext
                            )
                        }
                        guard didApply else { return }
                        presentedSheet = nil
                    },
                    onSaveCurrentBoard: { sourceTasks in
                        guard !sourceTasks.isEmpty else { return }
                        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }

                        let didSave = performPersistenceCommand(
                            failureMessage: "템플릿을 저장하지 못했습니다."
                        ) {
                            TemplateService.saveTemplate(
                                named: trimmedName,
                                from: sourceTasks,
                                in: modelContext
                            )
                        }
                        guard didSave else { return }
                        templateName = ""
                        presentedSheet = nil
                    },
                    onToggleFavorite: { template in
                        performPersistenceCommand(
                            failureMessage: "즐겨찾기를 변경하지 못했습니다."
                        ) {
                            template.isFavorite.toggle()
                            template.updatedAt = Date()
                        }
                    },
                    onDelete: { template in
                        performPersistenceCommand(
                            failureMessage: "템플릿을 삭제하지 못했습니다."
                        ) {
                            TemplateService.deleteTemplate(
                                template,
                                items: templateItems,
                                in: modelContext
                            )
                        }
                    }
                )
            case .taskDetail(let id):
                if let task = selectedDayTaskRows.first(where: { $0.supersededAt == nil && $0.id == id }) {
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
        .persistenceFailureAlert(message: boardFailureMessage)
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
                            deleteEvent(event)
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
                onTitleChange: updateTaskTitle,
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
                onTitleChange: updateTaskTitle,
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
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onDelete: deleteTask
            )
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let didAdd = performPersistenceCommand(
            failureMessage: "작업을 추가하지 못했습니다."
        ) {
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext,
                dayKey: selectedDayKey,
                status: .todo
            )
            let task = Task(
                title: title,
                status: .todo,
                plannedAt: selectedDate,
                order: nextOrder
            )
            modelContext.insert(task)
        }
        guard didAdd else { return }
        quickTitle = ""
    }

    private func moveTask(idString: String, to status: TaskStatus) -> Bool {
        guard let id = UUID(uuidString: idString),
              let task = selectedDayTaskRows.first(where: { $0.supersededAt == nil && $0.id == id }) else {
            return false
        }

        return performPersistenceCommand(
            failureMessage: "작업 상태를 변경하지 못했습니다."
        ) {
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext,
                dayKey: task.plannedDayKey,
                status: status
            )
            TaskRules.applyStatus(status, to: task)
            task.order = nextOrder
        }
    }

    private func moveTask(_ task: Task, to status: TaskStatus) {
        performPersistenceCommand(
            failureMessage: "작업 상태를 변경하지 못했습니다."
        ) {
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext,
                dayKey: task.plannedDayKey,
                status: status
            )
            TaskRules.applyStatus(status, to: task)
            task.order = nextOrder
        }
    }

    private func updateTaskTitle(_ task: Task, to title: String) -> Bool {
        performPersistenceCommand(
            failureMessage: "작업 제목을 저장하지 못했습니다."
        ) {
            task.title = title
            task.updatedAt = Date()
        }
    }

    private func bringToToday(_ task: Task) {
        performPersistenceCommand(
            failureMessage: "작업을 오늘로 가져오지 못했습니다."
        ) {
            let now = Date()
            let currentTodayKey = DayKey.key(for: now)
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext,
                dayKey: currentTodayKey,
                status: .todo
            )
            TaskRules.bringToToday(task, order: nextOrder, now: now)
        }
    }

    private func completeAllCarryoverTasks() {
        performPersistenceCommand(
            failureMessage: "이월 작업을 완료 처리하지 못했습니다."
        ) {
            TaskRules.completeOnPlannedDays(carryoverTasks)
        }
    }

    private func deleteTask(_ task: Task) {
        performPersistenceCommand(
            failureMessage: "작업을 삭제하지 못했습니다."
        ) {
            try TaskRules.delete(task, from: modelContext)
        }
    }

    private func deleteEvent(_ event: CalendarEvent) {
        performPersistenceCommand(
            failureMessage: "이벤트를 삭제하지 못했습니다."
        ) {
            let linkedTasks = try BoundedQueryService.tasksLinked(
                toEventID: event.id,
                in: modelContext
            )
            CalendarEventRules.detachTasks(from: event, in: linkedTasks)
            modelContext.delete(event)
        }
    }

    @discardableResult
    private func performPersistenceCommand(
        failureMessage: String,
        _ mutation: () throws -> Void
    ) -> Bool {
        do {
            try PersistenceCommandService.perform(in: modelContext, mutation)
            return true
        } catch {
            persistenceFailureMessage = failureMessage
            return false
        }
    }

    private func editTask(_ task: Task) {
        presentedSheet = .taskDetail(task.id)
    }
}
