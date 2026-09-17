import SwiftData
import SwiftUI
import PlanBaseCore

private enum BoardSheet: Identifiable {
    case carryover
    case templates
    case savedTasks
    case taskDetail(UUID)
    case dailyReview

    var id: String {
        switch self {
        case .carryover: "carryover"
        case .templates: "templates"
        case .savedTasks: "savedTasks"
        case .taskDetail(let id): "taskDetail-\(id.uuidString)"
        case .dailyReview: "dailyReview"
        }
    }
}

private struct PendingDesktopTaskDeletion {
    var taskID: UUID
    var title: String
}

private struct PendingDesktopTaskCompletion {
    var taskID: UUID
    var title: String
    var reminderAt: Date
}

private struct PendingDesktopLibrarySave {
    var taskID: UUID
    var title: String
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
    @Environment(\.openWindow) private var openWindow
    @Query private var selectedDayTaskRows: [Task]
    @State private var carryoverSession: CarryoverInboxSession?
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @Binding var selectedDate: Date
    @State private var quickTitle = ""
    @State private var quickEntry = SavedTaskQuickEntryController()
    @State private var presentedSheet: BoardSheet?
    @State private var pendingTaskDeletion: PendingDesktopTaskDeletion?
    @State private var pendingEventDeletion: CalendarEvent?
    @State private var savedTaskNotice: String?
    @State private var completionUndo: TaskCompletionUndoToken?
    @State private var completedTaskTitle = ""
    @State private var persistenceFailureMessage: String?
    @State private var pendingTaskCompletion: PendingDesktopTaskCompletion?
    @State private var pendingLibrarySave: PendingDesktopLibrarySave?
    @State private var progressSession: TaskProgressEventQuerySession?
    @FocusState private var isQuickTitleFocused: Bool

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var todayKey: String { DayKey.today }

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate

