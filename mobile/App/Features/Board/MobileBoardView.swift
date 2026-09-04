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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var selectedDayTaskRows: [TodoTask]
    @Query private var carryoverTaskRows: [TodoTask]
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var quickAddFocusRequestID: UUID?
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?
    @State private var pendingTaskCompletion: PendingMobileTaskCompletion?
    @State private var pendingTaskDeletion: PendingMobileTaskDeletion?
    @State private var persistenceFailureMessage: String?
    @State private var statusNotice: String?
    @State private var statusNoticeToken = UUID()
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

    private var boardTasks: [TodoTask] {
        return BoardQueryRules.tasksForBoard(
            selectedDayTaskRows.filter { $0.modelContext != nil },
            selectedDayKey: selectedDayKey
        )
    }

    private var statusTasks: [TodoTask] {
        BoardQueryRules.tasks(boardTasks, matching: selectedStatus)
    }

    private var displayedTaskIDs: Set<UUID> {
        Set(boardTasks.map(\.id))
    }

    private var dayEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey, in: overlappingEventRows)
    }

    private var carryoverTasks: [TodoTask] {
        TaskRules.carryoverTasks(carryoverTaskRows, before: DayKey.today)
    }

    var body: some View {
        NavigationStack {
            boardLayout
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let statusNotice {
                    MobileStatusNotice(message: statusNotice)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
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
                        Image(systemName: "tray")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("이월함")
                    .accessibilityIdentifier("carryover-button")

                    Button { presentedSheet = .review } label: {
                        Image(systemName: "book.closed")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("회고 작성")
                    .accessibilityIdentifier("review-compose-button")
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .task(let task):
                    MobileTaskDetailSheet(task: task, onStartFocus: onStartFocus)
                case .carryover:
                    MobileCarryoverSheet(
                        tasks: carryoverTasks,
                        onApplied: showBoardNotice
                    )
                case .savedTasks:
                    SavedTaskLibrarySheet(
                        selectedDate: selectedDate,
                        onAdded: { message in
                            selectedStatus = .todo
                            showBoardNotice(message)
                        }
                    )
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                case .templates:
                    MobileTemplateLibrarySheet(
                        templates: templates,
                        items: templateItems,
                        selectedDate: selectedDate,
                        existingTasks: selectedDayTaskRows,
                        onApplied: showBoardNotice
                    )
                case .review:
                    MobileReviewComposerSheet(
                        selectedDate: selectedDate,
                        onSaved: showBoardNotice
                    )
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
            .task {
                if progressSession == nil {
                    progressSession = TaskProgressEventQuerySession(context: modelContext)
                }
                progressSession?.apply(taskIDs: displayedTaskIDs)
            }
            .onChange(of: displayedTaskIDs) { _, taskIDs in
                progressSession?.apply(taskIDs: taskIDs)
            }
            .onChange(of: actionRequest) { _, request in
                handleActionRequest(request)
            }
            .onAppear {
                handleActionRequest(actionRequest)
            }
            .onDisappear {
                progressSession?.cancel()
            }
        }
    }

    @ViewBuilder
    private var boardLayout: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                boardControls
                taskList(isEmbeddedInScrollView: true)
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("board-accessibility-scroll")
    }

    @ViewBuilder
    private var boardControls: some View {
        BoardHeader(
            selectedDate: $selectedDate,
            isTodayBoard: isTodayBoard,
            selectedDayKey: selectedDayKey
        )
        BoardEventStrip(events: dayEvents)
        BoardQuickAdd(
            title: $quickTitle,
            focusRequestID: quickAddFocusRequestID,
            onAdd: addQuickTask,
            onOpenSavedTasks: { presentedSheet = .savedTasks },
            onOpenTemplates: { presentedSheet = .templates }
        )
        BoardStatusPicker(
            selectedStatus: $selectedStatus,
            taskCount: taskCount
        )
    }

    private func taskList(isEmbeddedInScrollView: Bool) -> some View {
        BoardTaskList(
            tasks: statusTasks,
            selectedStatus: selectedStatus,
            isEmbeddedInScrollView: isEmbeddedInScrollView,
            onEdit: { presentedSheet = .task($0) },
            onStartFocus: { onStartFocus($0.id) },
            onDelete: deleteTask,
            onSaveToLibrary: saveToLibrary,
            onStatusChange: requestTaskStatusChange,
            progressText: progressText
        )
    }

    private func saveToLibrary(_ task: TodoTask) {
        do {
            _ = try SavedTaskLibraryService.save(taskID: task.id, in: modelContext)
            showBoardNotice("저장한 작업에 추가했어요")
        } catch { persistenceFailureMessage = error.localizedDescription }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
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
                    showBoardNotice("작업이 변경되어 완료하지 못했습니다")
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
                showBoardNotice("작업이 변경되어 완료하지 못했습니다")
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
            try PersistenceCommandService.perform(in: modelContext) {
                try TaskLifecycleService.applyStatus(
                    status,
                    to: task,
                    in: modelContext,
                    now: Date()
                )
            }
            if status == .done {
                TaskNotificationScheduler.shared.cancelNotifications(for: [task.id])
            }
            if status == .done {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            showStatusNotice(task: task, status: status)
        } catch {
            persistenceFailureMessage = "작업 상태를 변경하지 못했습니다. 다시 시도해 주세요."
        }
    }

    private func showStatusNotice(task: TodoTask, status: TaskStatus) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = title.isEmpty
            ? status.transitionNotice
            : "\(title) · \(status.transitionNotice)"
        if status == .done, !isTodayBoard {
            showBoardNotice("\(message) · 오늘 완료에서 확인")
        } else {
            showBoardNotice(message)
        }
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

    private func taskCount(for status: TaskStatus) -> Int {
        boardTasks.reduce(into: 0) { result, task in
            if task.status == status.rawValue {
                result += 1
            }
        }
    }

    private func showBoardNotice(_ message: String) {
        let token = UUID()

        statusNoticeToken = token
        statusNotice = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard statusNoticeToken == token else { return }
            statusNotice = nil
        }
    }
}

#endif
