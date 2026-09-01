import SwiftData
import SwiftUI
import PlanBaseCore

private enum CalendarSheet: Identifiable {
    case addEvent
    case duplicateEvent(UUID)
    case templatePlacement
    case editEvent(UUID)
    case day(Date)

    var id: String {
        switch self {
        case .addEvent: "addEvent"
        case .duplicateEvent(let id): "duplicateEvent-\(id.uuidString)"
        case .templatePlacement: "templatePlacement"
        case .editEvent(let id): "editEvent-\(id.uuidString)"
        case .day(let date): "day-\(DayKey.key(for: date))"
        }
    }
}


struct CalendarView: View {
    private static let specialDayStore = SpecialDayStore.load()

    @Binding var navigationDate: Date?
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var visibleMonth = DayKey.startOfMonth(for: Date())
    @State private var selectedDate = DayKey.startOfDay(for: Date())
    @State private var title = ""
    @State private var startDate = DayKey.startOfDay(for: Date())
    @State private var endDate = DayKey.startOfDay(for: Date())
    @State private var selectedEventColor = CalendarEventPalette.defaultColor
    @State private var note = ""
    @State private var presentedSheet: CalendarSheet?
    @State private var pendingAddDateAfterSheetDismissal: Date?
    @State private var placementTemplate: TaskTemplate?
    @State private var placementDayKeys: Set<String> = []
    @State private var calendarMessage: String?

    private let onOpenBoardDate: (Date) -> Void

    init(
        navigationDate: Binding<Date?> = .constant(nil),
        onOpenBoardDate: @escaping (Date) -> Void = { _ in }
    ) {
        _navigationDate = navigationDate
        self.onOpenBoardDate = onOpenBoardDate
    }

    private var monthDates: [Date] { DayKey.monthGridDates(for: visibleMonth) }
    private var isPlacementMode: Bool { placementTemplate != nil }

    private var selectedPlacementDates: [Date] {
        placementDayKeys.sorted().compactMap(DayKey.date(from:))
    }

    var body: some View {
        let queryRange = DesktopCalendarQueryRange(visibleMonth: visibleMonth)

        DesktopCalendarMonthQueryHost(range: queryRange) { events, templatePlacements in
            calendarContent(
                events: events,
                templatePlacements: templatePlacements
            )
        }
        .id(queryRange)
        .onAppear {
            consumeNavigationDateIfNeeded()
        }
        .onChange(of: navigationDate) {
            consumeNavigationDateIfNeeded()
        }
    }

