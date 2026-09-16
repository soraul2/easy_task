#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI
import UIKit

private struct PendingMobileTaskDetailCompletion {
    var taskID: UUID
    var title: String
    var reminderAt: Date
}

#if DEBUG
@MainActor
private enum MobileTaskDetailUITestFixture {
    static var didSimulateChecklistLoadFailure = false
}
#endif

struct MobileTaskDetailSheet: View {
    private enum SaveFailure: Error {
        case reminderExpired
    }

    var task: TodoTask
    private let onStartFocus: (UUID) -> Void
    private let initialReminderEnabled: Bool
    private let initialReminderAt: Date?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var title: String
    @State private var note: String
    @State private var status: TaskStatus
    @State private var plannedDate: Date
    @State private var priority: TaskPriority?
    @State private var estimatedMinutesText: String
    @State private var tagsText: String
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var checklistDrafts: [ChecklistItemDraft] = []
    @State private var newChecklistTitle = ""
    @State private var checklistEditMode: EditMode = .inactive
    @State private var isChecklistLoading = false
    @State private var isChecklistLoaded = false
    @State private var checklistLoadError: String?
    @State private var notificationAuthorization: TaskNotificationAuthorizationState = .notDetermined
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false
    @State private var initialDraft: TaskEditorDraftSnapshot
    @State private var startsFocusAfterSaving = false
    @State private var pendingCompletion: PendingMobileTaskDetailCompletion?
    private enum Field: Hashable {
        case title, note, estimate, tags
        case checklist(UUID)
        case newChecklist
    }
    @FocusState private var focusedField: Field?

