import SwiftData
import SwiftUI
import PlanBaseCore

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

private struct DesktopCalendarQueryRange: Hashable {
    let startDayKey: String
    let endDayKey: String

    init(visibleMonth: Date) {
        let dates = DayKey.monthGridDates(for: visibleMonth)
        let fallbackDayKey = DayKey.key(for: visibleMonth)
        startDayKey = dates.first.map(DayKey.key(for:)) ?? fallbackDayKey
        endDayKey = dates.last.map(DayKey.key(for:)) ?? fallbackDayKey
    }
}

private struct DesktopCalendarEventsQueryHost<Content: View>: View {
    @Query private var events: [CalendarEvent]
    private let content: ([CalendarEvent]) -> Content

    init(
        range: DesktopCalendarQueryRange,
        @ViewBuilder content: @escaping ([CalendarEvent]) -> Content
    ) {
        _events = Query(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: range.startDayKey,
            endDayKey: range.endDayKey
        ))
        self.content = content
    }

    var body: some View {
        content(events)
    }
}

struct CalendarView: View {
    private static let specialDayStore = SpecialDayStore.load()

    @Environment(\.modelContext) private var modelContext
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
    @State private var placementDayKeys: Set<String> = []
    @State private var calendarMessage: String?

    private var monthDates: [Date] { DayKey.monthGridDates(for: visibleMonth) }
    private var isPlacementMode: Bool { placementTemplate != nil }

    private var selectedPlacementDates: [Date] {
        placementDayKeys.sorted().compactMap(DayKey.date(from:))
    }

    var body: some View {
        let queryRange = DesktopCalendarQueryRange(visibleMonth: visibleMonth)

        DesktopCalendarEventsQueryHost(range: queryRange) { events in
            calendarContent(events: events)
        }
        .id(queryRange)
    }

    private func calendarContent(events: [CalendarEvent]) -> some View {
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

            monthGrid(events: events)
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
                    onAdd: addEvent
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
                if let event = events.first(where: { $0.supersededAt == nil && $0.id == eventID }) {
                    EventEditorSheet(
                        event: event,
                        onDelete: removeEvent
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
        .alert("저장 실패", isPresented: Binding(
            get: { calendarMessage != nil },
            set: { isPresented in
                if !isPresented {
                    calendarMessage = nil
                }
            }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(calendarMessage ?? "")
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

            Text("\(placementDayKeys.count)일 선택")
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
            .disabled(placementDayKeys.isEmpty)
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

    private func monthGrid(events: [CalendarEvent]) -> some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 7
            let cellHeight = max((proxy.size.height - 5) / 6, 54)
            let eventTopInset = min(max(cellHeight * 0.34, 28), 38)
            let laneHeight: CGFloat = cellHeight < 76 ? 18 : 21
            let barHeight: CGFloat = cellHeight < 76 ? 16 : 18
            let maxEventLanes = max(1, min(4, Int((cellHeight - eventTopInset - 6) / laneHeight)))
            let segments = eventSegments(events: events, maxLanes: maxEventLanes)

            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(monthDates, id: \.self) { date in
                        MonthDayCell(
                            date: date,
                            visibleMonth: visibleMonth,
                            selectedDate: selectedDate,
                            placementMode: isPlacementMode,
                            isPlacementSelected: placementDayKeys.contains(DayKey.key(for: date)),
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
                        onDelete: { event in
                            if let failureMessage = removeEvent(event) {
                                calendarMessage = failureMessage
                            }
                        }
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

    private func addEvent() -> String? {
        guard let event = CalendarEventRules.makeEvent(
            title: title,
            startAt: startDate,
            endAt: endDate,
            color: selectedEventColor
        ) else {
            return "이벤트 정보를 확인해 주세요."
        }

        do {
            try PersistenceCommandService.perform(in: modelContext) {
                modelContext.insert(event)
            }
        } catch {
            return "이벤트를 추가하지 못했어요."
        }

        title = ""
        selectedEventColor = CalendarEventPalette.defaultColor
        return nil
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

    private func removeEvent(_ event: CalendarEvent) -> String? {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let linkedTasks = try BoundedQueryService.tasksLinked(
                    toEventID: event.id,
                    in: modelContext
                )
                CalendarEventRules.detachTasks(from: event, in: linkedTasks)
                modelContext.delete(event)
            }
            return nil
        } catch {
            return "이벤트를 삭제하지 못했어요."
        }
    }

    private func beginPlacement(with template: TaskTemplate) {
        placementTemplate = template
        placementDayKeys = []
    }

    private func cancelPlacement() {
        placementTemplate = nil
        placementDayKeys = []
    }

    private func togglePlacementDate(_ date: Date) {
        let dayKey = DayKey.key(for: date)
        selectedDate = DayKey.date(from: dayKey) ?? DayKey.startOfDay(for: date)

        if placementDayKeys.contains(dayKey) {
            placementDayKeys.remove(dayKey)
        } else {
            placementDayKeys.insert(dayKey)
        }
    }

    private func applyTemplatePlacement() {
        guard let placementTemplate else { return }

        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let existingTasks = try placementDayKeys.sorted().flatMap { dayKey in
                    try BoundedQueryService.tasks(
                        from: dayKey,
                        through: dayKey,
                        in: modelContext
                    )
                }
                TemplateService.applyTemplate(
                    placementTemplate,
                    items: templateItems,
                    selectedDates: selectedPlacementDates,
                    existingTasks: existingTasks,
                    in: modelContext
                )
            }
            cancelPlacement()
        } catch {
            calendarMessage = "템플릿을 배치하지 못했어요."
        }
    }

    private func eventSegments(
        events: [CalendarEvent],
        maxLanes: Int = 4
    ) -> [CalendarEventSegment] {
        let weeks = stride(from: 0, to: monthDates.count, by: 7).map {
            Array(monthDates[$0..<min($0 + 7, monthDates.count)])
        }

        var segments: [CalendarEventSegment] = []

        for (weekIndex, weekDates) in weeks.enumerated() {
            guard let weekStart = weekDates.first, let weekEnd = weekDates.last else { continue }
            let weekStartKey = DayKey.key(for: weekStart)
            let weekEndKey = DayKey.key(for: weekEnd)

            let overlappingEvents = CalendarEventRules.events(
                overlapping: weekStart,
                through: weekEnd,
                in: events
            )

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
