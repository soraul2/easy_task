#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI

enum MobileEventEditorRoute: Identifiable {
    case add(Date)
    case edit(CalendarEvent)

    var id: String {
        switch self {
        case .add(let date): "add-\(DayKey.key(for: date))"
        case .edit(let event): "edit-\(event.id.uuidString)"
        }
    }
}

private enum MobileEventDurationPreset: Int, CaseIterable, Identifiable {
    case one = 1
    case three = 3
    case five = 5
    case seven = 7

    var id: Int { rawValue }
    var title: String { "\(rawValue)일" }
}

struct MobileEventEditorSheet: View {
    var initialDate: Date
    var event: CalendarEvent?
    var onComplete: ((String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var color: String
    @State private var message: String?
    @State private var showingAddConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var linkedTaskCount = 0

    private var isEditing: Bool {
        event != nil
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedStartDate: Date {
        DayKey.startOfDay(for: min(startDate, endDate))
    }

    private var normalizedEndDate: Date {
        DayKey.startOfDay(for: max(startDate, endDate))
    }

    init(
        initialDate: Date,
        event: CalendarEvent? = nil,
        onComplete: ((String) -> Void)? = nil
    ) {
        self.initialDate = initialDate
        self.event = event
        self.onComplete = onComplete
        _title = State(initialValue: event?.title ?? "")
        _note = State(initialValue: event?.note ?? "")
        _startDate = State(initialValue: event?.startAt ?? initialDate)
        _endDate = State(initialValue: event?.endAt ?? initialDate)
        _color = State(initialValue: event?.color ?? CalendarEventPalette.defaultColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Section("일정") {
                    TextField("큰 일정 또는 작업 맥락", text: $title)
                }
                Section("기간") {
                    MobileEventDateRangeEditor(startDate: $startDate, endDate: $endDate)
                }
                Section("띠 색상") {
                    MobileEventColorSelector(selection: $color)
                }
                Section("메모") {
                    TextField("메모", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            requestEventDeletion()
                        } label: {
                            Label("이벤트 삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "이벤트 편집" : "이벤트 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "저장" : "추가") {
                        if isEditing {
                            if saveEvent() {
                                dismiss()
                            }
                        } else {
                            showingAddConfirmation = true
                        }
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .alert("이벤트를 추가할까요?", isPresented: $showingAddConfirmation) {
                Button("취소", role: .cancel) {}
                Button("추가") {
                    if saveEvent() {
                        dismiss()
                    }
                }
            } message: {
                Text("\"\(trimmedTitle)\" 이벤트를 \(DayKey.display(normalizedStartDate))부터 \(DayKey.display(normalizedEndDate))까지 추가합니다.")
            }
            .alert("이벤트를 삭제할까요?", isPresented: $showingDeleteConfirmation) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                if linkedTaskCount > 0 {
                    Text("연결된 작업 \(linkedTaskCount)개의 이벤트 연결도 함께 해제됩니다.")
                } else {
                    Text("삭제한 이벤트는 되돌릴 수 없습니다.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @discardableResult
    private func saveEvent() -> Bool {
        message = nil
        do {
            let didSave = try PersistenceCommandService.perform(in: modelContext) {
                if let event {
                    return CalendarEventRules.update(
                        event,
                        title: trimmedTitle,
                        startAt: startDate,
                        endAt: endDate,
                        note: note,
                        color: color
                    )
                }
                guard let event = CalendarEventRules.makeEvent(
                    title: trimmedTitle,
                    startAt: startDate,
                    endAt: endDate,
                    note: note,
                    color: color
                ) else {
                    return false
                }
                modelContext.insert(event)
                return true
            }
            guard didSave else {
                message = "이벤트 내용을 확인해 주세요"
                return false
            }

            onComplete?(isEditing ? "이벤트를 저장했어요" : "이벤트를 추가했어요")
            return true
        } catch {
            message = isEditing ? "이벤트를 저장하지 못했어요" : "이벤트를 추가하지 못했어요"
            return false
        }
    }

    private func deleteEvent() {
        guard let event else { return }
        message = nil
        do {
            let detachedCount = try PersistenceCommandService.perform(in: modelContext) {
                let linkedTasks = try BoundedQueryService.tasksLinked(
                    toEventID: event.id,
                    in: modelContext
                )
                let detachedCount = CalendarEventRules.detachTasks(from: event, in: linkedTasks)
                modelContext.delete(event)
                return detachedCount
            }
            if detachedCount > 0 {
                onComplete?("이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
            } else {
                onComplete?("이벤트를 삭제했어요")
            }
            dismiss()
        } catch {
            message = "이벤트를 삭제하지 못했어요"
        }
    }

    private func requestEventDeletion() {
        guard let event else { return }
        do {
            linkedTaskCount = try BoundedQueryService.tasksLinked(
                toEventID: event.id,
                in: modelContext
            ).count
            showingDeleteConfirmation = true
        } catch {
            message = "이벤트 정보를 불러오지 못했어요"
        }
    }
}

private struct MobileEventDateRangeEditor: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var customDurationText = ""

    private var selectedPreset: MobileEventDurationPreset? {
        let normalizedStart = DayKey.startOfDay(for: startDate)
        let normalizedEnd = DayKey.startOfDay(for: endDate)
        let dayCount = (DayKey.calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0) + 1
        return MobileEventDurationPreset(rawValue: dayCount)
    }

    private var customDuration: Int? {
        guard let duration = Int(customDurationText), duration > 0 else { return nil }
        return min(duration, 365)
    }

    var body: some View {
        DatePicker("시작", selection: $startDate, displayedComponents: .date)
            .onChange(of: startDate) {
                if endDate < startDate {
                    endDate = startDate
                }
            }
        DatePicker("종료", selection: $endDate, displayedComponents: .date)
            .onChange(of: endDate) {
                if endDate < startDate {
                    startDate = endDate
                }
            }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MobileEventDurationPreset.allCases) { preset in
                    Button(preset.title) {
                        applyPreset(preset)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(selectedPreset == preset ? AppTheme.event : .secondary)
                }
                HStack(spacing: 6) {
                    TextField("직접", text: $customDurationText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 48)
                        .onChange(of: customDurationText) {
                            customDurationText = sanitizedDurationText(customDurationText)
                        }
                    Text("일")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button("적용") {
                        applyCustomDuration()
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(customDuration == nil)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.input, in: Capsule())
            }
            .padding(.vertical, 2)
        }
    }

    private func applyPreset(_ preset: MobileEventDurationPreset) {
        let normalizedStart = DayKey.startOfDay(for: startDate)
        startDate = normalizedStart
        endDate = DayKey.addingDays(preset.rawValue - 1, to: normalizedStart)
    }

    private func applyCustomDuration() {
        guard let customDuration else { return }
        let normalizedStart = DayKey.startOfDay(for: startDate)
        startDate = normalizedStart
        endDate = DayKey.addingDays(customDuration - 1, to: normalizedStart)
        customDurationText = String(customDuration)
    }

    private func sanitizedDurationText(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count > 3 else { return digits }
        return String(digits.prefix(3))
    }
}

private struct MobileEventColorSelector: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CalendarEventColor.allCases) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .stroke(selection == option.rawValue ? AppTheme.primaryText : AppTheme.border, lineWidth: selection == option.rawValue ? 3 : 1)
                        }
                        .overlay {
                            if selection == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppTheme.eventText)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