        let dayKey = DayKey.key(for: selectedDate.wrappedValue)
        _selectedDayTaskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
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
        carryoverSession?.tasks ?? []
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
        let tasks = boardTasks
        let displayedTaskIDs = Set(tasks.map(\.id))
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    eventStrip
                    quickCreate
                    if let carryoverSession {
                        CarryoverArrivalBanner(session: carryoverSession) { presentedSheet = .carryover }
                    }
                    kanbanBoard(tasks: tasks)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .carryoverInboxSession($carryoverSession)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .carryover:
                if let carryoverSession {
                    CarryoverSheet(
                        session: carryoverSession,
                        failureMessage: $persistenceFailureMessage,
                        onBringToToday: bringToToday,
                        onCompleteAll: completeAllCarryoverTasks,
                        onDelete: deleteTask
                    )
                }
            case .savedTasks:
                SavedTaskLibrarySheet(selectedDate: selectedDate) {
                    savedTaskNotice = $0
                }
            case .templates:
                TemplateLibraryView(selectedDate: selectedDate, currentBoardTasks: selectedDayTaskRows) {
                    savedTaskNotice = $0
                }
            case .taskDetail(let id):
                if let task = (selectedDayTaskRows + carryoverTasks).first(where: {
                    $0.supersededAt == nil && $0.id == id
                }) {
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
                completePendingTask(pending)
            }
            Button("취소", role: .cancel) {}
        } message: { pending in
            Text(
                "\"\(pending.title)\" 작업을 완료하면 " +
                    "\(pending.reminderAt.formatted(date: .abbreviated, time: .shortened)) 알림이 중지됩니다. " +
                    "알림 설정 기록은 계속 유지됩니다."
            )
        }
        .alert("작업을 삭제할까요?", isPresented: Binding(
            get: { pendingTaskDeletion != nil },
            set: { if !$0 { pendingTaskDeletion = nil } }
        ), presenting: pendingTaskDeletion) { pending in
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { confirmTaskDeletion(pending) }
        } message: { pending in
            Text("‘\(pending.title)’ 작업을 삭제합니다. 삭제한 작업은 되돌릴 수 없어요.")
        }
        .alert("일정을 삭제할까요?", isPresented: Binding(
            get: { pendingEventDeletion != nil },
            set: { if !$0 { pendingEventDeletion = nil } }
        ), presenting: pendingEventDeletion) { event in
            Button("취소", role: .cancel) { pendingEventDeletion = nil }
            Button("삭제", role: .destructive) {
                pendingEventDeletion = nil
                deleteEvent(event)
            }
        } message: { event in
            Text("‘\(event.title)’ 일정을 삭제합니다. 연결된 작업은 유지되며 일정 연결만 해제됩니다. 삭제한 일정은 되돌릴 수 없어요.")
        }
        .persistenceFailureAlert(message: boardFailureMessage)
        .alert(
            "자주 쓰는 작업으로 저장하지 못했어요",
            isPresented: Binding(
                get: { pendingLibrarySave != nil },
                set: { if !$0 { pendingLibrarySave = nil } }
            ),
            presenting: pendingLibrarySave
        ) { pending in
            Button("취소", role: .cancel) {}
            Button("다시 시도") {
                saveToLibrary(taskID: pending.taskID, title: pending.title)
            }
        } message: { pending in
            Text("‘\(pending.title)’ 작업은 보드에 그대로 남아 있어요. 다시 시도해 주세요.")
        }
        .overlay(alignment: .bottom) {
            if completionUndo != nil {
                HStack(spacing: 16) {
                    Text("\(completedTaskTitle) · 완료했어요")
                        .lineLimit(2)
                    Button("완료 실행 취소", action: undoCompletion)
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("board-completion-undo")
                }
                .font(.callout)
                .padding(12)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            } else if let savedTaskNotice {
                Text(savedTaskNotice)
                    .font(.callout)
                    .padding(12)
                    .background(AppTheme.panel, in: Capsule())
                    .padding(.bottom, 18)
            }
        }
        .task(id: completionUndo?.id) {
            guard let token = completionUndo else { return }
            let remaining = max(0, token.expiresAt.timeIntervalSinceNow)
            do { try await _Concurrency.Task.sleep(for: .seconds(remaining)) } catch { return }
            guard completionUndo?.id == token.id else { return }
            completionUndo = nil
        }
        .task(id: savedTaskNotice) {
            guard savedTaskNotice != nil else { return }
            do { try await _Concurrency.Task.sleep(for: .seconds(3)) } catch { return }
            savedTaskNotice = nil
        }
        .task {
            if progressSession == nil {
                progressSession = TaskProgressEventQuerySession(context: modelContext)
            }
            progressSession?.apply(taskIDs: displayedTaskIDs)
        }
        .onChange(of: displayedTaskIDs) { _, taskIDs in
            progressSession?.apply(taskIDs: taskIDs)
        }
        .onDisappear {
            progressSession?.cancel()
            completionUndo = nil
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                selectedDate = DayKey.addingDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                           height: PlanBaseControlMetrics.minimumTargetSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("이전 날짜")
            .help("이전 날짜")

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
                    .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                           height: PlanBaseControlMetrics.minimumTargetSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("다음 날짜")
            .help("다음 날짜")

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
                    CarryoverCountBadge(session: carryoverSession)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(carryoverSession?.accessibilityLabel ?? "이월함, 불러오는 중")
            .accessibilityIdentifier("carryover-button")
            .help("과거 미완료 작업을 오늘 보드로 가져오기")

            Button {
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
                Text("선택한 날짜의 일정")
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
                            Text(CalendarEventTimeline.dateRangeText(for: event))
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
                            pendingEventDeletion = event
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                                       height: PlanBaseControlMetrics.minimumTargetSize)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityLabel("\(event.title) 일정 삭제")
                        .help("일정 삭제")
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("해당 날짜에 할 일 입력", text: $quickTitle,
                          prompt: Text("해당 날짜에 할 일 입력").foregroundStyle(AppTheme.secondaryText))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.primaryText)
                    .focused($isQuickTitleFocused)
                    .onSubmit(addQuickTask)
                    .onKeyPress(.downArrow) { quickEntry.moveSelection(by: 1) ? .handled : .ignored }
                    .onKeyPress(.upArrow) { quickEntry.moveSelection(by: -1) ? .handled : .ignored }
                    .onKeyPress(.escape) { quickEntry.dismiss() ? .handled : .ignored }
                Button {
                    addQuickTask()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(PlanBaseButtonStyle())
                .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("작업 추가")
                Button { presentedSheet = .savedTasks } label: {
                    Label("저장한 작업", systemImage: "bookmark")
                }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
                .accessibilityIdentifier("saved-task-library-button")
            }
            .padding(14)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isQuickTitleFocused ? AppTheme.accent : AppTheme.border,
                        lineWidth: isQuickTitleFocused ? 2 : 1.25
                    )
            }
            SavedTaskQuickEntrySuggestions(controller: quickEntry, onAdd: addSavedQuickTask) {
                isQuickTitleFocused = false
                presentedSheet = .savedTasks
            }
        }
        .onChange(of: quickTitle) { _, value in quickEntry.update(value, in: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)) { notification in
            guard PersistenceCommandService.affects(.templates, in: notification) else { return }
            quickEntry.refresh(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudKitSyncService.eventChangedNotification)) { _ in
            quickEntry.refresh(in: modelContext)
        }
    }

    private func kanbanBoard(tasks: [Task]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            KanbanColumn(
                title: TaskStatus.todo.title,
                status: .todo,
                tasks: BoardQueryRules.tasks(tasks, matching: .todo),
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { isQuickTitleFocused = true },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary,
                progressText: progressText
            )

            KanbanColumn(
                title: TaskStatus.doing.title,
                status: .doing,
                tasks: BoardQueryRules.tasks(tasks, matching: .doing),
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { isQuickTitleFocused = true },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary,
                progressText: progressText
            )

            KanbanColumn(
                title: TaskStatus.done.title,
                status: .done,
                tasks: BoardQueryRules.tasks(tasks, matching: .done),
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { isQuickTitleFocused = true },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary,
                progressText: progressText
            )
        }
    }

    private func openFocus(_ task: Task) {
        FocusModeSelectionRequest.post(taskID: task.id)
        openWindow(id: "focus-mode")
    }

    private func saveToLibrary(_ task: Task) {
        saveToLibrary(taskID: task.id, title: task.title)
    }

    private func saveToLibrary(taskID: UUID, title: String) {
        do {
            _ = try SavedTaskLibraryService.save(taskID: taskID, in: modelContext)
            pendingLibrarySave = nil
            savedTaskNotice = "‘\(title)’ 작업을 자주 쓰는 작업으로 저장했어요"
        } catch {
            pendingLibrarySave = PendingDesktopLibrarySave(taskID: taskID, title: title)
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if SavedTaskShortcutRules.query(in: title) != nil {
            addSavedQuickTask(nil)
            return
        }

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

    private func addSavedQuickTask(_ id: UUID?) {
        guard let task = quickEntry.add(input: quickTitle, selectedID: id, on: selectedDate, in: modelContext) else { return }
        quickTitle = ""
        savedTaskNotice = "‘\(task.title)’ 추가했어요"
        isQuickTitleFocused = true
    }

    private func moveTask(idString: String, to status: TaskStatus) -> Bool {
        guard let instanceID = UUID(uuidString: idString) else { return false }
        do {
            guard let task = try modelContext.fetch(
                BoundedQueryService.taskDescriptor(instanceID: instanceID)
            ).first else {
                return false
            }
            return requestTaskStatusChange(task, to: status)
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다."
            return false
        }
    }

    private func moveTask(_ task: Task, to status: TaskStatus) {
        _ = requestTaskStatusChange(task, to: status)
    }

    @discardableResult
    private func requestTaskStatusChange(_ task: Task, to status: TaskStatus) -> Bool {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard currentStatus != status else { return false }

        if status == .done,
           currentStatus != .done,
           let reminderAt = TaskReminderRules.upcomingReminderDate(for: task, now: Date()) {
            pendingTaskCompletion = PendingDesktopTaskCompletion(
                taskID: task.id,
                title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderAt
            )
            return true
        }

        return persistTaskStatusChange(task, to: status)
    }

    private func completePendingTask(_ pending: PendingDesktopTaskCompletion) {
        pendingTaskCompletion = nil
        do {
            guard let task = try modelContext.fetch(
                BoundedQueryService.taskDescriptor(id: pending.taskID)
            ).first,
                  task.status != TaskStatus.done.rawValue else {
                persistenceFailureMessage = "작업이 변경되어 완료하지 못했습니다."
                return
            }
            _ = persistTaskStatusChange(task, to: .done)
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다."
        }
    }

    @discardableResult
    private func persistTaskStatusChange(_ task: Task, to status: TaskStatus) -> Bool {
        do {
            let now = Date()
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext, dayKey: task.plannedDayKey, status: status
            )
            if status == .done {
                completionUndo = try TaskCompletionUndoService.complete(
                    task, in: modelContext, order: nextOrder, now: now
                )
                completedTaskTitle = task.title
            } else {
                try PersistenceCommandService.perform(in: modelContext) {
                    try TaskLifecycleService.applyStatus(status, to: task, in: modelContext, now: now)
                    task.order = nextOrder
                }
                completionUndo = nil
            }
            return true
        } catch {
            persistenceFailureMessage = "작업 상태를 변경하지 못했습니다."
            return false
        }
    }

    private func undoCompletion() {
        guard let token = completionUndo else { return }
        do {
            guard try TaskCompletionUndoService.undo(token, in: modelContext) else {
                completionUndo = nil
                savedTaskNotice = "작업이 변경되었거나 취소할 수 있는 시간이 지났어요"
                return
            }
            completionUndo = nil
            selectedDate = token.boardDate
            savedTaskNotice = "완료를 취소했어요 · 이전 상태로 돌아왔어요"
        } catch {
            persistenceFailureMessage = "완료를 취소하지 못했습니다. 다시 시도해 주세요."
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
            guard let task = try CarryoverInboxRules.currentTasks(withIDs: [task.id], in: modelContext).first else {
                carryoverSession?.refresh()
                return
            }
            let now = Date()
            let currentTodayKey = DayKey.key(for: now)
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext,
                dayKey: currentTodayKey,
                status: .todo
            )
            try TaskLifecycleService.bringToToday(
                task,
                in: modelContext,
                order: nextOrder,
                now: now
            )
        }
    }

    private func completeAllCarryoverTasks(taskIDs: [UUID]) {
        do {
            let tasksToComplete = try CarryoverInboxRules.currentTasks(withIDs: taskIDs, in: modelContext)
            guard !tasksToComplete.isEmpty else { return }
            try PersistenceCommandService.perform(in: modelContext) {
                try TaskLifecycleService.completeOnPlannedDays(
                    tasksToComplete,
                    in: modelContext,
                    now: Date()
                )
            }
        } catch {
            persistenceFailureMessage = "이월 작업을 완료 처리하지 못했습니다."
        }
    }

    private func deleteTask(_ task: Task) {
        pendingTaskDeletion = PendingDesktopTaskDeletion(taskID: task.id, title: task.title)
    }

    private func confirmTaskDeletion(_ pending: PendingDesktopTaskDeletion) {
        pendingTaskDeletion = nil
        performPersistenceCommand(failureMessage: "작업을 삭제하지 못했습니다.") {
            let candidates = try modelContext.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: pending.taskID))
            if let task = BoundedQueryService.representativeTask(from: candidates) {
                try TaskRules.delete(task, from: modelContext)
            }
        }
    }

    private func deleteEvent(_ event: CalendarEvent) {
        performPersistenceCommand(
            failureMessage: "일정을 삭제하지 못했습니다."
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

    private func progressText(for task: Task, at date: Date) -> String? {
        guard let progressSession else { return nil }
        return TaskProgressEventRules.detailText(
            projection: progressSession.projection(for: task.id),
            status: TaskStatus(rawValue: task.status) ?? .todo,
            now: date,
            completedAt: task.completedAt
        )
    }
}
