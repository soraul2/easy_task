#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI

enum MobileEventEditorRoute: Identifiable {
    case add(Date)
    case edit(CalendarEvent)
    case duplicate(CalendarEvent, Date)

    var id: String {
        switch self {
        case .add(let date): "add-\(DayKey.key(for: date))"
        case .edit(let event): "edit-\(event.id.uuidString)"
        case .duplicate(let event, let date):
            "duplicate-\(event.instanceID.uuidString)-\(DayKey.key(for: date))"
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

private enum MobileEventEditorField: Hashable {
    case title, note, duration
}

struct MobileEventEditorSheet: View {
    private static let saveFailureAnchor = "event-save-failure-anchor"

    var initialDate: Date
    var event: CalendarEvent?
    var onComplete: ((String) -> Void)?
    private let isDuplicating: Bool
    private let excludedRecommendationEventID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var color: String
    @State private var message: String?
    @State private var saveFailureMessage: String?
    @State private var initialDraft: CalendarEventReuseDraft
    @State private var showsDiscardConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var linkedTaskCount = 0
    @State private var recommendationSession: CalendarEventRecommendationSession?
    @State private var recommendationFeedback: String?
    @FocusState private var focusedField: MobileEventEditorField?

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
        duplicateDraft: CalendarEventReuseDraft? = nil,
        onComplete: ((String) -> Void)? = nil
    ) {
        self.initialDate = initialDate
        self.event = event
        self.onComplete = onComplete
        isDuplicating = duplicateDraft != nil
        excludedRecommendationEventID = event?.id ?? duplicateDraft?.sourceEventID
        _title = State(initialValue: duplicateDraft?.title ?? event?.title ?? "")
        _note = State(initialValue: duplicateDraft?.note ?? event?.note ?? "")
        _startDate = State(
            initialValue: duplicateDraft?.startAt ?? event?.startAt ?? initialDate
        )
        _endDate = State(
            initialValue: duplicateDraft?.endAt ?? event?.endAt ?? initialDate
        )
        _color = State(
            initialValue: duplicateDraft?.color
                ?? event?.color
                ?? CalendarEventPalette.defaultColor
        )
        _initialDraft = State(initialValue: CalendarEventReuseDraft(
            title: duplicateDraft?.title ?? event?.title ?? "",
            startAt: duplicateDraft?.startAt ?? event?.startAt ?? initialDate,
            endAt: duplicateDraft?.endAt ?? event?.endAt ?? initialDate,
            note: duplicateDraft?.note ?? event?.note ?? "",
            color: duplicateDraft?.color ?? event?.color ?? CalendarEventPalette.defaultColor
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    if let message {
                        Section {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .listRowBackground(AppTheme.panel)
                    }
                    Section("일정") {
                        if isDuplicating {
                            Label("복제한 일정", systemImage: "doc.on.doc")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .accessibilityHint("원본과 연결되지 않는 새 일정입니다")
                        }
                        TextField("큰 일정 또는 작업 맥락", text: $title)
                            .focused($focusedField, equals: .title)
                            .accessibilityIdentifier("event-title-field")
                        if let recommendations = recommendationSession?.recommendations,
                           !recommendations.isEmpty {
                            ForEach(recommendations) { recommendation in
                                Button {
                                    applyRecommendation(recommendation)
                                } label: {
                                    Text(recommendation.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.primaryText)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "event-recommendation-\(recommendation.instanceID.uuidString)"
                                )
                                .accessibilityLabel(
                                    "최근 일정 적용. \(recommendation.summary)"
                                )
                                .accessibilityHint(
                                    "현재 시작일은 유지하고 기간, 색상, 메모를 적용합니다"
                                )
                            }
                        }
                        if let recommendationFeedback {
                            Text(recommendationFeedback)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .accessibilityLabel(recommendationFeedback)
                        }
                    }
                    .listRowBackground(AppTheme.panel)

                    if let saveFailureMessage {
                        Section {
                            MobileNoticeBanner(
                                message: saveFailureMessage + ". 입력한 내용은 이 화면에 그대로 남아 있어요.",
                                tone: .error
                            )
                            .accessibilityIdentifier("event-save-failure")
                            .id(Self.saveFailureAnchor)
                        }
                        .listRowBackground(AppTheme.panel)
                    }

                    Section("기간") {
                        MobileEventDateRangeEditor(startDate: $startDate, endDate: $endDate,
                                                   focusedField: $focusedField)
                    }
                    .listRowBackground(AppTheme.panel)
                    Section("띠 색상") {
                        MobileEventColorSelector(selection: $color)
                    }
                    .listRowBackground(AppTheme.panel)
                    Section("메모") {
                        TextField("메모", text: $note, axis: .vertical)
                            .focused($focusedField, equals: .note)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("event-note-field")
                    }
                    .listRowBackground(AppTheme.panel)
                    if isEditing {
                        Section {
                            Button(role: .destructive) {
                                requestEventDeletion()
                            } label: {
                                Label("일정 삭제", systemImage: "trash")
                            }
                        }
                        .listRowBackground(AppTheme.panel)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.accent)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(
                    isEditing ? "일정 편집" : (isDuplicating ? "일정 복제" : "일정 추가")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소", action: requestDismiss)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditing ? "저장" : "추가") {
                            focusedField = nil
                            if saveEvent() { dismiss() }
                        }
                        .disabled(trimmedTitle.isEmpty)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("키보드 닫기") { focusedField = nil }
                            .accessibilityIdentifier("event-editor-keyboard-dismiss")
                    }
                }
                .alert("일정을 삭제할까요?", isPresented: $showingDeleteConfirmation) {
                    Button("취소", role: .cancel) {}
                    Button("삭제", role: .destructive) {
                        deleteEvent()
                    }
                } message: {
                    if linkedTaskCount > 0 {
                        Text("연결된 작업 \(linkedTaskCount)개의 일정 연결도 함께 해제됩니다.")
                    } else {
                        Text("삭제한 일정은 되돌릴 수 없습니다.")
                    }
                }
                .onChange(of: saveFailureMessage) { _, newValue in
                    guard newValue != nil else { return }
                    Swift.Task { @MainActor in
                        await Swift.Task.yield()
                        withAnimation {
                            scrollProxy.scrollTo(Self.saveFailureAnchor, anchor: .center)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if saveFailureMessage != nil {
                        Button {
                            focusedField = nil
                            if saveEvent() { dismiss() }
                        } label: {
                            Label("다시 시도", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlanBaseButtonStyle(.primary))
                        .accessibilityIdentifier("event-save-retry")
                        .accessibilityLabel("일정 저장 다시 시도")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppTheme.background)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(AppTheme.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: currentDraft != initialDraft,
            onDiscard: { dismiss() }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
        .task {
            guard recommendationSession == nil else { return }
            let session = CalendarEventRecommendationSession(context: modelContext)
            recommendationSession = session
            session.update(
                title: title,
                excludingEventID: excludedRecommendationEventID
            )
        }
        .onChange(of: title) {
            recommendationFeedback = nil
            recommendationSession?.update(
                title: title,
                excludingEventID: excludedRecommendationEventID
            )
        }
    }

    private var currentDraft: CalendarEventReuseDraft {
        CalendarEventReuseDraft(title: title, startAt: startDate, endAt: endDate, note: note, color: color)
    }

    private func requestDismiss() {
        focusedField = nil
        if currentDraft != initialDraft { showsDiscardConfirmation = true }
        else { dismiss() }
    }

    @discardableResult
    private func saveEvent() -> Bool {
        message = nil
        saveFailureMessage = nil

#if DEBUG
        if MobileEventEditorUITestFixture.consumeSaveFailure() {
            saveFailureMessage = saveFailureDescription
            return false
        }
#endif

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
                let draft = CalendarEventReuseDraft(
                    title: trimmedTitle,
                    startAt: startDate,
                    endAt: endDate,
                    note: note,
                    color: color
                )
                guard let event = CalendarEventReuseRules.makeIndependentEvent(
                    from: draft
                ) else {
                    return false
                }
                modelContext.insert(event)
                return true
            }
            guard didSave else {
                message = "일정 내용을 확인해 주세요"
                return false
            }

            onComplete?(
                isEditing
                    ? "일정을 저장했어요"
                    : (isDuplicating
                        ? "독립된 복제 일정을 추가했어요"
                        : "일정을 추가했어요")
            )
            return true
        } catch {
            saveFailureMessage = saveFailureDescription
            return false
        }
    }

    private var saveFailureDescription: String {
        isEditing
            ? "일정을 저장하지 못했어요"
            : (isDuplicating
                ? "복제 일정을 추가하지 못했어요"
                : "일정을 추가하지 못했어요")
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
                onComplete?("일정을 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
            } else {
                onComplete?("일정을 삭제했어요")
            }
            dismiss()
        } catch {
            message = "일정을 삭제하지 못했어요"
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
            message = "일정 정보를 불러오지 못했어요"
        }
    }

    private func applyRecommendation(
        _ recommendation: CalendarEventRecommendation
    ) {
        let current = CalendarEventReuseDraft(
            title: title,
            startAt: startDate,
            endAt: endDate,
            note: note,
            color: color,
            sourceEventID: excludedRecommendationEventID
        )
        let applied = CalendarEventReuseRules.applying(
            recommendation,
            to: current
        )
        startDate = applied.startAt
        endDate = applied.endAt
        note = applied.note ?? ""
        color = applied.color ?? CalendarEventPalette.defaultColor
        recommendationFeedback = "이전 일정의 기간·색상·메모를 적용했어요"
        recommendationSession?.dismissRecommendations()
    }
}

#if DEBUG
@MainActor
private enum MobileEventEditorUITestFixture {
    private static var didFailSave = false

    static func consumeSaveFailure() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didFailSave,
              arguments.contains("--ui-testing"),
              arguments.contains("--ui-testing-event-save-failure-once")
        else {
            return false
        }
        didFailSave = true
        return true
    }
}
#endif

private struct MobileEventDateRangeEditor: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var focusedField: FocusState<MobileEventEditorField?>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                ForEach(MobileEventDurationPreset.allCases) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        Text(preset.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlanBaseButtonStyle(selectedPreset == preset ? .primary : .secondary))
                    .accessibilityValue(selectedPreset == preset ? "선택됨" : "")
                    .accessibilityAddTraits(selectedPreset == preset ? .isSelected : [])
                    .accessibilityIdentifier("event-duration-\(preset.rawValue)")
                }
            }
            HStack(spacing: 8) {
                TextField("직접 입력", text: $customDurationText)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: .duration)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: PlanBaseControlMetrics.minimumTargetSize)
                    .accessibilityLabel("일정 기간, 일 단위")
                    .accessibilityIdentifier("event-custom-duration")
                    .onChange(of: customDurationText) {
                        customDurationText = sanitizedDurationText(customDurationText)
                    }
                Text("일")
                    .foregroundStyle(AppTheme.secondaryText)
                Button("적용") {
                    applyCustomDuration()
                }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
                .accessibilityIdentifier("event-apply-duration")
                .disabled(customDuration == nil)
            }
            .padding(8)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
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
        focusedField.wrappedValue = nil
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
                    ZStack {
                        Circle()
                            .fill(option.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Circle()
                                    .stroke(
                                        selection == option.rawValue
                                            ? AppTheme.primaryText
                                            : AppTheme.border,
                                        lineWidth: selection == option.rawValue ? 3 : 1
                                    )
                            }

                        if selection == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(option.foregroundColor)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityValue(selection == option.rawValue ? "선택됨" : "")
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
