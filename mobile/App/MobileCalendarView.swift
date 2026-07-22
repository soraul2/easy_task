#if os(iOS)
import PlanBaseCore
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

private struct MobileCalendarQueryRange: Hashable {
    let startDayKey: String
    let endDayKey: String

    init(visibleMonth: Date) {
        let dates = DayKey.monthGridDates(for: visibleMonth)
        let fallbackDayKey = DayKey.key(for: visibleMonth)
        startDayKey = dates.first.map(DayKey.key(for:)) ?? fallbackDayKey
        endDayKey = dates.last.map(DayKey.key(for:)) ?? fallbackDayKey
    }
}

private struct MobileCalendarMonthQueryHost<Content: View>: View {
    @Query private var events: [CalendarEvent]
    @Query private var templatePlacements: [TemplatePlacement]
    private let content: ([CalendarEvent], [TemplatePlacement]) -> Content

    init(
        range: MobileCalendarQueryRange,
        @ViewBuilder content: @escaping ([CalendarEvent], [TemplatePlacement]) -> Content
    ) {
        _events = Query(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: range.startDayKey,
            endDayKey: range.endDayKey
        ))
        _templatePlacements = Query(BoundedQueryService.templatePlacementsDescriptor(
            from: range.startDayKey,
            through: range.endDayKey
        ))
        self.content = content
    }

    var body: some View {
        content(events, templatePlacements)
    }
}

struct MobileCalendarView: View {
    @Binding var navigationDate: Date?
    var onOpenBoardDate: (Date) -> Void
    var onShowTheme: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [TaskTemplate]
    @Query private var templateItems: [TaskTemplateItem]

    @State private var visibleMonth = DayKey.startOfMonth(for: Date())
    @State private var selectedDate = DayKey.startOfDay(for: Date())
    @State private var sheet: CalendarSheet?
    @State private var placementTemplate: TaskTemplate?
    @State private var placementDrafts: [TemplateTaskDraft] = []
    @State private var placementDayKeys: Set<String> = []
    @State private var placementMessage: String?
    @State private var calendarNotice: String?
    @State private var calendarNoticeToken = UUID()
    @State private var showingTemplateApplyConfirmation = false
    @State private var showingPlacementTemplateDeleteConfirmation = false
    @State private var pendingPlacementTemplateDeletion: TaskTemplate?

    private let specialDayStore = SpecialDayStore.load()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let queryRange = MobileCalendarQueryRange(visibleMonth: visibleMonth)

