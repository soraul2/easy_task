import AppKit
import SwiftUI
import PlanBaseCore

private struct DesktopEventSaveFailureView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(message)
                    .foregroundStyle(AppTheme.primaryText)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .combine)
            .accessibilityValue("오류")

            Text("입력한 내용은 이 화면에 그대로 남아 있어요.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            Button(action: retry) {
                Label("다시 시도", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PlanBaseButtonStyle(.primary))
            .accessibilityLabel("일정 저장 다시 시도")
        }
    }
}

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
    @State private var initialDraft: CalendarEventReuseDraft?
    @State private var showsDiscardConfirmation = false
    @State private var recommendationSession: CalendarEventRecommendationSession?

    private var currentDraft: CalendarEventReuseDraft {
        CalendarEventReuseDraft(title: title, startAt: startDate, endAt: endDate, note: note, color: color)
    }

    private var hasUnsavedChanges: Bool {
        initialDraft.map { $0 != currentDraft } ?? false
    }

    private func requestDismiss() {
        if hasUnsavedChanges { showsDiscardConfirmation = true }
        else { dismiss() }
    }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text(isDuplicate ? "일정 복제" : "일정 추가")
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
                            title: recommendationTitleBinding,
                            session: recommendationSession,
                            onSelect: applyRecommendation,
                            onReplaceNote: {
                                if let draft = recommendationSession?.replacePreservedNote(in: currentDraft) { setDraft(draft) }
                            },
                            onUndo: {
                                if let draft = recommendationSession?.undo(in: currentDraft) { setDraft(draft) }
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
                            DesktopEventSaveFailureView(message: message, retry: attemptAdd)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .onChange(of: recommendationSession?.selectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: recommendationSession?.state) { _, state in
                    if state == .applied { proxy.scrollTo("event-editor-title", anchor: .top) }
                }
            }
            .frame(maxHeight: 560)

            HStack {
                Spacer()
                Button("취소", action: requestDismiss)
                .keyboardShortcut(.cancelAction)
                Button(action: attemptAdd) {
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
        .onAppear { if initialDraft == nil { initialDraft = currentDraft } }
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            onDiscard: { dismiss() }
        )
        .task {
            guard recommendationSession == nil else { return }
            let session = CalendarEventRecommendationSession(context: modelContext)
            recommendationSession = session
            session.update(
                title: title,
                excludingEventID: excludingEventID
            )
        }
        .onChange(of: currentDraft) {
            recommendationSession?.invalidateApplication(ifEdited: currentDraft)
        }
    }

    private var recommendationTitleBinding: Binding<String> {
        Binding(get: { title }, set: { value in
            guard title != value else { return }
            title = value
            recommendationSession?.update(title: value, excludingEventID: excludingEventID)
        })
    }

    private func attemptAdd() {
        message = nil
        if let failureMessage = onAdd() {
            message = failureMessage
        } else {
            dismiss()
        }
    }

    private func applyRecommendation(_ recommendation: CalendarEventRecommendation) {
        guard let draft = recommendationSession?.apply(id: recommendation.id, to: currentDraft) else { return }
        setDraft(draft)
    }

    private func setDraft(_ draft: CalendarEventReuseDraft) {
        title = draft.title
        startDate = draft.startAt
        endDate = draft.endAt
        note = draft.note ?? ""
        color = draft.color ?? CalendarEventPalette.defaultColor
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
    @State private var initialDraft: CalendarEventReuseDraft
    @State private var showsDiscardConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var linkedTaskCount = 0
    @State private var message: String?
    @State private var canRetrySave = false
    @State private var recommendationSession: CalendarEventRecommendationSession?

    init(
        event: CalendarEvent,
        onDelete: @escaping (CalendarEvent) -> String?
    ) {
        self.event = event
        _initialDraft = State(initialValue: CalendarEventReuseDraft(
            title: event.title, startAt: event.startAt, endAt: event.endAt,
            note: event.note ?? "", color: event.color ?? CalendarEventPalette.defaultColor
        ))
        self.onDelete = onDelete
        _draftTitle = State(initialValue: event.title)
        _draftStartDate = State(initialValue: event.startAt)
        _draftEndDate = State(initialValue: event.endAt)
        _draftColor = State(initialValue: event.color ?? CalendarEventPalette.defaultColor)
        _draftNote = State(initialValue: event.note ?? "")
    }

    private var currentDraft: CalendarEventReuseDraft {
        CalendarEventReuseDraft(title: draftTitle, startAt: draftStartDate, endAt: draftEndDate,
                               note: draftNote, color: draftColor)
    }

    private func requestDismiss() {
        if currentDraft != initialDraft { showsDiscardConfirmation = true }
        else { dismiss() }
    }

    private var canSave: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text("일정 편집")
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
                            title: recommendationTitleBinding,
                            session: recommendationSession,
                            onSelect: applyRecommendation,
                            onReplaceNote: {
                                if let draft = recommendationSession?.replacePreservedNote(in: currentDraft) { setDraft(draft) }
                            },
                            onUndo: {
                                if let draft = recommendationSession?.undo(in: currentDraft) { setDraft(draft) }
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
                            if canRetrySave {
                                DesktopEventSaveFailureView(message: message, retry: save)
                            } else {
                                Label(message, systemImage: "exclamationmark.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .onChange(of: recommendationSession?.selectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: recommendationSession?.state) { _, state in
                    if state == .applied { proxy.scrollTo("event-editor-title", anchor: .top) }
                }
            }
            .frame(maxHeight: 560)

            HStack {
                Button(role: .destructive, action: requestDeletion) {
                    Label("삭제", systemImage: "trash")
                }

                Spacer()

                Button("취소", action: requestDismiss)
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
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: currentDraft != initialDraft,
            onDiscard: { dismiss() }
        )
        .alert("일정을 삭제할까요?", isPresented: $showingDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                canRetrySave = false
                if let failureMessage = onDelete(event) { message = failureMessage }
                else { dismiss() }
            }
        } message: {
            if linkedTaskCount > 0 {
                Text("연결된 작업 \(linkedTaskCount)개의 일정 연결도 함께 해제됩니다.")
            } else {
                Text("삭제한 일정은 되돌릴 수 없습니다.")
            }
        }
        .task {
            guard recommendationSession == nil else { return }
            let session = CalendarEventRecommendationSession(context: modelContext)
            recommendationSession = session
            session.update(
                title: draftTitle,
                excludingEventID: event.id
            )
        }
        .onChange(of: currentDraft) {
            recommendationSession?.invalidateApplication(ifEdited: currentDraft)
        }
    }

    private var recommendationTitleBinding: Binding<String> {
        Binding(get: { draftTitle }, set: { value in
            guard draftTitle != value else { return }
            draftTitle = value
            recommendationSession?.update(title: value, excludingEventID: event.id)
        })
    }

    private func requestDeletion() {
        canRetrySave = false
        do {
            linkedTaskCount = try BoundedQueryService.tasksLinked(toEventID: event.id, in: modelContext).count
            showingDeleteConfirmation = true
        } catch {
            message = "일정 정보를 불러오지 못했어요."
        }
    }

    private func save() {
        message = nil
        canRetrySave = false
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
                message = "일정 정보를 확인해 주세요."
                return
            }
            dismiss()
        } catch {
            message = "일정을 저장하지 못했어요."
            canRetrySave = true
        }
    }

    private func applyRecommendation(_ recommendation: CalendarEventRecommendation) {
        guard let draft = recommendationSession?.apply(id: recommendation.id, to: currentDraft) else { return }
        setDraft(draft)
    }

    private func setDraft(_ draft: CalendarEventReuseDraft) {
        draftTitle = draft.title
        draftStartDate = draft.startAt
        draftEndDate = draft.endAt
        draftNote = draft.note ?? ""
        draftColor = draft.color ?? CalendarEventPalette.defaultColor
    }
}

