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
    var completionDayKey: String?
}

private struct PendingDesktopLibrarySave {
    var taskID: UUID
    var title: String
}

// Keep draft and suggestion observation inside this view. Reading them in
// BoardView would sort the board and rebuild every card on each keystroke.
private struct DesktopBoardQuickAdd: View {
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var quickEntry = SavedTaskQuickEntryController()
    @FocusState private var isTitleFocused: Bool

    let selectedDate: Date
    let focusRequestID: UUID?
    let onAdd: (String) -> Bool
    let onAddedSavedTask: (String) -> Void
    let onOpenSavedTasks: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("해당 날짜에 할 일 입력", text: $title,
                          prompt: Text("해당 날짜에 할 일 입력").foregroundStyle(AppTheme.secondaryText))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.primaryText)
                    .focused($isTitleFocused)
                    .onSubmit(submit)
                    .onKeyPress(.downArrow) { quickEntry.moveSelection(by: 1) ? .handled : .ignored }
                    .onKeyPress(.upArrow) { quickEntry.moveSelection(by: -1) ? .handled : .ignored }
                    .onKeyPress(.escape) { quickEntry.dismiss() ? .handled : .ignored }
                    .accessibilityHint("/를 입력하면 저장한 작업을 찾아 추가할 수 있어요.")
                Button(action: submit) {
                    Image(systemName: "plus")
                }
                .buttonStyle(PlanBaseButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("작업 추가")
                Button(action: onOpenSavedTasks) {
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
                        isTitleFocused ? AppTheme.accent : AppTheme.border,
                        lineWidth: isTitleFocused ? 2 : 1.25
                    )
            }
            SavedTaskQuickEntrySuggestions(controller: quickEntry, onAdd: addSavedTask) {
                isTitleFocused = false
                onOpenSavedTasks()
            }
        }
        .onChange(of: title) { _, value in quickEntry.update(value, in: modelContext) }
        .onChange(of: focusRequestID) { _, _ in isTitleFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)) { notification in
            guard PersistenceCommandService.affects(.templates, in: notification) else { return }
            quickEntry.refresh(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudKitSyncService.eventChangedNotification)) { notification in
            guard let summary = CloudKitSyncService.summary(from: notification) else { return }
            quickEntry.refresh(after: summary, in: modelContext)
        }
    }

    private func submit() {
        let interval = PlanBasePerformanceTrace.begin("TaskSubmit")
        defer { PlanBasePerformanceTrace.end("TaskSubmit", interval) }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        if SavedTaskShortcutRules.query(in: trimmedTitle) != nil {
            addSavedTask(nil)
        } else if onAdd(trimmedTitle) {
            title = ""
        }
    }

    private func addSavedTask(_ id: UUID?) {
        guard let task = quickEntry.add(input: title, selectedID: id, on: selectedDate, in: modelContext) else { return }
        title = ""
        onAddedSavedTask(task.title)
        isTitleFocused = true
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
    @Environment(\.openWindow) private var openWindow
    @Query private var selectedDayTaskRows: [Task]
    @State private var carryoverSession: CarryoverInboxSession?
    @State private var overlappingEventRows: [CalendarEvent] = []

    @Binding var selectedDate: Date
    @State private var quickAddFocusRequestID: UUID?
    @State private var presentedSheet: BoardSheet?
    @State private var pendingTaskDeletion: PendingDesktopTaskDeletion?
    @State private var pendingEventDeletion: CalendarEvent?
    @State private var savedTaskNotice: String?
    @State private var completionUndo: TaskCompletionUndoToken?
    @State private var completedTaskTitle = ""
    @State private var completedTaskNotice = ""
    @State private var persistenceFailureMessage: String?
    @State private var pendingTaskCompletion: PendingDesktopTaskCompletion?
    @State private var pendingLibrarySave: PendingDesktopLibrarySave?
    @State private var progressSession: TaskProgressEventQuerySession?

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var todayKey: String { DayKey.today }

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate

        let dayKey = DayKey.key(for: selectedDate.wrappedValue)
        _selectedDayTaskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
    }

    private var boardEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey,
            in: overlappingEventRows.filter { $0.modelContext != nil })
    }

    private var boardTasks: [Task] {
        BoardQueryRules.tasksForBoard(
            selectedDayTaskRows.filter { $0.modelContext != nil },
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
                    DesktopBoardQuickAdd(
                        selectedDate: selectedDate,
                        focusRequestID: quickAddFocusRequestID,
                        onAdd: addQuickTask,
                        onAddedSavedTask: { savedTaskNotice = "‘\($0)’ 추가했어요" },
                        onOpenSavedTasks: { presentedSheet = .savedTasks }
                    )
                    if let carryoverSession {
                        CarryoverArrivalBanner(session: carryoverSession) { presentedSheet = .carryover }
                    }
                    kanbanBoard(tasks: tasks)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .refreshVisibleData(key: selectedDayKey, domains: .calendar) {
            overlappingEventRows = try BoundedQueryService.events(
                overlappingStartDayKey: selectedDayKey, endDayKey: selectedDayKey,
                in: modelContext)
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
                if let task = try? currentTask(id: id) {
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
            Button(pending.completionDayKey.map { TaskCompletionRules.backdatedActionTitle(dayKey: $0) } ?? "완료하기", role: .destructive) {
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
                    Text("\(completedTaskTitle) · \(completedTaskNotice)")
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

    private func kanbanBoard(tasks: [Task]) -> some View {
        // Materialize before the column/TimelineView/ForEach closures retain any
        // children. A disappearing card must never construct a snapshot later.
        let todo = cardSnapshots(for: BoardQueryRules.tasks(tasks, matching: .todo))
        let doing = cardSnapshots(for: BoardQueryRules.tasks(tasks, matching: .doing))
        let done = cardSnapshots(for: BoardQueryRules.tasks(tasks, matching: .done))
        return HStack(alignment: .top, spacing: 14) {
            KanbanColumn(
                title: TaskStatus.todo.title,
                status: .todo,
                tasks: todo,
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { quickAddFocusRequestID = UUID() },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onRecordCompletion: recordCompletion,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary
            )

            KanbanColumn(
                title: TaskStatus.doing.title,
                status: .doing,
                tasks: doing,
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { quickAddFocusRequestID = UUID() },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onRecordCompletion: recordCompletion,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary
            )

            KanbanColumn(
                title: TaskStatus.done.title,
                status: .done,
                tasks: done,
                isBoardEmpty: tasks.isEmpty,
                onAddTask: { quickAddFocusRequestID = UUID() },
                selectedDayKey: selectedDayKey,
                onMove: moveTask,
                onStatusChange: moveTask,
                onRecordCompletion: recordCompletion,
                onTitleChange: updateTaskTitle,
                onEdit: editTask,
                onStartFocus: openFocus,
                onDelete: deleteTask,
                onSaveToLibrary: saveToLibrary
            )
        }
    }

    private func cardSnapshots(for tasks: [Task]) -> [DesktopTaskCardSnapshot] {
        tasks.map { task in
            DesktopTaskCardSnapshot(task: task, progress: progressSession?.projection(for: task.id))
        }
    }

    private func currentTask(id: UUID) throws -> Task? {
        BoundedQueryService.representativeTask(from: try modelContext.fetch(
            BoundedQueryService.taskCandidatesDescriptor(id: id)))
    }

    private func taskForAction(id: UUID) -> Task? {
        do {
            guard let task = try currentTask(id: id) else {
                persistenceFailureMessage = "작업이 변경되어 사용할 수 없습니다."
                return nil
            }
            return task
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다."
            return nil
        }
    }

    private func openFocus(_ taskID: UUID) {
        guard let task = taskForAction(id: taskID) else { return }
        FocusModeSelectionRequest.post(taskID: task.id)
        openWindow(id: "focus-mode")
    }

    private func saveToLibrary(_ taskID: UUID) {
        guard let task = taskForAction(id: taskID) else { return }
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

    private func addQuickTask(_ title: String) -> Bool {
        performPersistenceCommand(
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
    }

    private func moveTask(idString: String, to status: TaskStatus) -> Bool {
        guard let instanceID = UUID(uuidString: idString) else { return false }
        do {
            guard let instance = try modelContext.fetch(
                BoundedQueryService.taskDescriptor(instanceID: instanceID)
            ).first, let task = try currentTask(id: instance.id) else {
                return false
            }
            return requestTaskStatusChange(task, to: status)
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다."
            return false
        }
    }

    private func moveTask(_ taskID: UUID, to status: TaskStatus) {
        guard let task = taskForAction(id: taskID) else { return }
        _ = requestTaskStatusChange(task, to: status)
    }

    private func recordCompletion(_ taskID: UUID, on dayKey: String) {
        guard let task = taskForAction(id: taskID) else { return }
        _ = requestTaskStatusChange(task, to: .done, completionDayKey: dayKey)
    }

    @discardableResult
    private func requestTaskStatusChange(
        _ task: Task, to status: TaskStatus, completionDayKey: String? = nil
    ) -> Bool {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard currentStatus != status else { return false }

        if status == .done,
           currentStatus != .done,
           let reminderAt = TaskReminderRules.upcomingReminderDate(for: task, now: Date()) {
            pendingTaskCompletion = PendingDesktopTaskCompletion(
                taskID: task.id,
                title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderAt,
                completionDayKey: completionDayKey
            )
            return true
        }

        return persistTaskStatusChange(task, to: status, completionDayKey: completionDayKey)
    }

    private func completePendingTask(_ pending: PendingDesktopTaskCompletion) {
        pendingTaskCompletion = nil
        do {
            guard let task = try currentTask(id: pending.taskID),
                  task.status != TaskStatus.done.rawValue else {
                persistenceFailureMessage = "작업이 변경되어 완료하지 못했습니다."
                return
            }
            _ = persistTaskStatusChange(task, to: .done, completionDayKey: pending.completionDayKey)
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다."
        }
    }

    @discardableResult
    private func persistTaskStatusChange(
        _ task: Task, to status: TaskStatus, completionDayKey: String? = nil
    ) -> Bool {
        do {
            let now = Date()
            let nextOrder = try BoundedQueryService.nextOrder(
                in: modelContext, dayKey: task.plannedDayKey, status: status
            )
            if status == .done {
                completionUndo = try TaskCompletionUndoService.complete(
                    task, in: modelContext, order: nextOrder, now: now, completionDayKey: completionDayKey
                )
                completedTaskTitle = task.title
                completedTaskNotice = TaskCompletionRules.completionNotice(
                    dayKey: task.completedDayKey ?? DayKey.key(for: now)
                )
            } else {
                try PersistenceCommandService.perform(in: modelContext) {
                    try TaskLifecycleService.applyStatus(status, to: task, in: modelContext, now: now)
                    task.order = nextOrder
                }
                completionUndo = nil
            }
            return true
        } catch TaskCompletionUndoService.CompletionError.backdatedDayNoLongerAvailable {
            persistenceFailureMessage = "작업 날짜가 변경되어 해당 날짜에 완료로 기록하지 못했어요"
            return false
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

    private func updateTaskTitle(_ taskID: UUID, to title: String) -> Bool {
        performPersistenceCommand(
            failureMessage: "작업 제목을 저장하지 못했습니다."
        ) {
            guard let task = try currentTask(id: taskID) else {
                throw CocoaError(.fileNoSuchFile)
            }
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
        guard task.modelContext != nil else { return }
        deleteTask(task.id)
    }

    private func deleteTask(_ taskID: UUID) {
        guard let task = taskForAction(id: taskID) else { return }
        pendingTaskDeletion = PendingDesktopTaskDeletion(taskID: taskID, title: task.title)
    }

    private func confirmTaskDeletion(_ pending: PendingDesktopTaskDeletion) {
        let interval = PlanBasePerformanceTrace.begin("TaskDeletion")
        defer { PlanBasePerformanceTrace.end("TaskDeletion", interval) }
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

    private func editTask(_ taskID: UUID) {
        guard taskForAction(id: taskID) != nil else { return }
        presentedSheet = .taskDetail(taskID)
    }
}
