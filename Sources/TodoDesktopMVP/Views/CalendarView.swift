import SwiftData
import SwiftUI
import EasyTaskCore

private enum CalendarSheet: Identifiable {
    case addEvent
    case templatePlacement
    case editEvent(UUID)

    var id: String {
        switch self {
        case .addEvent: "addEvent"
        case .templatePlacement: "templatePlacement"
        case .editEvent(let id): "editEvent-\(id.uuidString)"
        }
    }
}

struct CalendarView: View {
    private static let specialDayStore = SpecialDayStore.load()

    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CalendarEvent]
    @Query private var tasks: [Task]
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var visibleMonth = DayKey.startOfMonth(for: Date())
    @State private var selectedDate = DayKey.startOfDay(for: Date())
    @State private var title = ""
    @State private var startDate = DayKey.startOfDay(for: Date())
    @State private var endDate = DayKey.startOfDay(for: Date())
    @State private var selectedEventColor = CalendarEventPalette.defaultColor
    @State private var presentedSheet: CalendarSheet?
    @State private var placementTemplate: TaskTemplate?
    @State private var placementDatesByKey: [String: Date] = [:]

    private var monthDates: [Date] { DayKey.monthGridDates(for: visibleMonth) }
    private var isPlacementMode: Bool { placementTemplate != nil }

    private var selectedPlacementDates: [Date] {
        placementDatesByKey.keys.sorted().compactMap { placementDatesByKey[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if isPlacementMode {
                placementToolbar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
            }

            weekdayHeader
                .padding(.horizontal, 22)

            monthGrid
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addEvent:
                AddEventSheet(
                    title: $title,
                    startDate: $startDate,
                    endDate: $endDate,
                    color: $selectedEventColor,
                    onAdd: {
                        if addEvent() {
                            presentedSheet = nil
                        }
                    }
                )
            case .templatePlacement:
                TemplatePlacementSheet(
                    templates: templates,
                    items: templateItems,
                    onSelect: { template in
                        beginPlacement(with: template)
                        presentedSheet = nil
                    }
                )
            case .editEvent(let eventID):
                if let event = events.first(where: { $0.id == eventID }) {
                    EventEditorSheet(
                        event: event,
                        onDelete: { event in
                            removeEvent(event)
                            presentedSheet = nil
                        }
                    )
                } else {
                    EmptySheetState(
                        symbol: "calendar.badge.exclamationmark",
                        title: "이벤트를 찾을 수 없음",
                        message: "이미 삭제되었거나 더 이상 사용할 수 없는 이벤트입니다."
                    )
                    .padding(22)
                    .frame(width: 380)
                    .background(AppTheme.panel)
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            regularHeader
            compactHeader
        }
    }

    private var regularHeader: some View {
        HStack(spacing: 12) {
            monthNavigation

            Text(DayKey.monthTitle(visibleMonth))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.leading, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            templatePlacementButton(compact: false)
            addEventButton
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                monthNavigation

                Text(DayKey.monthTitle(visibleMonth))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Spacer()
                templatePlacementButton(compact: true)
                addEventButton
            }
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 8) {
            Button {
                visibleMonth = DayKey.addingMonths(-1, to: visibleMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Button {
                visibleMonth = DayKey.startOfMonth(for: Date())
                selectedDate = DayKey.startOfDay(for: Date())
            } label: {
                Text("오늘")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)

            Button {
                visibleMonth = DayKey.addingMonths(1, to: visibleMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
        }
    }

    private func templatePlacementButton(compact: Bool) -> some View {
        Button {
            if isPlacementMode {
                cancelPlacement()
            } else {
                presentedSheet = .templatePlacement
            }
        } label: {
            if compact {
                Image(systemName: isPlacementMode ? "xmark.circle" : "square.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 34)
                    .calendarToolbarButtonBackground()
            } else {
                Label(
                    isPlacementMode ? "배치 종료" : "템플릿 배치",
                    systemImage: isPlacementMode ? "xmark.circle" : "square.grid.3x3"
                )
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .calendarToolbarButtonBackground()
            }
        }
        .buttonStyle(.plain)
        .help(isPlacementMode ? "템플릿 배치 종료" : "템플릿을 날짜에 배치")
    }

    private var addEventButton: some View {
        Button {
            prepareAddEvent(for: selectedDate)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 42, height: 34)
                .calendarToolbarButtonBackground(isPrimary: true)
        }
        .buttonStyle(.plain)
        .help("이벤트 추가")
    }

    private var placementToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(AppTheme.secondaryText)

            Text(placementTemplate?.name ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("\(placementDatesByKey.count)일 선택")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())

            Spacer()

            Button("취소") {
                cancelPlacement()
            }
            .buttonStyle(.bordered)

            Button {
                applyTemplatePlacement()
            } label: {
                Label("배치", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(placementDatesByKey.isEmpty)
        }
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(DayKey.weekdaySymbols(), id: \.self) { weekday in
                Text(weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.panel)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(AppTheme.border)
                            .frame(width: 1)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var monthGrid: some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 7
            let cellHeight = max((proxy.size.height - 5) / 6, 54)
            let eventTopInset = min(max(cellHeight * 0.34, 28), 38)
            let laneHeight: CGFloat = cellHeight < 76 ? 18 : 21
            let barHeight: CGFloat = cellHeight < 76 ? 16 : 18
            let maxEventLanes = max(1, min(4, Int((cellHeight - eventTopInset - 6) / laneHeight)))
            let segments = eventSegments(maxLanes: maxEventLanes)

            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(monthDates, id: \.self) { date in
                        MonthDayCell(
                            date: date,
                            visibleMonth: visibleMonth,
                            selectedDate: selectedDate,
                            placementMode: isPlacementMode,
                            isPlacementSelected: placementDatesByKey[DayKey.key(for: date)] != nil,
                            specialDays: Self.specialDayStore.days(on: date),
                            onSelect: {
                                if isPlacementMode {
                                    togglePlacementDate(date)
                                } else {
                                    selectedDate = date
                                    if !DayKey.isSameMonth(date, visibleMonth) {
                                        visibleMonth = DayKey.startOfMonth(for: date)
                                    }
                                }
                            },
                            onAddEvent: {
                                prepareAddEvent(for: date)
                            }
                        )
                        .frame(height: cellHeight)
                    }
                }

                ForEach(segments) { segment in
                    CalendarEventSegmentButton(
                        segment: segment,
                        isDisabled: isPlacementMode,
                        width: max(cellWidth * CGFloat(segment.span) - 10, 32),
                        height: barHeight,
                        xOffset: cellWidth * CGFloat(segment.startColumn) + 5,
                        yOffset: CGFloat(segment.weekIndex) * cellHeight + eventTopInset + CGFloat(segment.lane) * laneHeight,
                        onEdit: { event in
                            presentedSheet = .editEvent(event.id)
                        },
                        onDelete: removeEvent
                    )
                }
            }
            .frame(height: cellHeight * 6)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
    }

    private func addEvent() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let normalizedStart = min(startDate, endDate)
        let normalizedEnd = max(startDate, endDate)
        modelContext.insert(CalendarEvent(
            title: trimmedTitle,
            startAt: normalizedStart,
            endAt: normalizedEnd,
            color: selectedEventColor
        ))
        title = ""
        selectedEventColor = CalendarEventPalette.defaultColor
        return true
    }

    private func prepareAddEvent(for date: Date) {
        let normalizedDate = DayKey.startOfDay(for: date)
        selectedDate = normalizedDate
        if !DayKey.isSameMonth(normalizedDate, visibleMonth) {
            visibleMonth = DayKey.startOfMonth(for: normalizedDate)
        }

        title = ""
        startDate = normalizedDate
        endDate = normalizedDate
        selectedEventColor = CalendarEventPalette.defaultColor
        presentedSheet = .addEvent
    }

    private func removeEvent(_ event: CalendarEvent) {
        modelContext.delete(event)
    }

    private func beginPlacement(with template: TaskTemplate) {
        placementTemplate = template
        placementDatesByKey = [:]
    }

    private func cancelPlacement() {
        placementTemplate = nil
        placementDatesByKey = [:]
    }

    private func togglePlacementDate(_ date: Date) {
        let normalizedDate = DayKey.startOfDay(for: date)
        let dayKey = DayKey.key(for: normalizedDate)
        selectedDate = normalizedDate

        if placementDatesByKey[dayKey] == nil {
            placementDatesByKey[dayKey] = normalizedDate
        } else {
            placementDatesByKey.removeValue(forKey: dayKey)
        }
    }

    private func applyTemplatePlacement() {
        guard let placementTemplate else { return }

        TemplateService.applyTemplate(
            placementTemplate,
            items: templateItems,
            selectedDates: selectedPlacementDates,
            existingTasks: tasks,
            in: modelContext
        )
        cancelPlacement()
    }

    private func eventsFor(dayKey: String) -> [CalendarEvent] {
        events
            .filter { $0.startDayKey <= dayKey && dayKey <= $0.endDayKey }
            .sorted {
                if $0.startDayKey == $1.startDayKey {
                    return $0.title < $1.title
                }
                return $0.startDayKey < $1.startDayKey
            }
    }

    private func eventSegments(maxLanes: Int = 4) -> [CalendarEventSegment] {
        let weeks = stride(from: 0, to: monthDates.count, by: 7).map {
            Array(monthDates[$0..<min($0 + 7, monthDates.count)])
        }

        var segments: [CalendarEventSegment] = []

        for (weekIndex, weekDates) in weeks.enumerated() {
            guard let weekStart = weekDates.first, let weekEnd = weekDates.last else { continue }
            let weekStartKey = DayKey.key(for: weekStart)
            let weekEndKey = DayKey.key(for: weekEnd)

            let overlappingEvents = events
                .filter { $0.startDayKey <= weekEndKey && $0.endDayKey >= weekStartKey }
                .sorted {
                    if $0.startDayKey == $1.startDayKey {
                        if $0.endDayKey == $1.endDayKey {
                            return $0.title < $1.title
                        }
                        return $0.endDayKey > $1.endDayKey
                    }
                    return $0.startDayKey < $1.startDayKey
                }

            var laneEndColumns: [Int] = []

            for event in overlappingEvents {
                let weekKeys = weekDates.map(DayKey.key(for:))
                let segmentStartKey = max(event.startDayKey, weekStartKey)
                let segmentEndKey = min(event.endDayKey, weekEndKey)

                guard let startColumn = weekKeys.firstIndex(of: segmentStartKey),
                      let endColumn = weekKeys.firstIndex(of: segmentEndKey) else {
                    continue
                }

                let lane: Int
                if let availableLane = laneEndColumns.firstIndex(where: { $0 < startColumn }) {
                    lane = availableLane
                    laneEndColumns[availableLane] = endColumn
                } else {
                    lane = laneEndColumns.count
                    laneEndColumns.append(endColumn)
                }

                guard lane < maxLanes else { continue }

                let monthStartKey = DayKey.key(for: DayKey.startOfMonth(for: visibleMonth))
                let nextMonthStartKey = DayKey.key(for: DayKey.addingMonths(1, to: DayKey.startOfMonth(for: visibleMonth)))
                let isDimmed = segmentEndKey < monthStartKey || segmentStartKey >= nextMonthStartKey

                segments.append(CalendarEventSegment(
                    event: event,
                    weekIndex: weekIndex,
                    startColumn: startColumn,
                    span: endColumn - startColumn + 1,
                    lane: lane,
                    isDimmed: isDimmed
                ))
            }
        }

        return segments
    }
}

struct CalendarEventSegment: Identifiable {
    var event: CalendarEvent
    var weekIndex: Int
    var startColumn: Int
    var span: Int
    var lane: Int
    var isDimmed: Bool

    var id: String {
        "\(event.id.uuidString)-\(weekIndex)-\(lane)"
    }
}

struct CalendarEventSegmentButton: View {
    var segment: CalendarEventSegment
    var isDisabled: Bool
    var width: CGFloat
    var height: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var onEdit: (CalendarEvent) -> Void
    var onDelete: (CalendarEvent) -> Void

    var body: some View {
        Button {
            onEdit(segment.event)
        } label: {
            EventSpanBar(event: segment.event, isDimmed: segment.isDimmed)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDisabled)
        .frame(width: width, height: height)
        .offset(x: xOffset, y: yOffset)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(segment.event)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

struct AddEventSheet: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var color: String
    var onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

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

            HStack {
                Spacer()
                Button("취소") {
                    dismiss()
                }
                Button {
                    onAdd()
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
    var onDelete: (CalendarEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draftTitle: String
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date
    @State private var draftColor: String

    init(
        event: CalendarEvent,
        onDelete: @escaping (CalendarEvent) -> Void
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

            HStack {
                Button(role: .destructive) {
                    onDelete(event)
                    dismiss()
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
        let normalizedStart = min(draftStartDate, draftEndDate)
        let normalizedEnd = max(draftStartDate, draftEndDate)

        event.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startAt = normalizedStart
        event.endAt = normalizedEnd
        event.startDayKey = DayKey.key(for: normalizedStart)
        event.endDayKey = DayKey.key(for: normalizedEnd)
        event.color = draftColor
        event.updatedAt = Date()
        dismiss()
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

struct TemplatePlacementSheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var onSelect: (TaskTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedScope: TemplateListScope = .favorites

    private var visibleTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(
            templates,
            items: items,
            query: searchText,
            scope: selectedScope
        )
    }

    private var emptyTemplateTitle: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "즐겨찾기한 템플릿 없음"
        }
        return "검색 결과 없음"
    }

    private var emptyTemplateMessage: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "전체보기에서 자주 쓰는 템플릿에 별표를 눌러 추가하세요."
        }
        return "템플릿 이름이나 포함된 작업명으로 다시 검색해보세요."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("템플릿 배치")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

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

            TemplateScopePicker(scope: $selectedScope)

            TemplateSearchField(text: $searchText)

            if templates.isEmpty {
                EmptySheetState(
                    symbol: "square.grid.3x3",
                    title: "저장된 템플릿 없음",
                    message: "칸반보드에서 현재 작업을 템플릿으로 저장하면 사용할 수 있습니다."
                )
            } else if visibleTemplates.isEmpty {
                EmptySheetState(
                    symbol: selectedScope == .favorites ? "star" : "magnifyingglass",
                    title: emptyTemplateTitle,
                    message: emptyTemplateMessage
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            TemplatePlacementRow(
                                template: template,
                                items: itemsForTemplate(template),
                                onSelect: {
                                    onSelect(template)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 480)
        .background(AppTheme.panel)
        .onAppear {
            selectedScope = TemplateListRules.preferredScope(for: templates)
        }
    }

    private func itemsForTemplate(_ template: TaskTemplate) -> [TaskTemplateItem] {
        TemplateListRules.itemsForTemplate(template, in: items)
    }
}

struct TemplatePlacementRow: View {
    @Bindable var template: TaskTemplate
    var items: [TaskTemplateItem]
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                template.isFavorite.toggle()
                template.updatedAt = Date()
            } label: {
                Image(systemName: template.isFavorite ? "star.fill" : "star")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(template.isFavorite ? Color.yellow : AppTheme.secondaryText)
            .help(template.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                }

                if items.isEmpty {
                    Text("비어 있는 템플릿")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text(items.prefix(4).map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            Button("선택") {
                onSelect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(items.isEmpty)
        }
        .padding(12)
        .background(AppTheme.columnTodo, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct MonthDayCell: View {
    var date: Date
    var visibleMonth: Date
    var selectedDate: Date
    var placementMode: Bool
    var isPlacementSelected: Bool
    var specialDays: [SpecialDay]
    var onSelect: () -> Void
    var onAddEvent: () -> Void

    @State private var isHovered = false

    private var isCurrentMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var isSelected: Bool {
        DayKey.key(for: date) == DayKey.key(for: selectedDate)
    }

    private var primarySpecialDay: SpecialDay? {
        specialDays.first
    }

    private var hasPublicHoliday: Bool {
        specialDays.contains { $0.isPublicHoliday }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(DayKey.dayNumber(date))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(dayForeground)
                        .frame(width: 24, height: 24)
                        .background(dayBackground, in: Circle())

                    if let primarySpecialDay {
                        Text(primarySpecialDay.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(specialDayForeground(primarySpecialDay))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if specialDays.count > 1 {
                            Text("+\(specialDays.count - 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.columnTodo, in: Capsule())
                        }
                    }

                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cellBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
            }
            .overlay {
                if isPlacementSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.event, lineWidth: 2)
                        .padding(2)
                }
            }

            if isHovered, !placementMode {
                Button {
                    onAddEvent()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(AppTheme.eventText)
                        .background(AppTheme.event, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("이 날짜에 이벤트 추가")
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var cellBackground: Color {
        if isPlacementSelected {
            return AppTheme.selectedTab
        }
        if isSelected, !placementMode {
            return AppTheme.selectedTab
        }
        return isCurrentMonth ? AppTheme.panel : AppTheme.columnTodo
    }

    private var dayBackground: Color {
        if isPlacementSelected || (!placementMode && isSelected) || DayKey.isToday(date) {
            return AppTheme.event
        }
        return Color.clear
    }

    private var dayForeground: Color {
        if isPlacementSelected || (!placementMode && isSelected) || DayKey.isToday(date) {
            return AppTheme.eventText
        }
        if hasPublicHoliday, isCurrentMonth {
            return Color(red: 0.98, green: 0.40, blue: 0.42)
        }
        return isCurrentMonth ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.45)
    }

    private func specialDayForeground(_ specialDay: SpecialDay) -> Color {
        if !isCurrentMonth {
            return AppTheme.secondaryText.opacity(0.40)
        }

        if specialDay.isPublicHoliday {
            return Color(red: 0.98, green: 0.40, blue: 0.42)
        }

        return AppTheme.secondaryText
    }
}

struct EventSpanBar: View {
    var event: CalendarEvent
    var isDimmed: Bool

    var body: some View {
        Text(event.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.eventText)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalendarEventPalette.color(for: event.color).opacity(isDimmed ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 3))
    }
}

extension View {
    func calendarToolbarButtonBackground(isPrimary: Bool = false) -> some View {
        self
            .foregroundStyle(AppTheme.primaryText)
            .background(
                isPrimary ? AppTheme.selectedTab : AppTheme.panel,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}
