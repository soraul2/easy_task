#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI
import Foundation
import UIKit

private enum MobileBoardSheet: Identifiable {
    case task(TodoTask)
    case carryover
    case templates
    case savedTasks
    case review

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .carryover: "carryover"
        case .templates: "templates"
        case .savedTasks: "savedTasks"
        case .review: "review"
        }
    }
}

private struct PendingMobileTaskDeletion {
    var taskID: UUID
    var title: String
}

private struct PendingMobileTaskCompletion {
    var taskID: UUID
    var title: String
    var reminderAt: Date
}

private struct PendingMobileLibrarySave {
    var taskID: UUID
    var title: String
}

private struct MobileLibrarySaveFailureAlertModifier: ViewModifier {
    @Binding var pendingSave: PendingMobileLibrarySave?
    let onRetry: (PendingMobileLibrarySave) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "자주 쓰는 작업으로 저장하지 못했어요",
            isPresented: Binding(
                get: { pendingSave != nil },
                set: { if !$0 { pendingSave = nil } }
            ),
            presenting: pendingSave
        ) { pending in
            Button("취소", role: .cancel) {}
            Button("다시 시도") { onRetry(pending) }
        } message: { pending in
            Text("‘\(pending.title)’ 작업은 보드에 그대로 남아 있어요. 다시 시도해 주세요.")
        }
    }
}

struct MobileBoardActionRequest: Equatable, Identifiable {
    let id: UUID
    let action: PlanBaseBoardAction

    init(id: UUID = UUID(), action: PlanBaseBoardAction) {
        self.id = id
        self.action = action
    }
}

struct MobileBoardView: View {
    @Binding var selectedDate: Date
    @Binding var actionRequest: MobileBoardActionRequest?
    let onStartFocus: (UUID) -> Void
    let onShowTheme: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var minimumBoardColumnWidth = 280.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var selectedDayTaskRows: [TodoTask]
    @State private var carryoverSession: CarryoverInboxSession?
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var quickEntry = SavedTaskQuickEntryController()
    @State private var quickAddFocusRequestID: UUID?
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?
    @State private var pendingTaskCompletion: PendingMobileTaskCompletion?
    @State private var pendingTaskDeletion: PendingMobileTaskDeletion?
    @State private var pendingLibrarySave: PendingMobileLibrarySave?
#if DEBUG
    @State private var didSimulateLibrarySaveFailure = false
#endif
    @State private var persistenceFailureMessage: String?
    @State private var statusNotice: String?
    @State private var statusNoticeTone: MobileNoticeTone = .success
    @State private var statusNoticeToken = UUID()
    @State private var statusDestination: (taskID: UUID, status: TaskStatus)?
    @State private var completionUndo: TaskCompletionUndoToken?
    @State private var highlightedTaskID: UUID?
    @State private var pendingScrollTaskID: UUID?
    @State private var pendingSheetNotice: String?
    @State private var pendingSheetStatus: TaskStatus?
    @State private var progressSession: TaskProgressEventQuerySession?

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var isTodayBoard: Bool { selectedDayKey == DayKey.today }

