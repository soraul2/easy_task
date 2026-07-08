#if os(iOS)
#if !XCODE_APP_BUNDLE
import EasyTaskCore
#endif
import SwiftData
import SwiftUI

private enum CalendarSheet: Identifiable {
    case addEvent(Date)
    case day(Date)
    case templates

    var id: String {
        switch self {
        case .addEvent(let date): "add-\(DayKey.key(for: date))"
        case .day(let date): "day-\(DayKey.key(for: date))"
        case .templates: "templates"
        }
    }
}

struct MobileCalendarView: View {
    var onOpenBoardDate: (Date) -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CalendarEvent]
    @Query private var tasks: [TodoTask]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var visibleMonth = DayKey.startOfMonth(for: Date())
    @State private var selectedDate = DayKey.startOfDay(for: Date())
    @State private var sheet: CalendarSheet?
    @State private var placementTemplate: TaskTemplate?
    @State private var placementDatesByKey: [String: Date] = [:]
    @State private var placementMessage: String?
    @State private var calendarNotice: String?
    @State private var calendarNoticeToken = UUID()
    @State private var showingTemplateApplyConfirmation = false

    private let specialDayStore = SpecialDayStore.load()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                CalendarHeader(visibleMonth: $visibleMonth, selectedDate: $selectedDate)
                if let placementTemplate {
                    CalendarTemplatePlacementStatus(
                        templateName: placementTemplate.name,
                        selectedCount: placementDatesByKey.count,
                        message: placementMessage
                    )
                }
                CalendarWeekdayHeader()
                monthGrid
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let calendarNotice {
                    CalendarNoticeBanner(message: calendarNotice)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: calendarNotice)
            .navigationTitle(placementTemplate == nil ? "캘린더" : "날짜 선택")
            .toolbar {
                if placementTemplate == nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { sheet = .templates } label: {
                            Label("템플릿 배치", systemImage: "square.grid.3x3")
                        }
                        Button { sheet = .addEvent(selectedDate) } label: {
                            Label("이벤트 추가", systemImage: "plus")
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            cancelTemplatePlacement()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("적용") {
                            requestTemplatePlacementConfirmation()
                        }
                        .disabled(placementDatesByKey.isEmpty)
                    }
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .addEvent(let date):
                    MobileEventEditorSheet(initialDate: date)
                case .day(let date):
                    MobileCalendarDaySheet(
                        date: date,
                        events: eventsForDate(date),
                        tasks: tasksForDate(date),
                        onOpenBoard: {
                            onOpenBoardDate(date)
                        }
                    )
                case .templates:
                    MobileTemplatePlacementSheet(
                        templates: templates,
                        items: templateItems,
                        onStartPlacement: startTemplatePlacement
                    )
                }
            }
            .alert("템플릿을 적용할까요?", isPresented: $showingTemplateApplyConfirmation, presenting: placementTemplate) { _ in
                Button("취소", role: .cancel) {}
                Button("적용") {
                    applyTemplatePlacement()
                }
            } message: { template in
                Text("\"\(template.name)\" 템플릿을 선택한 \(placementDatesByKey.count)일에 적용합니다.")
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(DayKey.monthGridDates(for: visibleMonth), id: \.self) { date in
                MobileMonthDayCell(
                    date: date,
                    visibleMonth: visibleMonth,
                    isSelected: DayKey.key(for: date) == DayKey.key(for: selectedDate),
                    isPlacementSelected: placementDatesByKey[DayKey.key(for: date)] != nil,
                    events: eventsForDate(date),
                    taskCount: taskCount(for: date),
                    specialDays: specialDayStore.days(on: date)
                )
                .onTapGesture {
                    let day = DayKey.startOfDay(for: date)
                    selectedDate = day
                    if placementTemplate == nil {
                        sheet = .day(day)
                    } else {
                        togglePlacementDate(day)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func eventsForDate(_ date: Date) -> [CalendarEvent] {
        let key = DayKey.key(for: date)
        return events
            .filter { $0.startDayKey <= key && key <= $0.endDayKey }
            .sorted { $0.startDayKey < $1.startDayKey }
    }

    private func taskCount(for date: Date) -> Int {
        tasksForDate(date).count
    }

    private func tasksForDate(_ date: Date) -> [TodoTask] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: DayKey.key(for: date)
        )
    }

    private func startTemplatePlacement(_ template: TaskTemplate) {
        placementTemplate = template
        placementDatesByKey = [:]
        placementMessage = nil
    }

    private func cancelTemplatePlacement() {
        placementTemplate = nil
        placementDatesByKey = [:]
        placementMessage = nil
        showingTemplateApplyConfirmation = false
    }

    private func togglePlacementDate(_ date: Date) {
        let day = DayKey.startOfDay(for: date)
        let key = DayKey.key(for: day)
        if placementDatesByKey[key] == nil {
            placementDatesByKey[key] = day
        } else {
            placementDatesByKey.removeValue(forKey: key)
        }
        placementMessage = nil
    }

    private func requestTemplatePlacementConfirmation() {
        guard placementTemplate != nil else { return }
        guard !placementDatesByKey.isEmpty else {
            placementMessage = "날짜를 선택하세요"
            return
        }
        showingTemplateApplyConfirmation = true
    }

    private func applyTemplatePlacement() {
        guard let placementTemplate else { return }
        let createdCount = TemplateService.applyTemplate(
            placementTemplate,
            items: TemplateListRules.itemsForTemplate(placementTemplate, in: templateItems),
            selectedDates: Array(placementDatesByKey.values),
            existingTasks: tasks,
            in: modelContext
        )
        guard createdCount > 0 else {
            placementMessage = "추가할 새 작업이 없어요"
            return
        }

        let selectedDayCount = placementDatesByKey.count
        cancelTemplatePlacement()
        showCalendarNotice("\"\(placementTemplate.name)\" 템플릿으로 \(createdCount)개 작업을 \(selectedDayCount)일에 배치했어요")
    }

    private func showCalendarNotice(_ message: String) {
        let token = UUID()
        calendarNoticeToken = token
        calendarNotice = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard calendarNoticeToken == token else { return }
            calendarNotice = nil
        }
    }
}

