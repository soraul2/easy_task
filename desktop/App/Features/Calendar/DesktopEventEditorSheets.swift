import AppKit
import SwiftUI
import PlanBaseCore

struct AddEventSheet: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var color: String
    @Binding var note: String
    var isDuplicate = false
    var excludingEventID: UUID? = nil
    var onAdd: () -> String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var recommendationSession: CalendarEventRecommendationSession?
    @State private var selectedRecommendationIndex: Int?
    @State private var recommendationFeedback: String?

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(isDuplicate ? "이벤트 복제" : "이벤트 추가")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Label(DayKey.display(startDate), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.input, in: Capsule())
                    .accessibilityLabel("시작일 \(DayKey.display(startDate))")
            }

            if isDuplicate {
                Label("복제한 일정", systemImage: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHint("원본과 연결되지 않는 새 일정입니다")
            }

            DesktopEventTitleEditor(
                title: $title,
                recommendations: recommendationSession?.recommendations ?? [],
                selectedIndex: $selectedRecommendationIndex,
                feedback: recommendationFeedback,
                onSelect: applyRecommendation,
                onDismiss: {
                    recommendationSession?.dismissRecommendations()
                    selectedRecommendationIndex = nil
                }
            )

            EventDateRangeEditor(startDate: $startDate, endDate: $endDate)

            VStack(alignment: .leading, spacing: 8) {
                Text("일정 색상")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                EventColorSelector(selection: $color)
            }

            EventNoteEditor(text: $note)

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
                .keyboardShortcut(.cancelAction)
                Button {
                    if let failureMessage = onAdd() {
                        message = failureMessage
                    } else {
                        dismiss()
                    }
                } label: {
                    Label(
                        isDuplicate ? "복제 추가" : "추가",
                        systemImage: isDuplicate ? "doc.on.doc" : "plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(AppTheme.panel)
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .task {
            guard recommendationSession == nil else { return }
            let session = CalendarEventRecommendationSession(context: modelContext)
            recommendationSession = session
            session.update(
                title: title,
                excludingEventID: excludingEventID
            )
        }
        .onChange(of: title) {
            recommendationFeedback = nil
            selectedRecommendationIndex = nil
            recommendationSession?.update(
                title: title,
                excludingEventID: excludingEventID
            )
        }
    }

    private func applyRecommendation(
        _ recommendation: CalendarEventRecommendation
    ) {
        let applied = CalendarEventReuseRules.applying(
            recommendation,
            to: CalendarEventReuseDraft(
                title: title,
                startAt: startDate,
                endAt: endDate,
                note: note,
                color: color,
                sourceEventID: excludingEventID
            )
        )
        startDate = applied.startAt
        endDate = applied.endAt
        note = applied.note ?? ""
        color = applied.color ?? CalendarEventPalette.defaultColor
        recommendationFeedback = "이전 일정의 기간·색상·메모를 적용했어요"
        selectedRecommendationIndex = nil
        recommendationSession?.dismissRecommendations()
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
    @State private var draftNote: String
    @State private var message: String?
    @State private var recommendationSession: CalendarEventRecommendationSession?
    @State private var selectedRecommendationIndex: Int?
    @State private var recommendationFeedback: String?

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
        _draftNote = State(initialValue: event.note ?? "")
    }

    private var canSave: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("이벤트 편집")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Label(DayKey.display(draftStartDate), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.input, in: Capsule())
                    .accessibilityLabel("시작일 \(DayKey.display(draftStartDate))")
            }

            DesktopEventTitleEditor(
                title: $draftTitle,
                recommendations: recommendationSession?.recommendations ?? [],
                selectedIndex: $selectedRecommendationIndex,
                feedback: recommendationFeedback,
                onSelect: applyRecommendation,
                onDismiss: {
                    recommendationSession?.dismissRecommendations()
                    selectedRecommendationIndex = nil
                }
            )

            EventDateRangeEditor(startDate: $draftStartDate, endDate: $draftEndDate)

            VStack(alignment: .leading, spacing: 8) {
                Text("일정 색상")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                EventColorSelector(selection: $draftColor)
            }

            EventNoteEditor(text: $draftNote)

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
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    Label("저장", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(AppTheme.panel)
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .task {
            guard recommendationSession == nil else { return }
            let session = CalendarEventRecommendationSession(context: modelContext)
            recommendationSession = session
            session.update(
                title: draftTitle,
                excludingEventID: event.id
            )
        }
        .onChange(of: draftTitle) {
            recommendationFeedback = nil
            selectedRecommendationIndex = nil
            recommendationSession?.update(
                title: draftTitle,
                excludingEventID: event.id
            )
        }
    }

    private func save() {
        do {
            let didUpdate = try PersistenceCommandService.perform(in: modelContext) {
                CalendarEventRules.update(
                    event,
                    title: draftTitle,
                    startAt: draftStartDate,
                    endAt: draftEndDate,
                    note: draftNote,
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

    private func applyRecommendation(
        _ recommendation: CalendarEventRecommendation
    ) {
        let applied = CalendarEventReuseRules.applying(
            recommendation,
            to: CalendarEventReuseDraft(
                title: draftTitle,
                startAt: draftStartDate,
                endAt: draftEndDate,
                note: draftNote,
                color: draftColor,
                sourceEventID: event.id
            )
        )
        draftStartDate = applied.startAt
        draftEndDate = applied.endAt
        draftNote = applied.note ?? ""
        draftColor = applied.color ?? CalendarEventPalette.defaultColor
        recommendationFeedback = "이전 일정의 기간·색상·메모를 적용했어요"
        selectedRecommendationIndex = nil
        recommendationSession?.dismissRecommendations()
    }
}

private struct DesktopEventTitleEditor: View {
    @Binding var title: String
    var recommendations: [CalendarEventRecommendation]
    @Binding var selectedIndex: Int?
    var feedback: String?
    var onSelect: (CalendarEventRecommendation) -> Void
    var onDismiss: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("이벤트 제목", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .focused($isTitleFocused)
                .background {
                    DesktopEventTitleKeyMonitor(
                        isEnabled: isTitleFocused,
                        onMove: moveSelection,
                        onSubmit: selectCurrentRecommendation,
                        onCancel: {
                            guard !recommendations.isEmpty else { return false }
                            onDismiss()
                            return true
                        }
                    )
                    .frame(width: 0, height: 0)
                }

            if !recommendations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(
                        Array(recommendations.enumerated()),
                        id: \.element.id
                    ) { index, recommendation in
                        if index > 0 {
                            Divider()
                        }
                        Button {
                            selectedIndex = index
                            onSelect(recommendation)
                        } label: {
                            Text(recommendation.summary)
                                .font(.caption)
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    selectedIndex == index
                                        ? AppTheme.selectedTab
                                        : Color.clear
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "최근 일정 적용. \(recommendation.summary)"
                        )
                        .accessibilityHint(
                            "현재 시작일은 유지하고 기간, 색상, 메모를 적용합니다"
                        )
                    }
                }
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .padding(.top, 6)
            }

            if let feedback {
                Text(feedback)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 6)
                    .accessibilityLabel(feedback)
            }
        }
        .onChange(of: recommendations) {
            guard let selectedIndex else { return }
            if recommendations.isEmpty {
                self.selectedIndex = nil
            } else if selectedIndex >= recommendations.count {
                self.selectedIndex = recommendations.count - 1
            }
        }
    }

    private func moveSelection(by offset: Int) -> Bool {
        guard !recommendations.isEmpty else { return false }
        if let selectedIndex {
            self.selectedIndex = min(
                max(selectedIndex + offset, 0),
                recommendations.count - 1
            )
        } else {
            selectedIndex = offset > 0 ? 0 : recommendations.count - 1
        }
        return true
    }

    private func selectCurrentRecommendation() -> Bool {
        guard let selectedIndex,
              recommendations.indices.contains(selectedIndex) else {
            return false
        }
        onSelect(recommendations[selectedIndex])
        return true
    }
}

private struct DesktopEventTitleKeyMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onMove: (Int) -> Bool
    var onSubmit: () -> Bool
    var onCancel: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.startMonitoring()
        return NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(
        _ view: NSView,
        coordinator: Coordinator
    ) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        var parent: DesktopEventTitleKeyMonitor
        private var keyMonitor: Any?

        init(parent: DesktopEventTitleKeyMonitor) {
            self.parent = parent
        }

        func startMonitoring() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self, self.parent.isEnabled else {
                    return event
                }

                let handled: Bool
                switch event.keyCode {
                case 125:
                    handled = self.parent.onMove(1)
                case 126:
                    handled = self.parent.onMove(-1)
                case 36, 76:
                    handled = self.parent.onSubmit()
                case 53:
                    handled = self.parent.onCancel()
                default:
                    handled = false
                }
                return handled ? nil : event
            }
        }

        func stopMonitoring() {
            guard let keyMonitor else { return }
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private struct EventNoteEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("메모")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 84)
                .padding(8)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .accessibilityLabel("이벤트 메모")
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
