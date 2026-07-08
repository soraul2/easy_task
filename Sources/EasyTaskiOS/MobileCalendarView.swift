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
                        Image(systemName: "plus")
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
                        tasks: tasks.filter { $0.plannedDayKey == DayKey.key(for: date) },
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
        let key = DayKey.key(for: date)
        return tasks.filter { $0.plannedDayKey == key && $0.archivedAt == nil }.count
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
            Text(DayKey.monthTitle(visibleMonth))
                .font(.title2.bold())
            Spacer()
            Button("오늘") {
                visibleMonth = DayKey.startOfMonth(for: Date())
                selectedDate = DayKey.startOfDay(for: Date())
            }
            Button { visibleMonth = DayKey.addingMonths(1, to: visibleMonth) } label: {
                Image(systemName: "chevron.right")
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(DayKey.dayNumber(date))
                    .font(.caption.weight(.bold))
                if let specialDay = specialDays.first {
                    Text(specialDay.name)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(specialDay.isPublicHoliday ? .red : .secondary)
                }
                Spacer()
            }

            ForEach(events.prefix(2)) { event in
                Text(event.title)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
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
    }
}

private struct MobileEventEditorSheet: View {
    var initialDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
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
                TextField("이벤트 제목", text: $title)
                DatePicker("시작", selection: $startDate, displayedComponents: .date)
                DatePicker("종료", selection: $endDate, displayedComponents: .date)
                Picker("색상", selection: $color) {
                    ForEach(CalendarEventColor.allCases) { color in
                        Text(color.title).tag(color.rawValue)
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
    }

    private func addEvent() {
        let event = CalendarEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: min(startDate, endDate),
            endAt: max(startDate, endDate),
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

    var body: some View {
        NavigationStack {
            List {
                Section("이벤트") {
                    if events.isEmpty {
                        Text("이벤트 없음")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text("\(event.startDayKey) - \(event.endDayKey)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                modelContext.delete(event)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                Section("작업") {
                    ForEach(tasks.prefix(6)) { task in
                        Text(task.title)
                    }
                    if tasks.isEmpty {
                        Text("작업 없음")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("이 날짜 칸반보드 열기") {
                    dismiss()
                    onOpenBoard()
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

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
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
                    ForEach(filteredTemplates) { template in
                        Button {
                            selectedTemplate = template
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
                }
                Section("배치 날짜") {
                    ForEach(DayKey.monthGridDates(for: visibleMonth).filter { DayKey.isSameMonth($0, visibleMonth) }, id: \.self) { date in
                        let key = DayKey.key(for: date)
                        Button {
                            toggleDate(date, key: key)
                        } label: {
                            HStack {
                                Text(DayKey.display(date))
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
                        dismiss()
                    }
                    .disabled(selectedTemplate == nil || selectedDatesByKey.isEmpty)
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
    }

    private func apply() {
        guard let selectedTemplate else { return }
        TemplateService.applyTemplate(
            selectedTemplate,
            items: TemplateListRules.itemsForTemplate(selectedTemplate, in: items),
            selectedDates: Array(selectedDatesByKey.values),
            existingTasks: existingTasks,
            in: modelContext
        )
    }
}
#endif