    init(
        selectedDate: Binding<Date>,
        actionRequest: Binding<MobileBoardActionRequest?>,
        onStartFocus: @escaping (UUID) -> Void = { _ in },
        onShowTheme: @escaping () -> Void = {}
    ) {
        _selectedDate = selectedDate
        _actionRequest = actionRequest
        self.onStartFocus = onStartFocus
        self.onShowTheme = onShowTheme

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

    private var boardTasks: [TodoTask] {
        return BoardQueryRules.tasksForBoard(
            selectedDayTaskRows.filter { $0.modelContext != nil },
            selectedDayKey: selectedDayKey
        )
    }

    private var dayEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey, in: overlappingEventRows)
    }

    private var carryoverTasks: [TodoTask] {
        carryoverSession?.tasks ?? []
    }

    var body: some View {
        let tasks = boardTasks
        let displayedTaskIDs = Set(tasks.map(\.id))
        NavigationStack {
            boardLayout(tasks: tasks)
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                statusNoticeOverlay
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: statusNotice)
            .navigationTitle("칸반")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onShowTheme) {
                        Image(systemName: "paintpalette")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("테마 선택")
                    .accessibilityIdentifier("board-theme-button")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { presentedSheet = .carryover } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "tray")
                            CarryoverCountBadge(session: carryoverSession)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(carryoverSession?.accessibilityLabel ?? "이월함, 불러오는 중")
                    .accessibilityIdentifier("carryover-button")

                    Button { presentedSheet = .review } label: {
                        Image(systemName: "book.closed")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("회고 작성")
                    .accessibilityIdentifier("review-compose-button")
                }
            }
            .carryoverInboxSession($carryoverSession)
            .sheet(item: $presentedSheet, onDismiss: showPendingSheetNotice) { sheet in
                Group {
                    switch sheet {
                    case .task(let task):
                        MobileTaskDetailSheet(task: task, onStartFocus: onStartFocus)
                    case .carryover:
                        if let carryoverSession {
                            MobileCarryoverSheet(
                                session: carryoverSession,
                                onApplied: { pendingSheetNotice = $0 }
                            )
                        }
                    case .savedTasks:
                        SavedTaskLibrarySheet(
                            selectedDate: selectedDate,
                            onAdded: { message in
                                pendingSheetStatus = .todo
                                pendingSheetNotice = message
                            }
                        )
                    case .templates:
                        MobileTemplateLibrarySheet(
                            selectedDate: selectedDate,
                            existingTasks: selectedDayTaskRows,
                            onApplied: {
                                pendingSheetStatus = .todo
                                pendingSheetNotice = $0
                            }
                        )
                    case .review:
                        MobileReviewComposerSheet(
                            selectedDate: selectedDate,
                            onSaved: { pendingSheetNotice = $0 }
                        )
                    }
                }
                .environment(\.dynamicTypeSize, dynamicTypeSize)
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
                    "\(pending.title) 작업을 완료하면 " +
                        "\(pending.reminderAt.formatted(date: .abbreviated, time: .shortened)) " +
                        "알림이 중지됩니다. 알림 설정 기록은 계속 유지됩니다."
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
            .alert("저장하지 못했어요", isPresented: Binding(
                get: { persistenceFailureMessage != nil },
                set: { if !$0 { persistenceFailureMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(persistenceFailureMessage ?? "다시 시도해 주세요.")
            }
            .modifier(MobileLibrarySaveFailureAlertModifier(pendingSave: $pendingLibrarySave) { pending in
                saveToLibrary(taskID: pending.taskID, title: pending.title)
            })
            .task {
                if progressSession == nil {
                    progressSession = TaskProgressEventQuerySession(context: modelContext)
                }
                progressSession?.apply(taskIDs: displayedTaskIDs)
            }
            .onChange(of: displayedTaskIDs) { _, taskIDs in
                progressSession?.apply(taskIDs: taskIDs)
            }
            .onChange(of: quickTitle) { _, value in quickEntry.update(value, in: modelContext) }
            .onReceive(NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)) { notification in
                guard PersistenceCommandService.affects(.templates, in: notification) else { return }
                quickEntry.refresh(in: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudKitSyncService.eventChangedNotification)) { _ in
                quickEntry.refresh(in: modelContext)
            }
            .onChange(of: actionRequest) { _, request in
                handleActionRequest(request)
            }
            .onAppear {
                handleActionRequest(actionRequest)
            }
            .onDisappear {
                progressSession?.cancel()
                clearBoardNotice()
            }
        }
    }

    @ViewBuilder
    private var statusNoticeOverlay: some View {
        if let statusNotice {
            MobileStatusNotice(
                message: statusNotice, tone: statusNoticeTone,
                destinationTitle: statusDestinationTitle,
                onShowDestination: showStatusDestination,
                onUndo: completionUndoAction
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var statusDestinationTitle: String? {
        guard let statusDestination else { return nil }
        return "\(statusDestination.status.title) 보기"
    }

    private var completionUndoAction: (() -> Void)? {
        guard completionUndo != nil else { return nil }
        return { undoCompletion() }
    }

    @ViewBuilder
    private func boardLayout(tasks: [TodoTask]) -> some View {
        GeometryReader { geometry in
            let showsColumns = horizontalSizeClass == .regular
                && !dynamicTypeSize.isAccessibilitySize
                && geometry.size.width >= minimumBoardColumnWidth * 3
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        boardControls(tasks: tasks, showsColumns: showsColumns)
                        if let carryoverSession {
                            CarryoverArrivalBanner(session: carryoverSession) { presentedSheet = .carryover }
                                .padding(.horizontal, 16)
                                .padding(.bottom, carryoverSession.bannerKeys.isEmpty ? 0 : 12)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(TaskStatus.allCases) { status in
                                // Keep each list's identity stable while reflowing.
                                VStack(spacing: 12) {
                                    if showsColumns {
                                        HStack {
                                            Label(status.title, systemImage: status.systemImage)
                                                .font(.headline)
                                            Spacer()
                                            Text("\(BoardQueryRules.tasks(tasks, matching: status).count)")
                                                .foregroundStyle(AppTheme.secondaryText)
                                        }
                                        .padding(.horizontal, 16)
                                        .accessibilityIdentifier("board-column-\(status.rawValue)")
                                    }
                                    taskList(
                                        tasks: tasks,
                                        status: status,
                                        showsColumns: showsColumns,
                                        emptyStateMinimumHeight: showsColumns
                                            ? 240 : min(360, max(260, geometry.size.height * 0.4))
                                    )
                                }
                                .frame(maxWidth: showsColumns || selectedStatus == status ? .infinity : 0)
                                .frame(height: showsColumns || selectedStatus == status ? nil : 0)
                                .clipped()
                                .opacity(showsColumns || selectedStatus == status ? 1 : 0)
                                .accessibilityHidden(!showsColumns && selectedStatus != status)
                                .allowsHitTesting(showsColumns || selectedStatus == status)
                            }
                        }
                        .padding(.top, showsColumns ? 16 : 0)
                    }
                    .frame(maxWidth: showsColumns ? .infinity : 820)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("board-accessibility-scroll")
                .onChange(of: pendingScrollTaskID) { _, _ in scrollToDestination(using: proxy) }
                .onChange(of: BoardQueryRules.tasks(tasks, matching: selectedStatus).map(\.id)) { _, _ in
                    scrollToDestination(using: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func boardControls(tasks: [TodoTask], showsColumns: Bool) -> some View {
        BoardHeader(
            selectedDate: $selectedDate,
            isTodayBoard: isTodayBoard,
            selectedDayKey: selectedDayKey
        )
        BoardEventStrip(events: dayEvents)
        BoardQuickAdd(
            title: $quickTitle,
            focusRequestID: quickAddFocusRequestID,
            quickEntry: quickEntry,
            onAdd: addQuickTask,
            onAddSaved: addSavedQuickTask,
            onOpenSavedTasks: { presentedSheet = .savedTasks },
            onOpenTemplates: { presentedSheet = .templates }
        )
        BoardStatusPicker(
            selectedStatus: $selectedStatus,
            taskCount: { status in tasks.filter { $0.status == status.rawValue }.count }
        )
        .opacity(showsColumns ? 0 : 1)
        .frame(height: showsColumns ? 0 : nil)
        .clipped()
        .accessibilityHidden(showsColumns)
        .allowsHitTesting(!showsColumns)
    }

    private func taskList(
        tasks: [TodoTask],
        status: TaskStatus,
        showsColumns: Bool,
        emptyStateMinimumHeight: CGFloat
    ) -> some View {
        BoardTaskList(
            tasks: BoardQueryRules.tasks(tasks, matching: status),
            selectedStatus: status,
            isEmbeddedInScrollView: true,
            isBoardEmpty: tasks.isEmpty,
            showsEmptyStateIcon: !showsColumns,
            emptyStateMinimumHeight: emptyStateMinimumHeight,
            onAddTask: { quickAddFocusRequestID = UUID() },
            onEdit: { presentedSheet = .task($0) },
            onStartFocus: { onStartFocus($0.id) },
            onDelete: deleteTask,
            onSaveToLibrary: saveToLibrary,
            onStatusChange: requestTaskStatusChange,
            progressText: progressText,
            highlightedTaskID: highlightedTaskID
        )
        .id(status)
    }

    private func saveToLibrary(_ task: TodoTask) {
        saveToLibrary(taskID: task.id, title: task.title)
    }

    private func saveToLibrary(taskID: UUID, title: String) {
        do {
#if DEBUG
            if !didSimulateLibrarySaveFailure,
               PlanBaseLaunchEnvironment.isUITesting,
               ProcessInfo.processInfo.arguments.contains("--ui-testing-library-save-failure-once") {
                didSimulateLibrarySaveFailure = true
                throw CocoaError(.fileWriteUnknown)
            }
#endif
            _ = try SavedTaskLibraryService.save(taskID: taskID, in: modelContext)
            pendingLibrarySave = nil
            showBoardNotice("‘\(title)’ 작업을 자주 쓰는 작업으로 저장했어요")
        } catch {
            pendingLibrarySave = PendingMobileLibrarySave(taskID: taskID, title: title)
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if SavedTaskShortcutRules.query(in: title) != nil {
            addSavedQuickTask(nil)
            return
        }
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let nextOrder = try BoundedQueryService.nextOrder(
                    in: modelContext,
                    dayKey: selectedDayKey,
                    status: .todo
                )
                let task = TodoTask(
                    title: title,
                    status: .todo,
                    plannedAt: selectedDate,
                    order: nextOrder
                )
                modelContext.insert(task)
            }
            quickTitle = ""
            selectedStatus = .todo
        } catch {
            persistenceFailureMessage = "작업을 추가하지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func addSavedQuickTask(_ id: UUID?) {
        guard let task = quickEntry.add(input: quickTitle, selectedID: id, on: selectedDate, in: modelContext) else { return }
        quickTitle = ""
        selectedStatus = .todo
        showBoardNotice("‘\(task.title)’ 추가했어요")
    }

    private func deleteTask(_ task: TodoTask) {
        pendingTaskDeletion = PendingMobileTaskDeletion(taskID: task.id, title: task.title)
    }

    private func confirmTaskDeletion(_ pending: PendingMobileTaskDeletion) {
        pendingTaskDeletion = nil
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let candidates = try modelContext.fetch(
                    BoundedQueryService.taskCandidatesDescriptor(id: pending.taskID))
                if let task = BoundedQueryService.representativeTask(from: candidates) {
                    try TaskRules.delete(task, from: modelContext)
                }
            }
            showBoardNotice("작업을 삭제했어요")
        } catch {
            persistenceFailureMessage = "작업을 삭제하지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func requestTaskStatusChange(task: TodoTask, status: TaskStatus) {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard currentStatus != status else { return }

        let now = Date()
        if status == .done,
           currentStatus != .done,
           let reminderAt = TaskReminderRules.upcomingReminderDate(for: task, now: now) {
            pendingTaskCompletion = PendingMobileTaskCompletion(
                taskID: task.id,
                title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderAt
            )
            return
        }

        changeTaskStatus(task: task, status: status)
    }

    private func handleActionRequest(_ request: MobileBoardActionRequest?) {
        guard let request else { return }
        actionRequest = nil

        switch request.action {
        case .newTask:
            quickAddFocusRequestID = request.id
        case .confirmCompletion(let taskID):
            do {
                let candidates = try modelContext.fetch(
                    BoundedQueryService.taskCandidatesDescriptor(id: taskID)
                )
                guard let task = BoundedQueryService.representativeTask(from: candidates),
                      task.plannedDayKey == DayKey.today,
                      task.archivedAt == nil,
                      task.status == TaskStatus.doing.rawValue else {
                    showBoardNotice("작업이 변경되어 완료하지 못했습니다", tone: .error)
                    return
                }
                requestTaskStatusChange(task: task, status: .done)
            } catch {
                persistenceFailureMessage = "작업을 다시 불러오지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    private func completePendingTask(_ pending: PendingMobileTaskCompletion) {
        pendingTaskCompletion = nil
        do {
            let candidates = try modelContext.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: pending.taskID)
            )
            guard let task = BoundedQueryService.representativeTask(from: candidates) else {
                showBoardNotice("작업이 변경되어 완료하지 못했습니다", tone: .error)
                return
            }
            changeTaskStatus(
                task: task,
                status: .done
            )
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func changeTaskStatus(
        task: TodoTask,
        status: TaskStatus
    ) {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard currentStatus != status else { return }
        do {
            let undo: TaskCompletionUndoToken?
            if status == .done {
                undo = try TaskCompletionUndoService.complete(task, in: modelContext)
            } else {
                try PersistenceCommandService.perform(in: modelContext) {
                    try TaskLifecycleService.applyStatus(status, to: task, in: modelContext)
                }
                undo = nil
            }
            if status == .done {
                TaskNotificationScheduler.shared.cancelNotifications(for: [task.id])
            }
            if status == .done {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            showStatusNotice(task: task, status: status, undo: undo)
            if status == .doing {
                Swift.Task {
                    await TaskLiveActivityCoordinator.shared.resumeAfterExplicitStart(taskID: task.id, context: modelContext)
                }
            }
        } catch {
            persistenceFailureMessage = "작업 상태를 변경하지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func showStatusNotice(
        task: TodoTask, status: TaskStatus, undo: TaskCompletionUndoToken? = nil
    ) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = title.isEmpty
            ? status.transitionNotice
            : "\(title) · \(status.transitionNotice)"
        showBoardNotice(message, duration: undo == nil ? 8 : TaskCompletionUndoService.availabilityDuration)
        statusDestination = (task.id, status)
        completionUndo = undo
    }

    private func progressText(for task: TodoTask, at date: Date) -> String? {
        guard let progressSession else { return nil }
        return TaskProgressEventRules.detailText(
            projection: progressSession.projection(for: task.id),
            status: TaskStatus(rawValue: task.status) ?? .todo,
            now: date,
            completedAt: task.completedAt
        )
    }

    private func showPendingSheetNotice() {
        if let status = pendingSheetStatus {
            pendingSheetStatus = nil
            selectedStatus = status
        }
        guard let message = pendingSheetNotice else { return }
        pendingSheetNotice = nil
        showBoardNotice(message)
    }

    private func showStatusDestination() {
        guard let destination = statusDestination else { return }
        do {
            let candidates = try modelContext.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: destination.taskID)
            )
            guard let task = BoundedQueryService.representativeTask(from: candidates),
                  let status = TaskStatus(rawValue: task.status), task.archivedAt == nil else {
                showBoardNotice("작업이 변경되어 이동할 수 없어요", tone: .information)
                return
            }
            let dayKey = status == .done ? task.completedDayKey : task.plannedDayKey
            guard let dayKey, let date = DayKey.date(from: dayKey) else { return }
            selectedDate = date
            selectedStatus = status
            statusDestination = nil
            highlightTask(task.id)
        } catch {
            persistenceFailureMessage = "작업을 다시 불러오지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func undoCompletion() {
        guard let token = completionUndo else { return }
        do {
            guard try TaskCompletionUndoService.undo(token, in: modelContext) else {
                showBoardNotice("작업이 변경되었거나 취소할 수 있는 시간이 지났어요", tone: .information)
                return
            }
            selectedDate = token.boardDate
            selectedStatus = token.previousStatus
            showBoardNotice("완료를 취소했어요 · 이전 상태로 돌아왔어요")
            highlightTask(token.taskID)
            UISelectionFeedbackGenerator().selectionChanged()
        } catch {
            persistenceFailureMessage = "완료를 취소하지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func highlightTask(_ taskID: UUID) {
        highlightedTaskID = taskID
        pendingScrollTaskID = taskID
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard highlightedTaskID == taskID else { return }
            highlightedTaskID = nil
        }
    }

    private func scrollToDestination(using proxy: ScrollViewProxy) {
        guard let taskID = pendingScrollTaskID,
              BoardQueryRules.tasks(boardTasks, matching: selectedStatus).contains(where: { $0.id == taskID }) else { return }
        DispatchQueue.main.async {
            guard pendingScrollTaskID == taskID else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                proxy.scrollTo(taskID, anchor: .center)
            }
            pendingScrollTaskID = nil
        }
    }

    private func clearBoardNotice() {
        statusNoticeToken = UUID()
        statusNotice = nil
        statusDestination = nil
        completionUndo = nil
    }

    private func showBoardNotice(
        _ message: String, tone: MobileNoticeTone = .success, duration: TimeInterval = 4
    ) {
        clearBoardNotice()
        let token = statusNoticeToken
        statusNoticeTone = tone
        statusNotice = message

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard statusNoticeToken == token else { return }
            clearBoardNotice()
        }
    }
}

#endif