    init(task: TodoTask, onStartFocus: @escaping (UUID) -> Void = { _ in }) {
        self.task = task
        _initialDraft = State(initialValue: TaskEditorDraftSnapshot(task: task))
        self.onStartFocus = onStartFocus
        initialReminderEnabled = task.reminderAt != nil
        initialReminderAt = TaskReminderRules.normalizedDate(task.reminderAt)
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _priority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _reminderEnabled = State(initialValue: task.reminderAt != nil)
        _reminderDate = State(
            initialValue:
                task.reminderAt ?? Self.defaultReminderDate(for: task.plannedAt)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section("기본") {
                        TextField("제목", text: $title)
                            .focused($focusedField, equals: .title)
                            .accessibilityLabel("제목")
                            .accessibilityIdentifier("task-detail-title")
                        DatePicker("보드 날짜", selection: $plannedDate, displayedComponents: .date)
                        Picker("상태", selection: $status) {
                            ForEach(TaskStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        .planBaseAdaptiveSegmentedPicker()
                    }
                    Section("상세") {
                        TextField("메모", text: $note, axis: .vertical)
                            .focused($focusedField, equals: .note)
                            .accessibilityLabel("메모")
                            .accessibilityIdentifier("task-detail-note")
                        Picker("우선순위", selection: $priority) {
                            Text("없음").tag(nil as TaskPriority?)
                            ForEach(TaskPriority.allCases) { priority in
                                Text(priority.title).tag(priority as TaskPriority?)
                            }
                        }
                        TextField("예상 시간(분)", text: $estimatedMinutesText)
                            .focused($focusedField, equals: .estimate)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("task-detail-estimate")
                        TextField("태그(쉼표로 구분)", text: $tagsText)
                            .focused($focusedField, equals: .tags)
                    }
                    Section {
                        if isChecklistLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("체크리스트 불러오는 중")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                        } else if let checklistLoadError {
                            VStack(alignment: .leading, spacing: 12) {
                                Label {
                                    Text(checklistLoadError)
                                        .foregroundStyle(AppTheme.primaryText)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                        .accessibilityHidden(true)
                                }
                                .font(.footnote.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityValue("오류")
                                .accessibilityIdentifier("task-checklist-load-error")

                                Button(action: loadChecklistDrafts) {
                                    Label("다시 시도", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(PlanBaseButtonStyle(.primary))
                                .accessibilityLabel("체크리스트 다시 불러오기")
                            }
                            .id("task-checklist-load-error")
                        } else {
                            ForEach($checklistDrafts) { $draft in
                                HStack(spacing: 8) {
                                    Button {
                                        draft.isCompleted.toggle()
                                    } label: {
                                        Image(
                                            systemName: draft.isCompleted
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .font(.title3)
                                        .foregroundStyle(
                                            draft.isCompleted
                                                ? AppTheme.done
                                                : AppTheme.secondaryText
                                        )
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("\(checklistAccessibilityTitle(draft.title)) 완료 상태")
                                    .accessibilityValue(draft.isCompleted ? "완료" : "미완료")

                                    TextField("체크리스트 항목", text: $draft.title)
                                        .focused($focusedField, equals: .checklist(draft.id))
                                        .strikethrough(draft.isCompleted)
                                        .foregroundStyle(draft.isCompleted ? .secondary : .primary)
                                        .submitLabel(.done)
                                        .frame(minHeight: 44)
                                        .accessibilityLabel("체크리스트 항목 제목")
                                        .accessibilityValue(draft.title)
                                }
                            }
                            .onDelete(perform: deleteChecklistDrafts)
                            .onMove(perform: moveChecklistDrafts)

                            HStack(spacing: 8) {
                                TextField("새 체크리스트 항목", text: $newChecklistTitle)
                                    .focused($focusedField, equals: .newChecklist)
                                    .submitLabel(.done)
                                    .onSubmit(addChecklistDraft)
                                    .frame(minHeight: 44)

                                Button(action: addChecklistDraft) {
                                    Image(systemName: "plus")
                                        .font(.headline)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .disabled(
                                    newChecklistTitle
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty || checklistEditMode.isEditing
                                )
                                .accessibilityLabel("체크리스트 항목 추가")
                            }
                        }
                    } header: {
                        HStack {
                            Text("체크리스트")
                            Spacer()
                            if isChecklistLoaded && (checklistDrafts.count > 1 || checklistEditMode.isEditing) {
                                Button(checklistEditMode.isEditing ? "완료" : "순서 변경") {
                                    checklistEditMode =
                                        checklistEditMode.isEditing
                                        ? .inactive
                                        : .active
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel(
                                    checklistEditMode.isEditing
                                        ? "체크리스트 순서 편집 완료"
                                        : "체크리스트 순서 편집")
                            }
                        }
                        .textCase(nil)
                    }
                    Section("알림") {
                        Toggle("작업 알림", isOn: $reminderEnabled)
                            .disabled(status == .done)

                        if status == .done {
                            if reminderEnabled {
                                Label(
                                    "설정했던 알림 · "
                                        + reminderDate.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        ),
                                    systemImage: "bell.slash.fill"
                                )
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                Text("완료 상태에서는 알림이 울리지 않으며 설정 기록만 유지됩니다.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(
                                    "완료한 작업에는 활성 알림이 없습니다",
                                    systemImage: "checkmark.circle"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        } else if reminderEnabled {
                            HStack(spacing: 8) {
                                reminderPresetButton("10분 후", minutes: 10)
                                reminderPresetButton("30분 후", minutes: 30)
                                reminderPresetButton("1시간 후", minutes: 60)
                            }

                            DatePicker(
                                "알림 시각",
                                selection: $reminderDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )

                            switch notificationAuthorization {
                            case .authorized:
                                EmptyView()
                            case .notDetermined:
                                Label(
                                    "저장 후 이 기기의 알림 권한을 요청합니다.",
                                    systemImage: "bell.badge"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            case .denied:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("알림 시각은 저장되지만 이 기기에서는 울리지 않습니다.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text("바로 열리지 않으면 설정 > 앱 > PlanBase > 알림에서 허용해 주세요.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button(action: openNotificationSettings) {
                                        Label("알림 설정 열기", systemImage: "gear")
                                    }
                                }
                            }
                        }
                    }
                    if status != .done {
                        Section("집중") {
                            Button {
                                startsFocusAfterSaving = true
                                requestSave()
                            } label: {
                                Label(hasUnsavedChanges ? "저장 후 집중 시작" : "이 작업으로 집중 시작", systemImage: "timer")
                            }
                            .disabled(!canSave)
                            .accessibilityIdentifier("task-detail-start-focus")
                        }
                    }
                    if let saveError {
                        Section {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .environment(\.editMode, $checklistEditMode)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("작업 상세")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("키보드 닫기") { focusedField = nil }
                            .accessibilityIdentifier("task-detail-keyboard-dismiss")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소", action: requestDismiss)
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "저장 중…" : "저장") {
                            startsFocusAfterSaving = false
                            requestSave()
                        }
                        .disabled(!canSave)
                    }
                }
                .onChange(of: checklistLoadError) { _, newValue in
                    guard newValue != nil else { return }
                    Swift.Task { @MainActor in
                        await Swift.Task.yield()
                        withAnimation {
                            scrollProxy.scrollTo("task-checklist-load-error", anchor: .center)
                        }
                    }
                }
            }
        }
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            isSaving: isSaving,
            onDiscard: { dismiss() }
        )
        .alert(
            "예정된 알림이 있습니다",
            isPresented: Binding(
                get: { pendingCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCompletion = nil
                    }
                }
            ),
            presenting: pendingCompletion
        ) { pending in
            Button("완료하기", role: .destructive) {
                pendingCompletion = nil
                save(confirmedCompletion: true, taskID: pending.taskID)
            }
            Button("취소", role: .cancel) {}
        } message: { pending in
            Text(
                "\(pending.title) 작업을 완료하면 " + "\(pending.reminderAt.formatted(date: .abbreviated, time: .shortened)) "
                    + "알림이 중지됩니다. 알림 설정 기록은 계속 유지됩니다."
            )
        }
        .task {
            loadChecklistDrafts()
            notificationAuthorization = await TaskNotificationScheduler.shared
                .authorizationState()
        }
        .onChange(of: reminderEnabled) { _, isEnabled in
            guard isEnabled, reminderDate <= Date() else { return }
            reminderDate = Self.defaultReminderDate(for: plannedDate)
        }
        .onChange(of: scenePhase) { _, nextPhase in
            guard nextPhase == .active else { return }
            refreshNotificationAuthorization()
        }
    }

    private var currentDraft: TaskEditorDraftSnapshot {
        var draft = initialDraft
        draft.title = title
        draft.note = note
        draft.status = status
        draft.plannedDate = plannedDate
        draft.priority = priority
        draft.estimatedMinutesText = estimatedMinutesText
        draft.tagsText = tagsText
        draft.reminderAt = reminderEnabled ? TaskReminderRules.normalizedDate(reminderDate) : nil
        draft.checklist = checklistDrafts
        draft.pendingChecklistTitle = newChecklistTitle
        return draft
    }

    private var hasUnsavedChanges: Bool { currentDraft != initialDraft }

    private var canSave: Bool {
        !isSaving && isChecklistLoaded && !isChecklistLoading && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestDismiss() {
        guard !isSaving else { return }
        focusedField = nil
        if hasUnsavedChanges { showsDiscardConfirmation = true } else { dismiss() }
    }

    private func requestSave() {
        guard !isSaving, isChecklistLoaded, !isChecklistLoading else { return }
        let currentStatus = TaskStatus(rawValue: task.status) ?? .todo
        let effectiveReminderAt =
            reminderEnabled
            ? TaskReminderRules.normalizedDate(reminderDate)
            : nil
        if currentStatus != .done,
            status == .done,
            let reminderAt = effectiveReminderAt,
            reminderAt > Date()
        {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingCompletion = PendingMobileTaskDetailCompletion(
                taskID: task.id,
                title: trimmedTitle.isEmpty ? "선택한" : trimmedTitle,
                reminderAt: reminderAt
            )
            return
        }

        save(confirmedCompletion: false)
    }

    private func save(confirmedCompletion: Bool, taskID: UUID? = nil) {
        guard !isSaving, isChecklistLoaded, !isChecklistLoading else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

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
        let reminderAt =
            reminderEnabled
            ? TaskReminderRules.normalizedDate(reminderDate)
            : nil
        let reminderWasEdited = TaskReminderRules.reminderWasEdited(
            initialEnabled: initialReminderEnabled,
            initialDate: initialReminderAt,
            currentEnabled: reminderEnabled,
            currentDate: reminderAt
        )
        if status != .done,
            reminderEnabled,
            reminderWasEdited,
            reminderAt.map({ $0 <= Date() }) != false
        {
            saveError = "알림 시각은 현재보다 이후로 선택해 주세요"
            return
        }

        // Saving includes the last typed checklist item even when + was not pressed.
        if !newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
            checklistDrafts.append(
                ChecklistItemDraft(
                    title: newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    order: nextOrder
                ))
            newChecklistTitle = ""
        }
        let checklistDrafts = checklistDrafts
        focusedField = nil
        saveError = nil
        isSaving = true
        do {
            guard
                let currentTask = try modelContext.fetch(
                    BoundedQueryService.taskDescriptor(id: taskID ?? task.id)
                ).first
            else {
                isSaving = false
                saveError = "작업이 변경되어 저장하지 못했습니다"
                return
            }
            let oldDayKey = currentTask.plannedDayKey
            let oldStatus = TaskStatus(rawValue: currentTask.status) ?? .todo
            if oldStatus != .done,
                status == .done,
                !confirmedCompletion,
                let reminderAt,
                reminderAt > Date()
            {
                isSaving = false
                pendingCompletion = PendingMobileTaskDetailCompletion(
                    taskID: currentTask.id,
                    title: trimmedTitle,
                    reminderAt: reminderAt
                )
                return
            }

            try PersistenceCommandService.perform(in: modelContext) {
                let now = Date()
                if status != .done,
                    reminderEnabled,
                    reminderWasEdited,
                    reminderAt.map({ $0 > now }) != true
                {
                    throw SaveFailure.reminderExpired
                }
                let nextOrder: Double?
                if oldDayKey != newDayKey || oldStatus != status {
                    nextOrder = try BoundedQueryService.nextOrder(
                        in: modelContext,
                        dayKey: newDayKey,
                        status: status
                    )
                } else {
                    nextOrder = nil
                }

                if oldStatus != status {
                    try TaskLifecycleService.applyStatus(
                        status,
                        to: currentTask,
                        in: modelContext,
                        now: now
                    )
                }

                if oldDayKey != newDayKey || nextOrder != nil {
                    TaskRules.move(currentTask, to: newPlannedAt, order: nextOrder, now: now)
                }

                _ = TaskRules.setReminder(reminderAt, on: currentTask, now: now)
                currentTask.title = trimmedTitle
                currentTask.note = trimmedNote.isEmpty ? nil : trimmedNote
                currentTask.priority = priority?.rawValue
                currentTask.estimatedMinutes = estimatedMinutes
                currentTask.tags = tags
                currentTask.updatedAt = now

                let existingChecklistItems = try TaskChecklistService.items(
                    for: currentTask.id,
                    in: modelContext
                )
                TaskChecklistService.replaceItems(
                    for: currentTask.id,
                    drafts: checklistDrafts,
                    existingItems: existingChecklistItems,
                    in: modelContext,
                    now: now
                )
            }
            if status == .done {
                TaskNotificationScheduler.shared.cancelNotifications(for: [currentTask.id])
            }
            finishSaving(
                reminderRequested: status != .done && reminderAt.map { $0 > Date() } == true
            )
        } catch SaveFailure.reminderExpired {
            isSaving = false
            saveError = "알림 시각은 현재보다 이후로 선택해 주세요"
        } catch {
            isSaving = false
            saveError = "작업을 저장하지 못했습니다"
        }
    }

    private func reminderPresetButton(_ title: String, minutes: Int) -> some View {
        Button(title) {
            reminderDate =
                TaskReminderRules.normalizedDate(
                    Date().addingTimeInterval(Double(minutes * 60))
                ) ?? Date().addingTimeInterval(Double(minutes * 60))
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private func loadChecklistDrafts() {
        guard !isChecklistLoading else { return }
        isChecklistLoading = true
        isChecklistLoaded = false
        checklistLoadError = nil

        do {
            #if DEBUG
            if !MobileTaskDetailUITestFixture.didSimulateChecklistLoadFailure,
                PlanBaseLaunchEnvironment.isUITesting,
                ProcessInfo.processInfo.arguments.contains("--ui-testing-checklist-load-failure-once")
            {
                MobileTaskDetailUITestFixture.didSimulateChecklistLoadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            let items = try TaskChecklistService.items(for: task.id, in: modelContext)
            checklistDrafts = TaskChecklistService.drafts(from: items)
            initialDraft.checklist = checklistDrafts
            isChecklistLoaded = true
        } catch {
            checklistLoadError = "체크리스트를 불러오지 못했습니다"
        }

        isChecklistLoading = false
    }

    private func addChecklistDraft() {
        let trimmedTitle =
            newChecklistTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChecklistLoaded,
            !checklistEditMode.isEditing,
            !trimmedTitle.isEmpty
        else { return }

        let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
        checklistDrafts.append(
            ChecklistItemDraft(
                title: trimmedTitle,
                order: nextOrder
            ))
        newChecklistTitle = ""
        focusedField = .newChecklist
    }

    private func deleteChecklistDrafts(at offsets: IndexSet) {
        checklistDrafts.remove(atOffsets: offsets)
        normalizeChecklistDraftOrder()
    }

    private func moveChecklistDrafts(from source: IndexSet, to destination: Int) {
        checklistDrafts.move(fromOffsets: source, toOffset: destination)
        normalizeChecklistDraftOrder()
    }

    private func normalizeChecklistDraftOrder() {
        for index in checklistDrafts.indices {
            checklistDrafts[index].order = Double(index + 1) * 100
        }
    }

    private func checklistAccessibilityTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "제목 없는 체크리스트 항목" : trimmedTitle
    }

    private func finishSaving(reminderRequested: Bool) {
        Swift.Task { @MainActor in
            if reminderRequested {
                let currentAuthorization = await TaskNotificationScheduler.shared
                    .authorizationState()
                if currentAuthorization == .notDetermined {
                    notificationAuthorization = await TaskNotificationScheduler.shared
                        .requestAuthorization()
                } else {
                    notificationAuthorization = currentAuthorization
                }
            }
            await TaskNotificationScheduler.shared.reconcile(context: modelContext)
            isSaving = false
            let shouldStartFocus = startsFocusAfterSaving && status != .done
            dismiss()
            if shouldStartFocus {
                DispatchQueue.main.async { onStartFocus(task.id) }
            }
        }
    }

    private func refreshNotificationAuthorization() {
        Swift.Task { @MainActor in
            notificationAuthorization = await TaskNotificationScheduler.shared
                .authorizationState()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private static func defaultReminderDate(for plannedDate: Date) -> Date {
        let now = Date()
        let plannedDayKey = DayKey.key(for: plannedDate)
        if plannedDayKey > DayKey.today,
            let morning = Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: plannedDate
            )
        {
            return morning
        }
        return TaskReminderRules.normalizedDate(
            now.addingTimeInterval(60 * 60)
        ) ?? now.addingTimeInterval(60 * 60)
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
        return
            tagsText
            .split(separator: ",")
            .compactMap { rawTag in
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
                return tag
            }
    }
}

#endif
