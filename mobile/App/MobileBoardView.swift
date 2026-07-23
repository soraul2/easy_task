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

private struct PendingMobileTaskCompletion {
    var taskID: UUID
    var title: String
    var reminderAt: Date
    var completionDayKey: String
}

struct MobileBoardView: View {
    @Binding var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Query private var selectedDayTaskRows: [TodoTask]
    @Query private var carryoverTaskRows: [TodoTask]
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?
    @State private var pendingTaskCompletion: PendingMobileTaskCompletion?
    @State private var statusNotice: String?
    @State private var statusNoticeToken = UUID()

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var isTodayBoard: Bool { selectedDayKey == DayKey.today }

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate

        let dayKey = DayKey.key(for: selectedDate.wrappedValue)
        _selectedDayTaskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
        _carryoverTaskRows = Query(
            BoundedQueryService.carryoverTasksDescriptor(before: dayKey)
        )
        _overlappingEventRows = Query(
            BoundedQueryService.eventsDescriptor(
                overlappingStartDayKey: dayKey,
                endDayKey: dayKey
            )
        )
    }

    private var boardTasks: [TodoTask] {
        var rows = selectedDayTaskRows
        if isTodayBoard {
            let selectedTaskIDs = Set(rows.map(\.id))
            rows.append(contentsOf: carryoverTaskRows.filter { !selectedTaskIDs.contains($0.id) })
        }

        return BoardQueryRules.tasksForBoard(
            rows,
            selectedDayKey: selectedDayKey,
            includeCarryoverOnToday: true
        )
    }

    private var statusTasks: [TodoTask] {
        BoardQueryRules.tasks(boardTasks, matching: selectedStatus)
    }

    private var dayEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey, in: overlappingEventRows)
    }

    private var carryoverTasks: [TodoTask] {
        TaskRules.carryoverTasks(carryoverTaskRows, before: selectedDayKey)
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
                BoardStatusPicker(
                    selectedStatus: $selectedStatus,
                    taskCount: taskCount
                )
                BoardTaskList(
                    tasks: statusTasks,
                    selectedStatus: selectedStatus,
                    onEdit: { presentedSheet = .task($0) },
                    onDelete: deleteTask,
                    onStatusChange: requestTaskStatusChange
                )
            }
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let statusNotice {
                    MobileStatusNotice(message: statusNotice)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: statusNotice)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { presentedSheet = .carryover } label: {
                        Image(systemName: "tray")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("이월함")
                    .accessibilityIdentifier("carryover-button")

                    Button { presentedSheet = .templates } label: {
                        Image(systemName: "square.on.square")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("템플릿")
                    .accessibilityIdentifier("template-library-button")

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
                    MobileTaskDetailSheet(task: task)
                case .carryover:
                    MobileCarryoverSheet(
                        tasks: carryoverTasks,
                        onApplied: showBoardNotice
                    )
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
        }
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
            showBoardNotice("작업을 추가하지 못했습니다")
        }
    }

    private func deleteTask(_ task: TodoTask) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                try TaskRules.delete(task, from: modelContext)
            }
        } catch {
            showBoardNotice("작업을 삭제하지 못했습니다")
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
                reminderAt: reminderAt,
                completionDayKey: selectedDayKey
            )
            return
        }

        changeTaskStatus(task: task, status: status, completionDayKey: selectedDayKey)
    }

    private func completePendingTask(_ pending: PendingMobileTaskCompletion) {
        pendingTaskCompletion = nil
        do {
            guard let task = try modelContext.fetch(
                BoundedQueryService.taskDescriptor(id: pending.taskID)
            ).first else {
                showBoardNotice("작업이 변경되어 완료하지 못했습니다")
                return
            }
            changeTaskStatus(
                task: task,
                status: .done,
                completionDayKey: pending.completionDayKey
            )
        } catch {
            showBoardNotice("작업을 다시 불러오지 못했습니다")
        }
    }

    private func changeTaskStatus(
        task: TodoTask,
        status: TaskStatus,
        completionDayKey: String
    ) {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        guard currentStatus != status else { return }
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.applyStatus(status, to: task, completionDayKey: completionDayKey)
            }
            if status == .done {
                TaskNotificationScheduler.shared.cancelNotifications(for: [task.id])
            }
            UISelectionFeedbackGenerator().selectionChanged()
            showStatusNotice(task: task, status: status)
        } catch {
            showBoardNotice("작업 상태를 변경하지 못했습니다")
        }
    }

    private func showStatusNotice(task: TodoTask, status: TaskStatus) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = title.isEmpty
            ? status.transitionNotice
            : "\(title) · \(status.transitionNotice)"
        showBoardNotice(message)
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
