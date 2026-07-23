import SwiftUI
import PlanBaseCore

struct AddEventSheet: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var color: String
    var onAdd: () -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("이벤트 추가")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)

            TextField("큰 일정 또는 작업 맥락", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }

            EventDateRangeEditor(startDate: $startDate, endDate: $endDate)

            VStack(alignment: .leading, spacing: 8) {
                Text("띠 색상")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                EventColorSelector(selection: $color)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소") {
                    dismiss()
                }
                Button {
                    if let failureMessage = onAdd() {
                        message = failureMessage
                    } else {
                        dismiss()
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(AppTheme.panel)
    }
}

struct EventEditorSheet: View {
    @Bindable var event: CalendarEvent
    var onDelete: (CalendarEvent) -> String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftTitle: String
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date
    @State private var draftColor: String
    @State private var message: String?

    init(
        event: CalendarEvent,
        onDelete: @escaping (CalendarEvent) -> String?
    ) {
        self.event = event
        self.onDelete = onDelete
        _draftTitle = State(initialValue: event.title)
        _draftStartDate = State(initialValue: event.startAt)
        _draftEndDate = State(initialValue: event.endAt)
        _draftColor = State(initialValue: event.color ?? CalendarEventPalette.defaultColor)
    }

    private var canSave: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("이벤트 편집")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)

            TextField("큰 일정 또는 작업 맥락", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }

            EventDateRangeEditor(startDate: $draftStartDate, endDate: $draftEndDate)

            VStack(alignment: .leading, spacing: 8) {
                Text("띠 색상")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                EventColorSelector(selection: $draftColor)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            HStack {
                Button(role: .destructive) {
                    if let failureMessage = onDelete(event) {
                        message = failureMessage
                    } else {
                        dismiss()
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                }

                Spacer()

                Button("취소") {
                    dismiss()
                }

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
        .frame(width: 400)
        .background(AppTheme.panel)
    }

    private func save() {
        do {
            let didUpdate = try PersistenceCommandService.perform(in: modelContext) {
                CalendarEventRules.update(
                    event,
                    title: draftTitle,
                    startAt: draftStartDate,
                    endAt: draftEndDate,
                    note: event.note,
                    color: draftColor
                )
            }
            guard didUpdate else {
                message = "이벤트 정보를 확인해 주세요."
                return
            }
            dismiss()
        } catch {
            message = "이벤트를 저장하지 못했어요."
        }
    }
}

private enum EventDurationPreset: Int, CaseIterable, Identifiable {
    case one = 1
    case three = 3
    case five = 5
    case seven = 7

    var id: Int { rawValue }
    var title: String { "\(rawValue)일" }
}

struct EventDateRangeEditor: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var customDurationText = ""

    private var selectedPreset: EventDurationPreset? {
        let normalizedStart = DayKey.startOfDay(for: startDate)
        let normalizedEnd = DayKey.startOfDay(for: endDate)
        let dayCount = (DayKey.calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0) + 1
        return EventDurationPreset(rawValue: dayCount)
    }

    private var customDuration: Int? {
        guard let duration = Int(customDurationText), duration > 0 else { return nil }
        return min(duration, 365)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                DatePicker("시작", selection: $startDate, displayedComponents: .date)
                    .onChange(of: startDate) {
                        if let selectedPreset {
                            applyPreset(selectedPreset)
                        } else if endDate < startDate {
                            endDate = startDate
                        }
                    }

                DatePicker("종료", selection: $endDate, displayedComponents: .date)
                    .onChange(of: endDate) {
                        if endDate < startDate {
                            startDate = endDate
                        }
                    }
            }

            HStack(spacing: 8) {
                Text("기간")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                ForEach(EventDurationPreset.allCases) { preset in
                    Button(preset.title) {
                        applyPreset(preset)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedPreset == preset ? AppTheme.primaryText : AppTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        selectedPreset == preset ? AppTheme.selectedTab : AppTheme.columnTodo,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }

                HStack(spacing: 6) {
                    TextField("직접", text: $customDurationText)
                        .textFieldStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 42)
                        .onChange(of: customDurationText) {
                            customDurationText = sanitizedDurationText(customDurationText)
                        }
                        .onSubmit(applyCustomDuration)

                    Text("일")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)

                    Button("적용") {
                        applyCustomDuration()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(customDuration == nil ? AppTheme.secondaryText : AppTheme.primaryText)
                    .disabled(customDuration == nil)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.input, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.border, lineWidth: 1)
                }

                Spacer()
            }
        }
    }

    private func applyPreset(_ preset: EventDurationPreset) {
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

struct EventColorSelector: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CalendarEventColor.allCases) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .stroke(selection == option.rawValue ? AppTheme.primaryText : AppTheme.border, lineWidth: selection == option.rawValue ? 3 : 1)
                        }
                        .overlay {
                            if selection == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppTheme.eventText)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
            }
        }
    }
}

