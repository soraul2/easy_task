#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI

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
                    completionDayKey: selectedDayKey,
                    onEdit: { presentedSheet = .task($0) },
                    onDelete: deleteTask,
                    onStatusChange: showStatusNotice
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
                ToolbarItem(placement: .topBarTrailing) {
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
                }
            }
        }
    }

    private func addQuickTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = TodoTask(
            title: title,
            status: .todo,
            plannedAt: selectedDate,
            order: BoardQueryRules.nextOrder(in: tasks, dayKey: selectedDayKey, status: .todo)
        )
        modelContext.insert(task)
        quickTitle = ""
        selectedStatus = .todo
    }

    private func deleteTask(_ task: TodoTask) {
        do {
            try TaskRules.delete(task, from: modelContext)
        } catch {
            showBoardNotice("작업을 삭제하지 못했습니다")
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
    var completionDayKey: String
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
                        completionDayKey: completionDayKey,
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
    var completionDayKey: String
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
                withAnimation(.snappy) {
                    TaskRules.applyStatus(nextStatus, to: task, completionDayKey: completionDayKey)
                }
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
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TodoTask]
    @State private var title: String
    @State private var note: String
    @State private var status: TaskStatus
    @State private var plannedDate: Date
    @State private var priority: TaskPriority?
    @State private var estimatedMinutesText: String

    init(task: TodoTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _priority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
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
                }
            }
            .navigationTitle("작업 상세")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                        dismiss()
                    }
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

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMinutes = estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        task.title = trimmedTitle
        task.note = trimmedNote.isEmpty ? nil : trimmedNote
        task.priority = priority?.rawValue
        task.estimatedMinutes = trimmedMinutes.isEmpty ? nil : Int(trimmedMinutes)
        task.updatedAt = Date()
    }
}

private struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var targetDate: Date
    var onApplied: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var movedTaskIDs: Set<UUID> = []
    @State private var message: String?

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
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
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
        let count = remainingTasks.count
        TaskRules.completeAll(remainingTasks, completionDayKey: DayKey.key(for: targetDate))
        onApplied("\(count)개 이월 작업을 완료 처리했어요")
        dismiss()
    }

    private func moveAllToTargetDate() {
        let count = remainingTasks.count
        for task in remainingTasks {
            move(task)
        }
        onApplied("\(count)개 작업을 \(DayKey.display(targetDate))로 이월했어요")
        dismiss()
    }

    private func moveToTargetDate(_ task: TodoTask) {
        move(task)
        movedTaskIDs.insert(task.id)
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notice = title.isEmpty ? "작업을 \(DayKey.display(targetDate))로 이월했어요" : "\(title) · \(DayKey.display(targetDate))로 이월했어요"
        message = notice
        onApplied(notice)
    }

    private func move(_ task: TodoTask) {
        TaskRules.move(task, to: targetDate)
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

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
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
                    Button {
                        requestApply(template, items: templateItems)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(template.name)
                                    .font(.headline)
                                if template.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

    private func apply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        pendingTemplate = nil
        let createdCount = TemplateService.applyTemplate(
            template,
            items: templateItems,
            selectedDate: selectedDate,
            existingTasks: existingTasks,
            in: modelContext
        )
        guard createdCount > 0 else {
            message = "추가할 새 작업이 없어요"
            return
        }
        onApplied("\"\(template.name)\" 템플릿으로 \(createdCount)개 작업을 추가했어요")
        dismiss()
    }
}
#endif