private struct DesktopEventTitleEditor: View {
    @Binding var title: String
    var session: CalendarEventRecommendationSession?
    var onSelect: (CalendarEventRecommendation) -> Void
    var onReplaceNote: () -> Void
    var onUndo: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("일정 제목", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1)
                }
                .accessibilityIdentifier("event-title-field")
                .id("event-editor-title")
                .focused($isTitleFocused)
                .background {
                    DesktopEventTitleKeyMonitor(
                        isEnabled: isTitleFocused,
                        onMove: { session?.moveSelection(by: $0) ?? false },
                        onSubmit: {
                            guard let recommendation = session?.selectedRecommendation else { return false }
                            onSelect(recommendation)
                            return true
                        },
                        onCancel: {
                            guard session?.isPresented == true else { return false }
                            session?.dismissRecommendations()
                            return true
                        }
                    )
                    .frame(width: 0, height: 0)
                }
            if let session {
                CalendarEventRecommendationContent(
                    session: session, onApply: onSelect,
                    onReplaceNote: onReplaceNote, onUndo: onUndo
                )
            }
        }
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
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.startMonitoring()
        return view
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
        weak var hostView: NSView?

        init(parent: DesktopEventTitleKeyMonitor) {
            self.parent = parent
        }

        func startMonitoring() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self, self.parent.isEnabled,
                      let window = self.hostView?.window,
                      event.window === window, NSApp.keyWindow === window,
                      let editor = window.firstResponder as? NSTextView,
                      editor.isFieldEditor, !editor.hasMarkedText(),
                      let field = editor.delegate as? NSTextField,
                      field.currentEditor() === editor,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
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
                .accessibilityLabel("일정 메모")
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
                        .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                               height: PlanBaseControlMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityValue(selection == option.rawValue ? "선택됨" : "선택 안 됨")
                .accessibilityAddTraits(selection == option.rawValue ? .isSelected : [])
            }
        }
    }
}
