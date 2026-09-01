#if os(watchOS)
import PlanBaseCore
import SwiftData
import SwiftUI
import WatchKit

private struct PendingWatchCompletion: Identifiable {
    let id = UUID()
    let taskID: UUID
    let title: String
    let reminderAt: Date
}

struct WatchTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var taskRows: [PlanBaseCore.Task]
    @Query private var eventRows: [CalendarEvent]

    let dayKey: String
    let startupIssue: String?

    @State private var quickTitle = ""
    @State private var pendingCompletion: PendingWatchCompletion?
    @State private var notice: String?

    init(dayKey: String, startupIssue: String?) {
        self.dayKey = dayKey
        self.startupIssue = startupIssue
        _taskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
        _eventRows = Query(
            BoundedQueryService.eventsDescriptor(
                overlappingStartDayKey: dayKey,
                endDayKey: dayKey
            )
        )
    }

    private var tasks: [PlanBaseCore.Task] {
        BoardQueryRules.tasksForBoard(taskRows, selectedDayKey: dayKey)
    }

    private var openTasks: [PlanBaseCore.Task] {
        tasks.filter { $0.status != TaskStatus.done.rawValue }
    }

    private var doneTasks: [PlanBaseCore.Task] {
        tasks.filter { $0.status == TaskStatus.done.rawValue }
    }

    private var events: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: dayKey, in: eventRows)
    }

    private var contentFingerprint: String {
        let taskValues = taskRows.map {
            "\($0.instanceID)|\($0.status)|\($0.updatedAt.timeIntervalSinceReferenceDate)"
        }
        let eventValues = eventRows.map {
            "\($0.instanceID)|\($0.updatedAt.timeIntervalSinceReferenceDate)"
        }
        return (taskValues + eventValues).sorted().joined(separator: ";")
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if let startupIssue {
                    Label(startupIssue, systemImage: "exclamationmark.icloud")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                quickAddSection
                taskSection

                if !events.isEmpty {
                    eventSection
                }

                if !doneTasks.isEmpty {
                    completedSection
                }
            }
            .navigationTitle("오늘")
            .refreshable {
                publishWidget(forceWrite: true)
            }
            .task(id: contentFingerprint) {
                publishWidget(forceWrite: false)
            }
            .alert(item: $pendingCompletion) { pending in
                Alert(
                    title: Text("알림이 남아 있어요"),
                    message: Text("\(pending.title)을 완료하면 \(pending.reminderAt.formatted(date: .omitted, time: .shortened)) 알림은 iPhone 동기화 후 정리됩니다."),
                    primaryButton: .default(Text("완료")) {
                        completePendingTask(pending)
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 8) {
                WatchSummaryMetric(
                    value: openTasks.count,
                    label: "남음",
                    color: .blue
                )
                WatchSummaryMetric(
                    value: doneTasks.count,
                    label: "완료",
                    color: .green
                )
                WatchSummaryMetric(
                    value: events.count,
                    label: "일정",
                    color: .orange
                )
            }
        }
    }

    private var quickAddSection: some View {
        Section("빠른 추가") {
            TextField("할 일 말하기", text: $quickTitle)
                .onSubmit(addTask)

            Button(action: addTask) {
                Label("오늘 할 일 추가", systemImage: "plus")
            }
            .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var taskSection: some View {
        Section("할 일") {
            if openTasks.isEmpty {
                Label("남은 할 일이 없어요", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openTasks, id: \.instanceID) { task in
                    WatchTaskRow(task: task) {
                        requestPrimaryAction(for: task)
                    }
                }
            }
        }
    }

    private var eventSection: some View {
        Section("일정") {
            ForEach(events.prefix(5), id: \.instanceID) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .lineLimit(2)
                        if event.startDayKey != event.endDayKey {
                            Text(CalendarEventTimeline.badgeText(for: event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var completedSection: some View {
        Section("완료") {
            ForEach(doneTasks.prefix(5), id: \.instanceID) { task in
                WatchTaskRow(task: task) {
                    changeStatus(of: task, to: .doing)
                }
            }
        }
    }

    private func addTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let plannedAt = DayKey.date(from: dayKey) else { return }

        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let order = try BoundedQueryService.nextOrder(
                    in: modelContext,
                    dayKey: dayKey,
                    status: .todo
                )
                modelContext.insert(PlanBaseCore.Task(
                    title: title,
                    plannedAt: plannedAt,
                    order: order
                ))
            }
            quickTitle = ""
            WKInterfaceDevice.current().play(.success)
            showNotice("할 일을 추가했어요")
            publishWidget(forceWrite: true)
        } catch {
            showNotice("추가하지 못했어요")
        }
    }

    private func requestPrimaryAction(for task: PlanBaseCore.Task) {
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        let nextStatus = currentStatus.primaryActionStatus
        let now = Date()

        if nextStatus == .done,
           let reminderAt = TaskReminderRules.upcomingReminderDate(for: task, now: now) {
            pendingCompletion = PendingWatchCompletion(
                taskID: task.id,
                title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderAt
            )
            return
        }
        changeStatus(of: task, to: nextStatus)
    }

    private func completePendingTask(_ pending: PendingWatchCompletion) {
        do {
            let candidates = try modelContext.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: pending.taskID)
            )
            guard let task = BoundedQueryService.representativeTask(from: candidates) else {
                showNotice("작업이 변경되었어요")
                return
            }
            changeStatus(of: task, to: .done)
        } catch {
            showNotice("작업을 불러오지 못했어요")
        }
    }

    private func changeStatus(of task: PlanBaseCore.Task, to status: TaskStatus) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                try TaskLifecycleService.applyStatus(
                    status,
                    to: task,
                    in: modelContext,
                    now: Date()
                )
            }
            WKInterfaceDevice.current().play(status == .done ? .success : .click)
            showNotice(status.transitionNotice)
            publishWidget(forceWrite: true)
        } catch {
            showNotice("상태를 바꾸지 못했어요")
        }
    }

    private func publishWidget(forceWrite: Bool) {
        do {
            try WatchWidgetSnapshotPublicationService.publish(
                context: modelContext,
                forceWrite: forceWrite
            )
        } catch {
            print("PlanBase Watch 위젯 갱신 실패: \(error.localizedDescription)")
        }
    }

    private func showNotice(_ message: String) {
        notice = message
    }
}

private struct WatchSummaryMetric: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchTaskRow: View {
    let task: PlanBaseCore.Task
    let action: () -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .lineLimit(2)
                    .strikethrough(status == .done)
                Text(status.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button(action: action) {
                Image(systemName: status.primaryActionSystemImage)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(status == .doing ? .green : .blue)
            .accessibilityLabel(status.primaryActionTitle)
        }
    }
}
#endif
