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
    @State private var noticeIsError = false
    @State private var activeFocus: FocusActiveSessionSnapshot?

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
        List {
            summarySection

            if let activeFocus {
                activeFocusSection(activeFocus)
            }

            if let startupIssue {
                Label(startupIssue, systemImage: "exclamationmark.icloud")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let notice {
                Label(notice, systemImage: noticeIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(noticeIsError ? .orange : .green)
                    .accessibilityValue(noticeIsError ? "오류" : "")
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
            reloadActiveFocus()
            publishWidget(forceWrite: true)
        }
        .task(id: contentFingerprint) {
            reloadActiveFocus()
            publishWidget(forceWrite: false)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reloadActiveFocus()
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

    private func activeFocusSection(_ active: FocusActiveSessionSnapshot) -> some View {
        Section("집중") {
            NavigationLink(value: WatchFocusDestination(taskID: active.taskID)) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = FocusTimerRules.remainingSeconds(
                        for: active,
                        now: timeline.date
                    )
                    HStack(spacing: 8) {
                        Image(systemName: active.runState == .paused
                            ? "pause.circle.fill"
                            : "timer.circle.fill")
                            .foregroundStyle(active.phase == .focus ? .blue : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.taskTitleSnapshot)
                                .lineLimit(1)
                                .privacySensitive()
                            Text(Self.focusClock(remaining))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: remaining) { _, value in
                        if value <= 0 {
                            reconcileActiveFocus()
                        }
                    }
                }
            }
            .accessibilityLabel("진행 중인 집중 모드 열기")
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
            showNotice("추가하지 못했어요", isError: true)
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
                showNotice("작업이 변경되었어요. 목록을 확인해 주세요.", isError: true)
                return
            }
            changeStatus(of: task, to: .done)
        } catch {
            showNotice("작업을 불러오지 못했어요", isError: true)
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
            showNotice("상태를 바꾸지 못했어요", isError: true)
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

    @MainActor
    private func reloadActiveFocus() {
        do {
            activeFocus = try FocusSessionService.activeSnapshot()
        } catch {
            activeFocus = nil
            showNotice("집중 상태를 불러오지 못했어요", isError: true)
        }
    }

    @MainActor
    private func reconcileActiveFocus() {
        do {
            switch try FocusSessionService.reconcile(in: modelContext) {
            case .focusEnded, .breakEnded:
                WKInterfaceDevice.current().play(.notification)
            case .unchanged, .noActiveSession:
                break
            }
            reloadActiveFocus()
            publishWidget(forceWrite: true)
        } catch {
            showNotice("집중 기록을 저장하지 못했어요", isError: true)
        }
    }

    private static func focusClock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func showNotice(_ message: String, isError: Bool = false) {
        notice = message
        noticeIsError = isError
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let task: PlanBaseCore.Task
    let action: () -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var usesLargeTextLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(status == .done ? Color.secondary : Color.primary)
                    .lineLimit(usesLargeTextLayout ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(status == .done)
                    .privacySensitive()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { summaryDetails }
                    VStack(alignment: .leading, spacing: 5) { summaryDetails }
                }

                if let reminderAt = TaskReminderRules.normalizedDate(task.reminderAt) {
                    Label {
                        Text("\(status == .done ? "설정했던 알림" : "알림") \(reminderAt.formatted(date: .abbreviated, time: .shortened))")
                    } icon: {
                        Image(systemName: status == .done ? "bell.slash" : "bell")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Divider()

            if usesLargeTextLayout {
                VStack(spacing: 8) {
                    primaryAction
                    if status != .done { focusLink }
                }
            } else {
                HStack(spacing: 8) {
                    primaryAction
                    if status != .done { focusLink }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    status == .doing
                        ? Color.blue.opacity(0.60)
                        : Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
                    lineWidth: 1
                )
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var summaryDetails: some View {
        Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status == .doing ? Color.blue : Color.secondary)
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)

        if let minutes = task.estimatedMinutes, minutes > 0 {
            Text("예상 \(EstimatedTimeFormatter.short(minutes))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryAction: some View {
        Button(action: action) {
            Text(status.primaryActionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status == .doing ? Color.blue : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    status == .doing ? Color.blue.opacity(0.20) : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title) \(status.primaryActionTitle)")
    }

    private var focusLink: some View {
        NavigationLink(value: WatchFocusDestination(taskID: task.id)) {
            Group {
                if usesLargeTextLayout {
                    Label("집중 시작", systemImage: "timer")
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Image(systemName: "timer")
                        .frame(width: 44, height: 44)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title) 집중 시작")
    }
}
#endif
