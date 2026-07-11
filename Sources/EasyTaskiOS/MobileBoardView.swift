#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI

private enum MobileBoardSheet: Identifiable {
    case task(TodoTask)
    case carryover
    case templates
    case review
    case theme

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .carryover: "carryover"
        case .templates: "templates"
        case .review: "review"
        case .theme: "theme"
        }
    }
}

struct MobileBoardView: View {
    @Binding var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var quickTitle = ""
    @State private var selectedStatus: TaskStatus = .todo
    @State private var presentedSheet: MobileBoardSheet?
    @State private var statusNotice: String?
    @State private var statusNoticeToken = UUID()

    private var selectedDayKey: String { DayKey.key(for: selectedDate) }
    private var isTodayBoard: Bool { selectedDayKey == DayKey.today }

    private var boardTasks: [TodoTask] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: selectedDayKey,
            includeCarryoverOnToday: true
        )
    }

    private var statusTasks: [TodoTask] {
        BoardQueryRules.tasks(boardTasks, matching: selectedStatus)
    }

    private var dayEvents: [CalendarEvent] {
        CalendarEventRules.events(onDayKey: selectedDayKey, in: events)
    }

    private var carryoverTasks: [TodoTask] {
        TaskRules.carryoverTasks(tasks, before: selectedDayKey)
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

                    Menu {
                        Button { presentedSheet = .carryover } label: {
                            Label("이월함", systemImage: "tray")
                        }
                        Button { presentedSheet = .templates } label: {
                            Label("템플릿 적용", systemImage: "square.on.square")
                        }
                        Button { presentedSheet = .review } label: {
                            Label("회고 작성", systemImage: "book.closed")
                        }
                        Button { presentedSheet = .theme } label: {
                            Label("테마", systemImage: "paintpalette")
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
                        targetDate: selectedDate,
                        onApplied: showBoardNotice
                    )
                case .templates:
                    MobileTemplateLibrarySheet(
                        templates: templates,
                        items: templateItems,
                        selectedDate: selectedDate,
                        existingTasks: tasks,
                        onApplied: showBoardNotice
                    )
                case .review:
                    MobileReviewComposerSheet(selectedDate: selectedDate)
                case .theme:
                    MobileThemePickerSheet()
                }
            }
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let task = TodoTask(
                    title: title,
                    status: .todo,
                    plannedAt: selectedDate,
                    order: BoardQueryRules.nextOrder(in: tasks, dayKey: selectedDayKey, status: .todo)
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

private struct BoardHeader: View {
    @Binding var selectedDate: Date
    var isTodayBoard: Bool
    var selectedDayKey: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                selectedDate = DayKey.addingDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 날짜")

            VStack(alignment: .leading, spacing: 2) {
                Text(DayKey.display(selectedDate))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(isTodayBoard ? "오늘 보드" : selectedDayKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("오늘") {
                selectedDate = DayKey.startOfDay(for: Date())
            }
            .buttonStyle(.bordered)

            Button {
                selectedDate = DayKey.addingDays(1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("다음 날짜")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

private struct BoardEventStrip: View {
    var events: [CalendarEvent]

    var body: some View {
        if !events.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        Label(event.title, systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(CalendarEventPalette.color(for: event.color).opacity(0.18), in: Capsule())
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
        }
    }
}

private struct BoardQuickAdd: View {
    @Binding var title: String
    var onAdd: () -> Void

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("해당 날짜에 할 일 입력", text: $title)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit(onAdd)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.headline)
            }
            .disabled(!canAdd)
            .accessibilityLabel("작업 추가")
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct BoardStatusPicker: View {
    @Binding var selectedStatus: TaskStatus

    var body: some View {
        Picker("상태", selection: $selectedStatus) {
            ForEach(TaskStatus.allCases) { status in
                Text(status.title).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct BoardTaskList: View {
    var tasks: [TodoTask]
    var selectedStatus: TaskStatus
    var onEdit: (TodoTask) -> Void
    var onDelete: (TodoTask) -> Void
    var onStatusChange: (TodoTask, TaskStatus) -> Void

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "\(selectedStatus.title) 작업 없음",
                    systemImage: "checklist",
                    description: Text("빠른 입력이나 템플릿으로 작업을 추가하세요.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(tasks) { task in
                    MobileTaskRow(
                        task: task,
                        onEdit: { onEdit(task) },
                        onDelete: { onDelete(task) },
                        onStatusChange: { onStatusChange(task, $0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: MobileLayout.bottomTabClearance)
        }
    }
}

private struct MobileTaskRow: View {
    var task: TodoTask
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onStatusChange: (TaskStatus) -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var cardColor: Color {
        switch status {
        case .todo: AppTheme.todo
        case .doing: AppTheme.doing
        case .done: AppTheme.done
        }
    }

    private var accentColor: Color {
        switch status {
        case .todo: AppTheme.secondaryText
        case .doing: AppTheme.event
        case .done: AppTheme.done
        }
    }

    private var cardFillOpacity: Double {
        status == .done ? 0.76 : 0.96
    }

    private var shadowOpacity: Double {
        switch status {
        case .todo: 0.10
        case .doing: 0.20
        case .done: 0.12
        }
    }

    private var priority: TaskPriority? {
        task.priority.flatMap(TaskPriority.init(rawValue:))
    }

    private var visibleTags: [String] {
        task.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasDetails: Bool {
        priority != nil || task.estimatedMinutes != nil || !visibleTags.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(AppTheme.cardText)
                    if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.cardMutedText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("작업 편집")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(AppTheme.panel.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("작업 삭제")
                }
                .foregroundStyle(.secondary)
            }

            if hasDetails {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let priority {
                            MobileTaskDetailChip(
                                title: priority.title,
                                systemImage: "flag.fill"
                            )
                        }
                        if let estimatedMinutes = task.estimatedMinutes {
                            MobileTaskDetailChip(
                                title: EstimatedTimeFormatter.short(estimatedMinutes),
                                systemImage: "clock"
                            )
                        }
                        ForEach(visibleTags, id: \.self) { tag in
                            MobileTaskDetailChip(title: "#\(tag)", systemImage: "tag")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MobileTaskStatusSlider(status: status, accentColor: accentColor) { nextStatus in
                onStatusChange(nextStatus)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(cardColor.opacity(cardFillOpacity))
        }
        .shadow(color: accentColor.opacity(shadowOpacity), radius: status == .doing ? 18 : 12, x: 0, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

private struct MobileTaskDetailChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.panel.opacity(0.52), in: Capsule())
    }
}

private struct MobileStatusNotice: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "arrow.right.circle.fill")
            .font(.caption.weight(.bold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(AppTheme.eventText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.event.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MobileTaskStatusSlider: View {
    var status: TaskStatus
    var accentColor: Color
    var onChange: (TaskStatus) -> Void

    private var statuses: [TaskStatus] {
        TaskStatus.allCases
    }

    private var selectedIndex: Int {
        statuses.firstIndex(of: status) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = width / CGFloat(max(statuses.count, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.input.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border.opacity(0.26), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.94))
                    .frame(width: max(segmentWidth - 6, 0), height: 34)
                    .offset(x: CGFloat(selectedIndex) * segmentWidth + 3)
                    .shadow(color: accentColor.opacity(0.22), radius: 8, x: 0, y: 3)
                    .animation(.snappy(duration: 0.18), value: selectedIndex)

                HStack(spacing: 0) {
                    ForEach(statuses) { nextStatus in
                        Text(nextStatus.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(nextStatus == status ? AppTheme.eventText : AppTheme.cardText)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        updateStatus(status(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("작업 상태")
        .accessibilityValue(status.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                updateStatus(status(offsetBy: 1))
            case .decrement:
                updateStatus(status(offsetBy: -1))
            @unknown default:
                break
            }
        }
    }

    private func updateStatus(_ nextStatus: TaskStatus) {
        guard nextStatus != status else { return }
        onChange(nextStatus)
    }

    private func status(at x: CGFloat, width: CGFloat) -> TaskStatus {
        guard width > 0 else { return status }
        let segmentWidth = width / CGFloat(max(statuses.count, 1))
        let index = min(max(Int(x / segmentWidth), 0), statuses.count - 1)
        return statuses[index]
    }

    private func status(offsetBy offset: Int) -> TaskStatus {
        let index = min(max(selectedIndex + offset, 0), statuses.count - 1)
        return statuses[index]
    }
}

private struct MobileTaskDetailSheet: View {
    var task: TodoTask
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TodoTask]
    @State private var title: String
    @State private var note: String
    @State private var status: TaskStatus
    @State private var plannedDate: Date
    @State private var priority: TaskPriority?
    @State private var estimatedMinutesText: String
    @State private var tagsText: String
    @State private var saveError: String?

    init(task: TodoTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _priority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("기본") {
                    TextField("제목", text: $title)
                    DatePicker("보드 날짜", selection: $plannedDate, displayedComponents: .date)
                    Picker("상태", selection: $status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("상세") {
                    TextField("메모", text: $note, axis: .vertical)
                    Picker("우선순위", selection: $priority) {
                        Text("없음").tag(nil as TaskPriority?)
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority as TaskPriority?)
                        }
                    }
                    TextField("예상 시간(분)", text: $estimatedMinutesText)
                        .keyboardType(.numberPad)
                    TextField("태그(쉼표로 구분)", text: $tagsText)
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("작업 상세")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let oldDayKey = task.plannedDayKey
        let oldStatus = TaskStatus(rawValue: task.status) ?? .todo
        let newPlannedAt = DayKey.startOfDay(for: plannedDate)
        let newDayKey = DayKey.key(for: newPlannedAt)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimateInput = parsedEstimatedMinutesInput()
        if let errorMessage = estimateInput.errorMessage {
            saveError = errorMessage
            return
        }
        let estimatedMinutes = estimateInput.value
        let tags = parsedTags()

        saveError = nil
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                if oldStatus != status {
                    TaskRules.applyStatus(status, to: task, completionDayKey: newDayKey)
                }

                var nextOrder: Double?
                if oldDayKey != newDayKey || oldStatus != status {
                    let dayTasks = allTasks.filter {
                        $0.id != task.id && $0.plannedDayKey == newDayKey && $0.archivedAt == nil
                    }
                    nextOrder = BoardQueryRules.nextOrder(in: dayTasks, dayKey: newDayKey, status: status)
                }
                if oldDayKey != newDayKey || nextOrder != nil {
                    TaskRules.move(task, to: newPlannedAt, order: nextOrder)
                }

                task.title = trimmedTitle
                task.note = trimmedNote.isEmpty ? nil : trimmedNote
                task.priority = priority?.rawValue
                task.estimatedMinutes = estimatedMinutes
                task.tags = tags
                task.updatedAt = Date()
            }
            dismiss()
        } catch {
            saveError = "작업을 저장하지 못했습니다"
        }
    }

    private func parsedEstimatedMinutesInput() -> (value: Int?, errorMessage: String?) {
        let value = estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil) }
        guard let minutes = Int(value), (1...(24 * 60)).contains(minutes) else {
            return (nil, "예상 시간은 1~1440분 사이의 숫자로 입력해 주세요")
        }
        return (minutes, nil)
    }

    private func parsedTags() -> [String] {
        var seen: Set<String> = []
        return tagsText
            .split(separator: ",")
            .compactMap { rawTag in
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
                return tag
            }
    }
}

private struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var targetDate: Date
    var onApplied: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var movedTaskIDs: Set<UUID> = []
    @State private var message: String?
    @State private var isErrorMessage = false

    private var remainingTasks: [TodoTask] {
        tasks.filter { !movedTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if remainingTasks.isEmpty {
                    ContentUnavailableView("이월할 작업 없음", systemImage: "tray")
                } else {
                    Section {
                        if let message {
                            Label(
                                message,
                                systemImage: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isErrorMessage ? Color.red : Color.secondary)
                        }
                        Button {
                            moveAllToTargetDate()
                        } label: {
                            Label("모두 이 날짜로 이월", systemImage: "calendar.badge.plus")
                        }
                        Button(role: .destructive) {
                            completeAll()
                        } label: {
                            Label("모두 완료 처리", systemImage: "checkmark.circle")
                        }
                    }
                    ForEach(remainingTasks) { task in
                        Button {
                            moveToTargetDate(task)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .lineLimit(2)
                                    Text(task.plannedDayKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("이월함")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func completeAll() {
        let tasksToComplete = remainingTasks
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.completeAll(tasksToComplete, completionDayKey: DayKey.key(for: targetDate))
            }
            onApplied("\(tasksToComplete.count)개 이월 작업을 완료 처리했어요")
            dismiss()
        } catch {
            showError("이월 작업을 완료하지 못했습니다")
        }
    }

    private func moveAllToTargetDate() {
        let tasksToMove = remainingTasks
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                for task in tasksToMove {
                    TaskRules.move(task, to: targetDate)
                }
            }
            onApplied("\(tasksToMove.count)개 작업을 \(DayKey.display(targetDate))로 이월했어요")
            dismiss()
        } catch {
            showError("작업을 이월하지 못했습니다")
        }
    }

    private func moveToTargetDate(_ task: TodoTask) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.move(task, to: targetDate)
            }
            movedTaskIDs.insert(task.id)
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let notice = title.isEmpty ? "작업을 \(DayKey.display(targetDate))로 이월했어요" : "\(title) · \(DayKey.display(targetDate))로 이월했어요"
            isErrorMessage = false
            message = notice
            onApplied(notice)
        } catch {
            showError("작업을 이월하지 못했습니다")
        }
    }

    private func showError(_ errorMessage: String) {
        isErrorMessage = true
        message = errorMessage
    }
}

private struct MobileTemplateLibrarySheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var selectedDate: Date
    var existingTasks: [TodoTask]
    var onApplied: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites
    @State private var message: String?
    @State private var pendingTemplate: TaskTemplate?
    @State private var pendingDeleteTemplate: TaskTemplate?
    @State private var templateName = ""
    @State private var templateDrafts: [TemplateTaskDraft] = []

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
    }

    private var currentBoardTasks: [TodoTask] {
        let dayKey = DayKey.key(for: selectedDate)
        return existingTasks
            .filter {
                $0.supersededAt == nil &&
                    $0.archivedAt == nil &&
                    $0.plannedDayKey == dayKey
            }
            .sorted { $0.order < $1.order }
    }

    private var validTemplateDrafts: [TemplateTaskDraft] {
        templateDrafts.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var isConfirmingTemplateApply: Binding<Bool> {
        Binding(
            get: { pendingTemplate != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTemplate = nil
                }
            }
        )
    }

    private var emptyTitle: String {
        if templates.isEmpty { return "템플릿 없음" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "검색 결과 없음" }
        return "즐겨찾기 템플릿 없음"
    }

    private var emptyDescription: Text {
        if templates.isEmpty { return Text("반복할 작업 묶음을 템플릿으로 저장하면 여기에서 적용할 수 있어요.") }
        if scope == .favorites { return Text("전체보기로 전환하면 모든 템플릿을 볼 수 있어요.") }
        return Text("다른 검색어로 다시 시도하세요.")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("현재 보드 저장") {
                    if currentBoardTasks.isEmpty {
                        ContentUnavailableView("저장할 작업 없음", systemImage: "checklist")
                            .listRowBackground(Color.clear)
                    } else {
                        TextField("템플릿 이름", text: $templateName)

                        ForEach($templateDrafts) { $draft in
                            MobileTemplateDraftEditRow(
                                draft: $draft,
                                onRemove: removeTemplateDraft
                            )
                        }

                        HStack {
                            Button {
                                loadCurrentBoardDrafts()
                            } label: {
                                Label("다시 불러오기", systemImage: "arrow.clockwise")
                            }

                            Spacer()

                            Button {
                                saveCurrentBoardTemplate()
                            } label: {
                                Label("템플릿으로 저장", systemImage: "square.on.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                    validTemplateDrafts.isEmpty
                            )
                        }
                    }
                }

                Section {
                    TextField("템플릿 검색", text: $searchText)
                    Picker("보기", selection: $scope) {
                        ForEach(TemplateListScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(filteredTemplates) { template in
                    let templateItems = TemplateListRules.itemsForTemplate(template, in: items)
                    HStack(spacing: 10) {
                        Button {
                            toggleFavorite(template)
                        } label: {
                            Image(systemName: template.isFavorite ? "star.fill" : "star")
                                .font(.headline)
                                .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(template.isFavorite ? "즐겨찾기 제거" : "즐겨찾기 추가")

                        Button {
                            requestApply(template, items: templateItems)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(template.name)
                                    .font(.headline)
                                Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteTemplate = template
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
                if filteredTemplates.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "square.on.square",
                        description: emptyDescription
                    )
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("템플릿")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                scope = TemplateListRules.preferredScope(for: templates)
                if templateDrafts.isEmpty {
                    loadCurrentBoardDrafts()
                }
            }
            .onChange(of: searchText) {
                message = nil
            }
            .onChange(of: scope) {
                message = nil
            }
            .alert(
                "템플릿을 적용하시겠습니까?",
                isPresented: isConfirmingTemplateApply,
                presenting: pendingTemplate
            ) { template in
                Button("미적용", role: .cancel) {
                    pendingTemplate = nil
                }
                Button("적용") {
                    apply(
                        template,
                        items: TemplateListRules.itemsForTemplate(template, in: items)
                    )
                }
            } message: { template in
                Text("\"\(template.name)\" 템플릿을 \(DayKey.display(selectedDate))에 적용합니다.")
            }
            .alert("템플릿을 삭제할까요?", isPresented: Binding(
                get: { pendingDeleteTemplate != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteTemplate = nil
                    }
                }
            ), presenting: pendingDeleteTemplate) { template in
                Button("취소", role: .cancel) {
                    pendingDeleteTemplate = nil
                }
                Button("삭제", role: .destructive) {
                    deleteTemplate(template)
                }
            } message: { template in
                let count = TemplateListRules.itemsForTemplate(template, in: items).count
                Text("\"\(template.name)\" 템플릿과 하위 작업 \(count)개를 삭제합니다.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func requestApply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        let hasApplicableItem = templateItems.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard hasApplicableItem else {
            message = "템플릿에 적용할 작업이 없어요"
            return
        }

        message = nil
        pendingTemplate = template
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        do {
            let isFavorite = try PersistenceCommandService.perform(in: modelContext) {
                template.isFavorite.toggle()
                template.updatedAt = Date()
                return template.isFavorite
            }
            if !isFavorite && scope == .favorites {
                pendingTemplate = nil
            }
            message = isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요"
        } catch {
            message = "즐겨찾기를 변경하지 못했습니다"
        }
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        let name = template.name
        do {
            _ = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.deleteTemplate(
                    template,
                    items: items,
                    in: modelContext
                )
            }
            pendingDeleteTemplate = nil
            message = "\"\(name)\" 템플릿을 삭제했어요"
        } catch {
            pendingDeleteTemplate = nil
            message = "템플릿을 삭제하지 못했습니다"
        }
    }

    private func loadCurrentBoardDrafts() {
        templateDrafts = currentBoardTasks.enumerated().map { index, task in
            TemplateTaskDraft(
                id: task.id,
                title: task.title,
                note: task.note ?? "",
                priority: task.priority,
                tags: task.tags,
                estimatedMinutes: task.estimatedMinutes,
                order: Double(index + 1) * 100
            )
        }
        message = nil
    }

    private func removeTemplateDraft(_ id: UUID) {
        templateDrafts.removeAll { $0.id == id }
    }

    private func saveCurrentBoardTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !validTemplateDrafts.isEmpty else { return }

        do {
            let template = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.saveTemplate(
                    named: name,
                    from: validTemplateDrafts,
                    in: modelContext
                )
            }
            guard template != nil else {
                message = "템플릿 이름과 작업을 확인해 주세요"
                return
            }
            templateName = ""
            loadCurrentBoardDrafts()
            scope = .all
            message = "\"\(name)\" 템플릿을 저장했어요"
        } catch {
            message = "템플릿을 저장하지 못했습니다"
        }
    }

    private func apply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        pendingTemplate = nil
        let templateName = template.name
        do {
            let createdCount = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.applyTemplate(
                    template,
                    items: templateItems,
                    selectedDate: selectedDate,
                    existingTasks: existingTasks,
                    in: modelContext
                )
            }
            guard createdCount > 0 else {
                message = "추가할 새 작업이 없어요"
                return
            }
            onApplied("\"\(templateName)\" 템플릿으로 \(createdCount)개 작업을 추가했어요")
            dismiss()
        } catch {
            message = "템플릿을 적용하지 못했습니다"
        }
    }
}
#endif