    private func calendarContent(
        events: [CalendarEvent],
        templatePlacements: [TemplatePlacement]
    ) -> some View {
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
        .sheet(
            item: $presentedSheet,
            onDismiss: presentPendingAddEvent
        ) { sheet in
            switch sheet {
            case .addEvent:
                AddEventSheet(
                    title: $title,
                    startDate: $startDate,
                    endDate: $endDate,
                    color: $selectedEventColor,
                    note: $note,
                    onAdd: addEvent
                )
            case .duplicateEvent(let eventInstanceID):
                AddEventSheet(
                    title: $title,
                    startDate: $startDate,
                    endDate: $endDate,
                    color: $selectedEventColor,
                    note: $note,
                    isDuplicate: true,
                    excludingEventID: events.first {
                        $0.instanceID == eventInstanceID
                    }?.id,
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
            case .editEvent(let eventInstanceID):
                if let event = events.first(where: {
                    $0.supersededAt == nil && $0.instanceID == eventInstanceID
                }) {
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
            case .day(let date):
                DesktopCalendarDayQueryHost(
                    dayKey: DayKey.key(for: date),
                    date: date,
                    events: representativeEvents(on: date, in: events),
                    templatePlacements: TemplateService.placements(
                        on: date,
                        in: templatePlacements
                    ),
                    onOpenBoard: {
                        onOpenBoardDate(date)
                    },
                    onAddEvent: {
                        pendingAddDateAfterSheetDismissal = date
                        presentedSheet = nil
                    }
                )
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
        DesktopCalendarHeader(
            visibleMonth: $visibleMonth,
            selectedDate: $selectedDate,
            isPlacementMode: isPlacementMode,
            onMoveMonth: moveVisibleMonth,
            onToggleTemplatePlacement: {
                if isPlacementMode {
                    cancelPlacement()
                } else {
                    presentedSheet = .templatePlacement
                }
            },
            onOpenDayDetails: {
                openDayDetails(for: selectedDate)
            },
            onAddEvent: {
                prepareAddEvent(for: selectedDate)
            }
        )
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
            let activeEvents = events.filter { $0.supersededAt == nil }
            let eventsByRenderID = Dictionary(
                activeEvents.map { ($0.instanceID, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            let layout = CalendarEventGridLayout.make(
                items: activeEvents.map {
                    CalendarEventGridLayoutItem(
                        renderID: $0.instanceID,
                        eventID: $0.id,
                        title: $0.title,
                        startDayKey: $0.startDayKey,
                        endDayKey: $0.endDayKey,
                        updatedAt: $0.updatedAt
                    )
                },
                dates: monthDates,
                visibleMonth: visibleMonth,
                maximumLanes: maxEventLanes
            )

            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(monthDates, id: \.self) { date in
                        MonthDayCell(
                            date: date,
                            visibleMonth: visibleMonth,
                            selectedDate: selectedDate,
                            placementMode: isPlacementMode,
                            isPlacementSelected: placementDayKeys.contains(DayKey.key(for: date)),
                            hiddenEventCount: layout.hiddenEventCountByDayKey[DayKey.key(for: date)] ?? 0,
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
                            onOpenDetails: {
                                openDayDetails(for: date)
                            },
                            onAddEvent: {
                                prepareAddEvent(for: date)
                            }
                        )
                        .frame(height: cellHeight)
                    }
                }

                ForEach(layout.segments) { segment in
                    if let event = eventsByRenderID[segment.renderID] {
                        CalendarEventSegmentButton(
                            segment: segment,
                            event: event,
                            isDisabled: isPlacementMode,
                            width: max(cellWidth * CGFloat(segment.span) - 10, 32),
                            height: barHeight,
                            xOffset: cellWidth * CGFloat(segment.startColumn) + 5,
                            yOffset: CGFloat(segment.weekIndex) * cellHeight + eventTopInset + CGFloat(segment.lane) * laneHeight,
                            onEdit: { event in
                                presentedSheet = .editEvent(event.instanceID)
                            },
                            onDuplicate: { event in
                                prepareDuplicateEvent(event)
                            },
                            onDelete: { event in
                                if let failureMessage = removeEvent(event) {
                                    calendarMessage = failureMessage
                                }
                            }
                        )
                    }
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
        let draft = CalendarEventReuseDraft(
            title: title,
            startAt: startDate,
            endAt: endDate,
            note: note,
            color: selectedEventColor
        )
        guard let event = CalendarEventReuseRules.makeIndependentEvent(
            from: draft
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
        note = ""
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
        note = ""
        startDate = normalizedDate
        endDate = normalizedDate
        selectedEventColor = CalendarEventPalette.defaultColor
        presentedSheet = .addEvent
    }

    private func presentPendingAddEvent() {
        guard let date = pendingAddDateAfterSheetDismissal else { return }
        pendingAddDateAfterSheetDismissal = nil
        prepareAddEvent(for: date)
    }

    private func moveVisibleMonth(by offset: Int) {
        let nextMonth = DayKey.addingMonths(offset, to: visibleMonth)
        let today = DayKey.startOfDay(for: Date())
        visibleMonth = nextMonth
        selectedDate = DayKey.isSameMonth(today, nextMonth)
            ? today
            : DayKey.startOfMonth(for: nextMonth)
    }

    private func prepareDuplicateEvent(_ event: CalendarEvent) {
        let draft = CalendarEventReuseRules.duplicateDraft(
            from: event,
            targetStartAt: selectedDate
        )
        title = draft.title
        note = draft.note ?? ""
        startDate = draft.startAt
        endDate = draft.endAt
        selectedEventColor = draft.color ?? CalendarEventPalette.defaultColor
        presentedSheet = .duplicateEvent(event.instanceID)
    }

    private func openDayDetails(for date: Date) {
        guard !isPlacementMode else { return }
        let normalizedDate = DayKey.startOfDay(for: date)
        selectedDate = normalizedDate
        if !DayKey.isSameMonth(normalizedDate, visibleMonth) {
            visibleMonth = DayKey.startOfMonth(for: normalizedDate)
        }
        presentedSheet = .day(normalizedDate)
    }

    private func consumeNavigationDateIfNeeded() {
        guard let navigationDate else { return }
        let date = DayKey.startOfDay(for: navigationDate)
        if isPlacementMode {
            cancelPlacement()
        }
        pendingAddDateAfterSheetDismissal = nil
        visibleMonth = DayKey.startOfMonth(for: date)
        selectedDate = date
        presentedSheet = .day(date)
        self.navigationDate = nil
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

    private func representativeEvents(
        on date: Date,
        in events: [CalendarEvent]
    ) -> [CalendarEvent] {
        let dayEvents = CalendarEventRules.events(on: date, in: events)
        let representativeItems = CalendarEventGridLayout.representativeItems(
            from: dayEvents.map {
                CalendarEventGridLayoutItem(
                    renderID: $0.instanceID,
                    eventID: $0.id,
                    title: $0.title,
                    startDayKey: $0.startDayKey,
                    endDayKey: $0.endDayKey,
                    updatedAt: $0.updatedAt
                )
            }
        )
        let renderIDs = Set(representativeItems.map(\.renderID))
        return CalendarEventRules.sorted(
            dayEvents.filter { renderIDs.contains($0.instanceID) }
        )
    }

}
