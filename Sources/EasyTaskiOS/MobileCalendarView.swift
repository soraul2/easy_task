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

    private let specialDayStore = SpecialDayStore.load()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                CalendarHeader(visibleMonth: $visibleMonth, selectedDate: $selectedDate)
                CalendarWeekdayHeader()
                monthGrid
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("캘린더")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { sheet = .templates } label: {
                        Label("템플릿 배치", systemImage: "square.grid.3x3")
                    }
                    Button { sheet = .addEvent(selectedDate) } label: {
                        Label("이벤트 추가", systemImage: "plus")
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
                        visibleMonth: visibleMonth,
                        templates: templates,
                        items: templateItems,
                        existingTasks: tasks
                    )
                }
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
                    events: eventsForDate(date),
                    taskCount: taskCount(for: date),
                    specialDays: specialDayStore.days(on: date)
                )
                .onTapGesture {
                    selectedDate = DayKey.startOfDay(for: date)
                    sheet = .day(selectedDate)
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

private struct MobileMonthDayCell: View {
    var date: Date
    var visibleMonth: Date
    var isSelected: Bool
    var events: [CalendarEvent]
    var taskCount: Int
    var specialDays: [SpecialDay]

    private var background: Color {
        if DayKey.isToday(date) { return AppTheme.selectedTab.opacity(0.35) }
        return AppTheme.panel
    }

    private var accessibilityLabel: String {
        var parts = [DayKey.display(date)]
        if isSelected { parts.append("선택됨") }
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
                .stroke(isSelected ? AppTheme.event : AppTheme.border, lineWidth: isSelected ? 2 : 1)
        }
        .opacity(DayKey.isSameMonth(date, visibleMonth) ? 1 : 0.38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

private struct MobileEventEditorSheet: View {
    var initialDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var color = CalendarEventPalette.defaultColor

    init(initialDate: Date) {
        self.initialDate = initialDate
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("일정") {
                    TextField("이벤트 제목", text: $title)
                    TextField("메모", text: $note, axis: .vertical)
                }
                Section("기간") {
                    DatePicker("시작", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료", selection: $endDate, displayedComponents: .date)
                    Picker("색상", selection: $color) {
                        ForEach(CalendarEventColor.allCases) { color in
                            Text(color.title).tag(color.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("이벤트 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        addEvent()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addEvent() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = CalendarEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: min(startDate, endDate),
            endAt: max(startDate, endDate),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            color: color
        )
        modelContext.insert(event)
    }
}

private struct MobileCalendarDaySheet: View {
    var date: Date
    var events: [CalendarEvent]
    var tasks: [TodoTask]
    var onOpenBoard: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEventEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("이벤트") {
                    Button {
                        showingEventEditor = true
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
        .sheet(isPresented: $showingEventEditor) {
            MobileEventEditorSheet(initialDate: date)
        }
    }
}

private struct MobileTemplatePlacementSheet: View {
    var visibleMonth: Date
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var existingTasks: [TodoTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: TaskTemplate?
    @State private var selectedDatesByKey: [String: Date] = [:]
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
                        Button {
                            selectedTemplate = template
                            message = nil
                        } label: {
                            HStack {
                                Text(template.name)
                                Spacer()
                                if selectedTemplate?.id == template.id {
                                    Image(systemName: "checkmark")
                                }
                            }
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
                Section("배치 날짜") {
                    if !selectedDatesByKey.isEmpty {
                        Label("\(selectedDatesByKey.count)일 선택됨", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(DayKey.monthGridDates(for: visibleMonth).filter { DayKey.isSameMonth($0, visibleMonth) }, id: \.self) { date in
                        let key = DayKey.key(for: date)
                        Button {
                            toggleDate(date, key: key)
                        } label: {
                            HStack {
                                Text(DayKey.display(date))
                                    .lineLimit(1)
                                Spacer()
                                if selectedDatesByKey[key] != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
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
                        apply()
                    }
                    .disabled(selectedTemplate == nil || selectedDatesByKey.isEmpty)
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
    }

    private func toggleDate(_ date: Date, key: String) {
        if selectedDatesByKey[key] == nil {
            selectedDatesByKey[key] = date
        } else {
            selectedDatesByKey.removeValue(forKey: key)
        }
        message = nil
    }

    private func apply() {
        guard let selectedTemplate else { return }
        let createdCount = TemplateService.applyTemplate(
            selectedTemplate,
            items: TemplateListRules.itemsForTemplate(selectedTemplate, in: items),
            selectedDates: Array(selectedDatesByKey.values),
            existingTasks: existingTasks,
            in: modelContext
        )
        guard createdCount > 0 else {
            message = "추가할 새 작업이 없어요"
            return
        }
        dismiss()
    }
}
#endif
