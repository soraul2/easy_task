#if os(iOS)
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct MobileTaskDetailSheet: View {
    private enum SaveFailure: Error {
        case reminderExpired
    }

    var task: TodoTask
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
    @FocusState private var isNewChecklistTitleFocused: Bool

    init(task: TodoTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _priority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _reminderEnabled = State(initialValue: task.reminderAt != nil)
        _reminderDate = State(initialValue:
            task.reminderAt ?? Self.defaultReminderDate(for: task.plannedAt)
        )
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
                Section {
                    if isChecklistLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("체크리스트 불러오는 중")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    } else if let checklistLoadError {
                        HStack(spacing: 10) {
                            Label(checklistLoadError, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: loadChecklistDrafts) {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("체크리스트 다시 불러오기")
                        }
                    } else {
                        ForEach($checklistDrafts) { $draft in
                            HStack(spacing: 8) {
                                Button {
                                    draft.isCompleted.toggle()
                                } label: {
                                    Image(systemName: draft.isCompleted
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .font(.title3)
                                        .foregroundStyle(draft.isCompleted
                                            ? AppTheme.done
                                            : AppTheme.secondaryText)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(checklistAccessibilityTitle(draft.title)) 완료 상태")
                                .accessibilityValue(draft.isCompleted ? "완료" : "미완료")

                                TextField("체크리스트 항목", text: $draft.title)
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
                                .focused($isNewChecklistTitleFocused)
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
                        if isChecklistLoaded &&
                            (checklistDrafts.count > 1 || checklistEditMode.isEditing) {
                            EditButton()
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel(checklistEditMode.isEditing
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
                        Label("완료한 작업에는 알림을 설정할 수 없습니다", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                                Button(action: openNotificationSettings) {
                                    Label("설정에서 알림 허용", systemImage: "gear")
                                }
                            }
                        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(
                            isSaving ||
                            !isChecklistLoaded ||
                            isChecklistLoading ||
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
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
        .onChange(of: status) { _, nextStatus in
            if nextStatus == .done {
                reminderEnabled = false
            }
        }
        .onChange(of: scenePhase) { _, nextPhase in
            guard nextPhase == .active else { return }
            refreshNotificationAuthorization()
        }
    }

    private func save() {
        guard !isSaving, isChecklistLoaded, !isChecklistLoading else { return }
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
        let reminderAt = reminderEnabled
            ? TaskReminderRules.normalizedDate(reminderDate)
            : nil
        let checklistDrafts = checklistDrafts
        if status != .done,
           reminderEnabled,
           reminderAt.map({ $0 <= Date() }) != false {
            saveError = "알림 시각은 현재보다 이후로 선택해 주세요"
            return
        }

        saveError = nil
        isSaving = true
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let now = Date()
                if status != .done,
                   reminderEnabled,
                   reminderAt.map({ $0 > now }) != true {
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
                    TaskRules.applyStatus(
                        status,
                        to: task,
                        now: now,
                        completionDayKey: newDayKey
                    )
                }

                if oldDayKey != newDayKey || nextOrder != nil {
                    TaskRules.move(task, to: newPlannedAt, order: nextOrder, now: now)
                }

                _ = TaskRules.setReminder(reminderAt, on: task, now: now)
                task.title = trimmedTitle
                task.note = trimmedNote.isEmpty ? nil : trimmedNote
                task.priority = priority?.rawValue
                task.estimatedMinutes = estimatedMinutes
                task.tags = tags
                task.updatedAt = now

                let existingChecklistItems = try TaskChecklistService.items(
                    for: task.id,
                    in: modelContext
                )
                TaskChecklistService.replaceItems(
                    for: task.id,
                    drafts: checklistDrafts,
                    existingItems: existingChecklistItems,
                    in: modelContext,
                    now: now
                )
            }
            finishSaving(reminderRequested: status != .done && reminderAt != nil)
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
            reminderDate = TaskReminderRules.normalizedDate(
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
            let items = try TaskChecklistService.items(for: task.id, in: modelContext)
            checklistDrafts = TaskChecklistService.drafts(from: items)
            isChecklistLoaded = true
        } catch {
            checklistLoadError = "체크리스트를 불러오지 못했습니다"
        }

        isChecklistLoading = false
    }

    private func addChecklistDraft() {
        let trimmedTitle = newChecklistTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChecklistLoaded,
              !checklistEditMode.isEditing,
              !trimmedTitle.isEmpty else { return }

        let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
        checklistDrafts.append(ChecklistItemDraft(
            title: trimmedTitle,
            order: nextOrder
        ))
        newChecklistTitle = ""
        isNewChecklistTitleFocused = true
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
            dismiss()
        }
    }

    private func refreshNotificationAuthorization() {
        Swift.Task { @MainActor in
            notificationAuthorization = await TaskNotificationScheduler.shared
                .authorizationState()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
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
           ) {
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
        return tagsText
            .split(separator: ",")
            .compactMap { rawTag in
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
                return tag
            }
    }
}

#endif