        MobileCalendarMonthQueryHost(range: queryRange) { events, templatePlacements in
            calendarContent(events: events, templatePlacements: templatePlacements)
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
        NavigationStack {
            VStack(spacing: 6) {
                CalendarHeader(
                    visibleMonth: $visibleMonth,
                    selectedDate: $selectedDate,
                    showsActions: placementTemplate == nil,
                    onShowTheme: onShowTheme,
                    onShowTemplates: { sheet = .templates },
                    onAddEvent: { sheet = .addEvent(selectedDate) }
                )
                if let placementTemplate {
                    CalendarTemplatePlacementStatus(
                        templateName: placementTemplate.name,
                        selectedCount: placementDayKeys.count,
                        taskCount: validPlacementDrafts.count,
                        message: placementMessage,
                        onDelete: {
                            requestPlacementTemplateDeletion(placementTemplate)
                        }
                    )
                }
                monthGrid(events: events, templatePlacements: templatePlacements)
            }
            .padding(.top, 4)
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
            .navigationTitle(placementTemplate == nil ? "" : "날짜 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if placementTemplate != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            cancelTemplatePlacement()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("적용") {
                            requestTemplatePlacementConfirmation()
                        }
                        .disabled(placementDayKeys.isEmpty || validPlacementDrafts.isEmpty)
                    }
                }
            }
            .toolbar(placementTemplate == nil ? .hidden : .visible, for: .navigationBar)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .addEvent(let date):
                    MobileEventEditorSheet(
                        initialDate: date,
                        onComplete: showCalendarNotice
                    )
                case .day(let date):
                    let dayKey = DayKey.key(for: date)
                    MobileCalendarDayQueryHost(
                        dayKey: dayKey,
                        date: date,
                        events: eventsForDate(date, in: events),
                        templatePlacements: placementsForDate(date, in: templatePlacements),
                        onOpenBoard: {
                            onOpenBoardDate(date)
                        }
                    )
                    .id(dayKey)
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
                Text("\"\(template.name)\" 템플릿의 작업 \(validPlacementDrafts.count)개를 선택한 \(placementDayKeys.count)일에 적용합니다.")
            }
            .alert("템플릿을 삭제할까요?", isPresented: $showingPlacementTemplateDeleteConfirmation, presenting: pendingPlacementTemplateDeletion) { template in
                Button("취소", role: .cancel) {
                    pendingPlacementTemplateDeletion = nil
                }
                Button("삭제", role: .destructive) {
                    deletePlacementTemplate(template)
                }
            } message: { template in
                Text("\"\(template.name)\" 템플릿과 하위 작업 \(TemplateListRules.itemsForTemplate(template, in: templateItems).count)개를 삭제합니다. 이미 생성된 작업은 삭제되지 않습니다.")
            }
        }
    }

    private func monthGrid(
        events: [CalendarEvent],
        templatePlacements: [TemplatePlacement]
    ) -> some View {
        GeometryReader { proxy in
            let dates = DayKey.monthGridDates(for: visibleMonth)
            let isPlacementMode = placementTemplate != nil
            let headerHeight: CGFloat = 30
            let gridHeight = max(proxy.size.height - headerHeight, 324)
            let cellHeight = gridHeight / 6
            let cellWidth = proxy.size.width / 7
            let eventTopInset = min(max(cellHeight * 0.30, 24), 32)
            let laneHeight: CGFloat = 18
            let barHeight: CGFloat = 16
            let maxEventLanes = max(1, min(3, Int((cellHeight - eventTopInset - 6) / laneHeight)))
            let segments: [MobileCalendarEventSegment] = isPlacementMode ? [] : eventSegments(
                in: dates,
                events: events,
                maxLanes: maxEventLanes
            )

            VStack(spacing: 0) {
                CalendarWeekdayHeader()
                    .frame(height: headerHeight)

                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                            MobileMonthDayCell(
                                date: date,
                                visibleMonth: visibleMonth,
                                isSelected: DayKey.key(for: date) == DayKey.key(for: selectedDate),
                                isPlacementSelected: placementDayKeys.contains(DayKey.key(for: date)),
                                events: isPlacementMode ? [] : eventsForDate(date, in: events),
                                templatePlacements: isPlacementMode ? [] : placementsForDate(date, in: templatePlacements),
                                specialDays: specialDayStore.days(on: date),
                                showsTrailingDivider: (index + 1) % 7 != 0,
                                showsBottomDivider: index < 35
                            )
                            .frame(height: cellHeight)
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

                    ForEach(segments) { segment in
                        MobileCalendarEventSpanBar(
                            event: segment.event,
                            isDimmed: segment.isDimmed
                        )
                        .frame(width: max(cellWidth * CGFloat(segment.span), 24), height: barHeight)
                        .offset(
                            x: cellWidth * CGFloat(segment.startColumn),
                            y: CGFloat(segment.weekIndex) * cellHeight + eventTopInset + CGFloat(segment.lane) * laneHeight
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: gridHeight)
            }
            .frame(height: headerHeight + gridHeight)
            .clipShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func eventsForDate(_ date: Date, in events: [CalendarEvent]) -> [CalendarEvent] {
        CalendarEventRules.events(on: date, in: events)
    }

    private func placementsForDate(
        _ date: Date,
        in templatePlacements: [TemplatePlacement]
    ) -> [TemplatePlacement] {
        TemplateService.placements(on: date, in: templatePlacements)
    }

    private var validPlacementDrafts: [TemplateTaskDraft] {
        placementDrafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func eventSegments(
        in monthDates: [Date],
        events: [CalendarEvent],
        maxLanes: Int
    ) -> [MobileCalendarEventSegment] {
        let weeks = stride(from: 0, to: monthDates.count, by: 7).map {
            Array(monthDates[$0..<min($0 + 7, monthDates.count)])
        }
        let monthStartKey = DayKey.key(for: DayKey.startOfMonth(for: visibleMonth))
        let nextMonthStartKey = DayKey.key(for: DayKey.addingMonths(1, to: DayKey.startOfMonth(for: visibleMonth)))
        var segments: [MobileCalendarEventSegment] = []

        for (weekIndex, weekDates) in weeks.enumerated() {
            guard let weekStart = weekDates.first, let weekEnd = weekDates.last else { continue }
            let weekStartKey = DayKey.key(for: weekStart)
            let weekEndKey = DayKey.key(for: weekEnd)
            let weekKeys = weekDates.map(DayKey.key(for:))
            let overlappingEvents = CalendarEventRules.events(
                overlapping: weekStart,
                through: weekEnd,
                in: events
            )

            var laneEndColumns: [Int] = []

            for event in overlappingEvents {
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

                segments.append(MobileCalendarEventSegment(
                    event: event,
                    weekIndex: weekIndex,
                    startColumn: startColumn,
                    span: endColumn - startColumn + 1,
                    lane: lane,
                    isDimmed: segmentEndKey < monthStartKey || segmentStartKey >= nextMonthStartKey
                ))
            }
        }

        return segments
    }

    private func startTemplatePlacement(_ template: TaskTemplate, drafts: [TemplateTaskDraft]) {
        placementTemplate = template
        placementDrafts = drafts
        placementDayKeys = []
        placementMessage = nil
    }

    private func cancelTemplatePlacement() {
        placementTemplate = nil
        placementDrafts = []
        placementDayKeys = []
        placementMessage = nil
        showingTemplateApplyConfirmation = false
        showingPlacementTemplateDeleteConfirmation = false
        pendingPlacementTemplateDeletion = nil
    }

    private func togglePlacementDate(_ date: Date) {
        let key = DayKey.key(for: date)
        if placementDayKeys.contains(key) {
            placementDayKeys.remove(key)
        } else {
            placementDayKeys.insert(key)
        }
        placementMessage = nil
    }

    private func requestTemplatePlacementConfirmation() {
        guard placementTemplate != nil else { return }
        guard !validPlacementDrafts.isEmpty else {
            placementMessage = "적용할 작업을 남겨두세요"
            return
        }
        guard !placementDayKeys.isEmpty else {
            placementMessage = "날짜를 선택하세요"
            return
        }
        showingTemplateApplyConfirmation = true
    }

    private func applyTemplatePlacement() {
        guard let placementTemplate else { return }
        do {
            let createdCount = try PersistenceCommandService.perform(in: modelContext) {
                let existingTasks = try placementDayKeys.sorted().flatMap { dayKey in
                    try BoundedQueryService.tasks(
                        from: dayKey,
                        through: dayKey,
                        in: modelContext
                    )
                }
                return TemplateService.applyTemplate(
                    placementTemplate,
                    drafts: validPlacementDrafts,
                    selectedDates: placementDayKeys.sorted().compactMap(DayKey.date(from:)),
                    existingTasks: existingTasks,
                    in: modelContext
                )
            }
            guard createdCount > 0 else {
                placementMessage = "추가할 새 작업이 없어요"
                return
            }

            let selectedDayCount = placementDayKeys.count
            cancelTemplatePlacement()
            showCalendarNotice("\"\(placementTemplate.name)\" 템플릿으로 \(createdCount)개 작업을 \(selectedDayCount)일에 배치했어요")
        } catch {
            placementMessage = "템플릿을 적용하지 못했어요"
        }
    }

    private func requestPlacementTemplateDeletion(_ template: TaskTemplate) {
        pendingPlacementTemplateDeletion = template
        showingPlacementTemplateDeleteConfirmation = true
    }

    private func deletePlacementTemplate(_ template: TaskTemplate) {
        let templateName = template.name
        do {
            let deletedItemCount = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.deleteTemplate(
                    template,
                    items: templateItems,
                    in: modelContext
                )
            }
            cancelTemplatePlacement()
            showCalendarNotice("\"\(templateName)\" 템플릿과 작업 \(deletedItemCount)개를 삭제했어요")
        } catch {
            placementMessage = "템플릿을 삭제하지 못했어요"
        }
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

    private func consumeNavigationDateIfNeeded() {
        guard let navigationDate else { return }
        let date = DayKey.startOfDay(for: navigationDate)
        if placementTemplate != nil {
            cancelTemplatePlacement()
        }
        visibleMonth = DayKey.startOfMonth(for: date)
        selectedDate = date
        sheet = .day(date)
        self.navigationDate = nil
    }
}
#endif
