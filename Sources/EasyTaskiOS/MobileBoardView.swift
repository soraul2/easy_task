#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI
import Foundation

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
    var onShowTheme: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var selectedDayTaskRows: [TodoTask]
    @Query private var carryoverTaskRows: [TodoTask]
    @Query private var overlappingEventRows: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?
    @State private var statusNotice: String?
    @State private var statusNoticeToken = UUID()

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var isTodayBoard: Bool { selectedDayKey == DayKey.today }

    init(
        selectedDate: Binding<Date>,
        onShowTheme: @escaping () -> Void = {}
    ) {
        _selectedDate = selectedDate
        self.onShowTheme = onShowTheme

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
                BoardStatusPicker(selectedStatus: $selectedStatus)
                BoardTaskList(
                    tasks: statusTasks,
                    selectedStatus: selectedStatus,
                    onEdit: { presentedSheet = .task($0) },
                    onDelete: deleteTask,
                    onStatusChange: changeTaskStatus
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
                    MobileCloudKitSyncStatusButton()

                    MobileThemeButton(action: onShowTheme)

                    Button { presentedSheet = .review } label: {
                        Image(systemName: "book.closed")
                    }
                    .accessibilityLabel("회고 작성")
                    .accessibilityIdentifier("review-compose-button")

                    Menu {
                        Button { presentedSheet = .carryover } label: {
                            Label("이월함", systemImage: "tray")
                        }
                        Button { presentedSheet = .templates } label: {
                            Label("템플릿 적용", systemImage: "square.on.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("보드 작업")
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

    private func changeTaskStatus(task: TodoTask, status: TaskStatus) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.applyStatus(status, to: task, completionDayKey: selectedDayKey)
            }
            showStatusNotice(task: task, status: status)
        } catch {
            showBoardNotice("작업 상태를 변경하지 못했습니다")
        }
    }

    private func showStatusNotice(task: TodoTask, status: TaskStatus) {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = title.isEmpty ? "\(status.title)로 이동됨" : "\(title) · \(status.title)로 이동됨"
        showBoardNotice(message)
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