private struct CalendarHeader: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date

    var body: some View {
        HStack {
            Button { visibleMonth = DayKey.addingMonths(-1, to: visibleMonth) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 달")
            Text(DayKey.monthTitle(visibleMonth))
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Button("오늘") {
                visibleMonth = DayKey.startOfMonth(for: Date())
                selectedDate = DayKey.startOfDay(for: Date())
            }
            Button { visibleMonth = DayKey.addingMonths(1, to: visibleMonth) } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("다음 달")
        }
        .padding(.horizontal, 16)
    }
}

private struct CalendarWeekdayHeader: View {
    var body: some View {
        HStack {
            ForEach(DayKey.weekdaySymbols(), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct CalendarTemplatePlacementStatus: View {
    var templateName: String
    var selectedCount: Int
    var message: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(AppTheme.event)
            VStack(alignment: .leading, spacing: 2) {
                Text(templateName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(message ?? "\(selectedCount)일 선택됨")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

private struct CalendarNoticeBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
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

private struct MobileMonthDayCell: View {
    var date: Date
    var visibleMonth: Date
    var isSelected: Bool
    var isPlacementSelected: Bool
    var events: [CalendarEvent]
    var taskCount: Int
    var specialDays: [SpecialDay]

    private var background: Color {
        if isPlacementSelected { return AppTheme.event.opacity(0.22) }
        if DayKey.isToday(date) { return AppTheme.selectedTab.opacity(0.35) }
        return AppTheme.panel
    }

    private var accessibilityLabel: String {
        var parts = [DayKey.display(date)]
        if isSelected { parts.append("선택됨") }
        if isPlacementSelected { parts.append("배치 선택됨") }
        if let specialDay = specialDays.first { parts.append(specialDay.name) }
        if !events.isEmpty { parts.append("이벤트 \(events.count)개") }
        if taskCount > 0 { parts.append("작업 \(taskCount)개") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(DayKey.dayNumber(date))
                    .font(.caption.weight(.bold))
                if let specialDay = specialDays.first {
                    Text(specialDay.name)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(specialDay.isPublicHoliday ? .red : .secondary)
                }
                Spacer()
                if isPlacementSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.event)
                }
            }

            ForEach(events.prefix(2)) { event in
                Text(event.title)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CalendarEventPalette.color(for: event.color), in: RoundedRectangle(cornerRadius: 2))
                    .foregroundStyle(AppTheme.eventText)
            }

            if taskCount > 0 {
                Text("작업 \(taskCount)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(height: 72)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isPlacementSelected || isSelected ? AppTheme.event : AppTheme.border,
                    lineWidth: isPlacementSelected || isSelected ? 2 : 1
                )
        }
        .opacity(DayKey.isSameMonth(date, visibleMonth) ? 1 : 0.38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

private enum MobileEventEditorRoute: Identifiable {
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

private struct MobileEventEditorSheet: View {
    var initialDate: Date
    var event: CalendarEvent?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var color: String
    @State private var showingAddConfirmation = false

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

    init(initialDate: Date, event: CalendarEvent? = nil) {
        self.initialDate = initialDate
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _note = State(initialValue: event?.note ?? "")
        _startDate = State(initialValue: event?.startAt ?? initialDate)
        _endDate = State(initialValue: event?.endAt ?? initialDate)
        _color = State(initialValue: event?.color ?? CalendarEventPalette.defaultColor)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                            deleteEvent()
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
                            saveEvent()
                            dismiss()
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
                    saveEvent()
                    dismiss()
                }
            } message: {
                Text("\"\(trimmedTitle)\" 이벤트를 \(DayKey.display(normalizedStartDate))부터 \(DayKey.display(normalizedEndDate))까지 추가합니다.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveEvent() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let event {
            event.title = trimmedTitle
            event.startAt = normalizedStartDate
            event.endAt = normalizedEndDate
            event.startDayKey = DayKey.key(for: normalizedStartDate)
            event.endDayKey = DayKey.key(for: normalizedEndDate)
            event.note = trimmedNote.isEmpty ? nil : trimmedNote
            event.color = color
            event.updatedAt = Date()
        } else {
            modelContext.insert(CalendarEvent(
                title: trimmedTitle,
                startAt: normalizedStartDate,
                endAt: normalizedEndDate,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                color: color
            ))
        }
    }

    private func deleteEvent() {
        guard let event else { return }
        modelContext.delete(event)
        dismiss()
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

private struct MobileCalendarDaySheet: View {
    var date: Date
    var events: [CalendarEvent]
    var tasks: [TodoTask]
    var onOpenBoard: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var eventEditorRoute: MobileEventEditorRoute?

    var body: some View {
        NavigationStack {
            List {
                Section("이벤트") {
                    Button {
                        eventEditorRoute = .add(date)
                    } label: {
                        Label("이벤트 추가", systemImage: "plus.circle")
                    }
                    if events.isEmpty {
                        Text("이벤트 없음")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .lineLimit(2)
                                Text("\(event.startDayKey) - \(event.endDayKey)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = event.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Button {
                                eventEditorRoute = .edit(event)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("이벤트 편집")

                            Button(role: .destructive) {
                                modelContext.delete(event)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("이벤트 삭제")
                        }
                    }
                }
                Section("작업") {
                    ForEach(tasks.prefix(6)) { task in
                        HStack {
                            Text(task.title)
                                .lineLimit(2)
                            Spacer()
                            Text((TaskStatus(rawValue: task.status) ?? .todo).title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if tasks.count > 6 {
                        Text("외 \(tasks.count - 6)개 작업")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if tasks.isEmpty {
                        Text("작업 없음")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    dismiss()
                    onOpenBoard()
                } label: {
                    Label("이 날짜 칸반보드 열기", systemImage: "rectangle.3.group")
                }
            }
            .navigationTitle(DayKey.display(date))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $eventEditorRoute) { route in
            switch route {
            case .add(let date):
                MobileEventEditorSheet(initialDate: date)
            case .edit(let event):
                MobileEventEditorSheet(initialDate: event.startAt, event: event)
            }
        }
    }
}

private struct MobileTemplatePlacementSheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var onStartPlacement: (TaskTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: TaskTemplate?
    @State private var detailTemplate: TaskTemplate?
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites
    @State private var message: String?

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
    }

    private var emptyTitle: String {
        if templates.isEmpty { return "템플릿 없음" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "검색 결과 없음" }
        return "즐겨찾기 템플릿 없음"
    }

    private var emptyDescription: Text {
        if templates.isEmpty { return Text("반복할 작업 묶음을 템플릿으로 저장하면 여러 날짜에 배치할 수 있어요.") }
        if scope == .favorites { return Text("전체보기로 전환하면 모든 템플릿을 볼 수 있어요.") }
        return Text("다른 검색어로 다시 시도하세요.")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("템플릿") {
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
                    ForEach(filteredTemplates) { template in
                        let templateItems = TemplateListRules.itemsForTemplate(template, in: items)
                        HStack(spacing: 12) {
                            Button {
                                selectedTemplate = template
                                message = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(template.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        if selectedTemplate?.id == template.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppTheme.event)
                                        }
                                    }
                                    Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                detailTemplate = template
                            } label: {
                                Label("상세", systemImage: "list.bullet.rectangle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("템플릿 상세 보기")

                            Button {
                                toggleFavorite(template)
                            } label: {
                                Image(systemName: template.isFavorite ? "star.fill" : "star")
                                    .font(.headline)
                                    .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(template.isFavorite ? "즐겨찾기 제거" : "즐겨찾기 추가")
                        }
                    }
                    if filteredTemplates.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "square.grid.3x3",
                            description: emptyDescription
                        )
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("템플릿 배치")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("배치") {
                        startPlacement()
                    }
                    .disabled(selectedTemplate == nil)
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
                if selectedTemplate?.isFavorite == false && scope == .favorites {
                    selectedTemplate = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $detailTemplate) { template in
            MobileTemplateDetailSheet(
                template: template,
                items: TemplateListRules.itemsForTemplate(template, in: items)
            )
        }
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        template.isFavorite.toggle()
        template.updatedAt = Date()
        if selectedTemplate?.id == template.id && !template.isFavorite && scope == .favorites {
            selectedTemplate = nil
        }
        message = template.isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요"
    }

    private func startPlacement() {
        guard let selectedTemplate else { return }
        let applicableItems = TemplateListRules.itemsForTemplate(selectedTemplate, in: items).filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !applicableItems.isEmpty else {
            message = "템플릿에 적용할 작업이 없어요"
            return
        }

        message = nil
        onStartPlacement(selectedTemplate)
        dismiss()
    }
}

private struct MobileTemplateDetailSheet: View {
    var template: TaskTemplate
    var items: [TaskTemplateItem]
    @Environment(\.dismiss) private var dismiss

    private var orderedItems: [TaskTemplateItem] {
        items
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("템플릿") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text("\(orderedItems.count)개 작업")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: template.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                            .accessibilityLabel(template.isFavorite ? "즐겨찾기" : "일반 템플릿")
                    }
                }

                Section("작업") {
                    if orderedItems.isEmpty {
                        ContentUnavailableView("작업 없음", systemImage: "checklist")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(orderedItems) { item in
                            MobileTemplateTaskDetailRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("상세 보기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MobileTemplateTaskDetailRow: View {
    var item: TaskTemplateItem

    private var priority: TaskPriority? {
        item.priority.flatMap(TaskPriority.init(rawValue:))
    }

    private var tags: [String] {
        item.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.headline)
                .lineLimit(2)

            if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if priority != nil || item.estimatedMinutes != nil || !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let priority {
                            Label(priority.title, systemImage: "flag.fill")
                        }
                        if let estimatedMinutes = item.estimatedMinutes {
                            Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                        }
                        ForEach(tags, id: \.self) { tag in
                            Label("#\(tag)", systemImage: "tag")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
#endif
