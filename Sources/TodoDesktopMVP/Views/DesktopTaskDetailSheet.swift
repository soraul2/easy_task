import SwiftData
import SwiftUI
import EasyTaskCore

struct TaskDetailSheet: View {
    var task: Task
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var status: TaskStatus
    @State private var plannedDate: Date
    @State private var selectedPriority: TaskPriority?
    @State private var tagsText: String
    @State private var estimatedMinutesText: String
    @State private var persistenceFailureMessage: String?

    init(task: Task) {
        self.task = task
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _status = State(initialValue: TaskStatus(rawValue: task.status) ?? .todo)
        _plannedDate = State(initialValue: task.plannedAt)
        _selectedPriority = State(initialValue: task.priority.flatMap(TaskPriority.init(rawValue:)))
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _estimatedMinutesText = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("작업 상세 편집")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("\(task.plannedDayKey)에 배치된 작업")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                DetailFieldLabel("제목")
                TextField("작업 제목", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(10)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }

                DetailFieldLabel("보드 날짜")
                DatePicker("보드 날짜", selection: $plannedDate, displayedComponents: .date)
                    .labelsHidden()

                if let reminderAt = task.reminderAt {
                    DetailFieldLabel("알림")
                    Label(
                        reminderAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "bell"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }

                DetailFieldLabel("상태")
                Picker("상태", selection: $status) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                DetailFieldLabel("메모")
                TextEditor(text: $note)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }

                DetailFieldLabel("우선순위")
                Picker("우선순위", selection: $selectedPriority) {
                    Text("없음").tag(nil as TaskPriority?)
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority as TaskPriority?)
                    }
                }
                .pickerStyle(.segmented)

                DetailFieldLabel("예상 시간")
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach([15, 30, 60, 120], id: \.self) { minutes in
                            Button(EstimatedTimeFormatter.short(minutes)) {
                                estimatedMinutesText = String(minutes)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button("없음") {
                            estimatedMinutesText = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        TextField("직접 입력", text: $estimatedMinutesText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("분")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(10)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }

                DetailFieldLabel("태그")
                TextField("쉼표로 구분해서 입력", text: $tagsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(10)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
            }

            HStack {
                Spacer()

                Button("취소") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    save()
                } label: {
                    Label("저장", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(AppTheme.panel)
        .persistenceFailureAlert(message: $persistenceFailureMessage)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = parsedTags()
        let estimateInput = parsedEstimatedMinutesInput()
        if let errorMessage = estimateInput.errorMessage {
            persistenceFailureMessage = errorMessage
            return
        }
        let estimatedMinutes = estimateInput.value
        let oldDayKey = task.plannedDayKey
        let oldStatus = TaskStatus(rawValue: task.status) ?? .todo
        let newPlannedAt = DayKey.startOfDay(for: plannedDate)
        let newDayKey = DayKey.key(for: newPlannedAt)

        do {
            try PersistenceCommandService.perform(in: modelContext) {
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
                    TaskRules.applyStatus(status, to: task, completionDayKey: newDayKey)
                }

                if oldDayKey != newDayKey || nextOrder != nil {
                    TaskRules.move(task, to: newPlannedAt, order: nextOrder)
                }

                task.title = trimmedTitle
                task.note = trimmedNote.isEmpty ? nil : trimmedNote
                task.priority = selectedPriority?.rawValue
                task.tags = tags
                task.estimatedMinutes = estimatedMinutes
                task.updatedAt = Date()
            }
            dismiss()
        } catch {
            persistenceFailureMessage = "작업을 저장하지 못했습니다."
        }
    }

    private func parsedEstimatedMinutesInput() -> (value: Int?, errorMessage: String?) {
        let value = estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil) }
        guard let minutes = Int(value), (1...(24 * 60)).contains(minutes) else {
            return (nil, "예상 시간은 1~1440분 사이의 숫자로 입력해 주세요.")
        }
        return (minutes, nil)
    }

    private func parsedTags() -> [String] {
        var seen = Set<String>()
        return tagsText
            .split(separator: ",")
            .compactMap { rawTag in
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, !seen.contains(tag) else { return nil }
                seen.insert(tag)
                return tag
            }
    }
}

struct DetailFieldLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
    }
}

