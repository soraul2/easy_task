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
    @Query private var templatePlacements: [TemplatePlacement]

    @State private var visibleMonth = DayKey.startOfMonth(for: Date())
    @State private var selectedDate = DayKey.startOfDay(for: Date())
    @State private var sheet: CalendarSheet?
    @State private var placementTemplate: TaskTemplate?
    @State private var placementDrafts: [TemplateTaskDraft] = []
    @State private var placementDatesByKey: [String: Date] = [:]
    @State private var placementMessage: String?
    @State private var calendarNotice: String?
    @State private var calendarNoticeToken = UUID()
    @State private var showingTemplateApplyConfirmation = false
    @State private var showingPlacementTemplateDeleteConfirmation = false
    @State private var pendingPlacementTemplateDeletion: TaskTemplate?

    private let specialDayStore = SpecialDayStore.load()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                CalendarHeader(
                    visibleMonth: $visibleMonth,
                    selectedDate: $selectedDate,
                    showsActions: placementTemplate == nil,
                    onShowTemplates: { sheet = .templates },
                    onAddEvent: { sheet = .addEvent(selectedDate) }
                )
                if let placementTemplate {
                    CalendarTemplatePlacementStatus(
                        templateName: placementTemplate.name,
                        selectedCount: placementDatesByKey.count,
                        taskCount: validPlacementDrafts.count,
                        message: placementMessage,
                        onDelete: {
                            requestPlacementTemplateDeletion(placementTemplate)
                        }
                    )
                }
                monthGrid
            }
            .padding(.top, 4)
            .background(AppTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: MobileLayout.bottomTabClearance)
            }
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
                        .disabled(placementDatesByKey.isEmpty || validPlacementDrafts.isEmpty)
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
                    MobileCalendarDaySheet(
                        date: date,
                        events: eventsForDate(date),
                        templatePlacements: placementsForDate(date),
                        tasks: tasksForDate(date),
                        allTasks: tasks,
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
                Text("\"\(template.name)\" 템플릿의 작업 \(validPlacementDrafts.count)개를 선택한 \(placementDatesByKey.count)일에 적용합니다.")
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

    private var monthGrid: some View {
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
            let segments: [MobileCalendarEventSegment] = isPlacementMode ? [] : eventSegments(in: dates, maxLanes: maxEventLanes)

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
                                isPlacementSelected: placementDatesByKey[DayKey.key(for: date)] != nil,
                                events: isPlacementMode ? [] : eventsForDate(date),
                                templatePlacements: isPlacementMode ? [] : placementsForDate(date),
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

    private func tasksForDate(_ date: Date) -> [TodoTask] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: DayKey.key(for: date)
        )
    }

    private func eventsForDate(_ date: Date) -> [CalendarEvent] {
        CalendarEventRules.events(on: date, in: events)
    }

    private func placementsForDate(_ date: Date) -> [TemplatePlacement] {
        TemplateService.placements(on: date, in: templatePlacements)
    }

    private var validPlacementDrafts: [TemplateTaskDraft] {
        placementDrafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func eventSegments(in monthDates: [Date], maxLanes: Int) -> [MobileCalendarEventSegment] {
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
        placementDatesByKey = [:]
        placementMessage = nil
    }

    private func cancelTemplatePlacement() {
        placementTemplate = nil
        placementDrafts = []
        placementDatesByKey = [:]
        placementMessage = nil
        showingTemplateApplyConfirmation = false
        showingPlacementTemplateDeleteConfirmation = false
        pendingPlacementTemplateDeletion = nil
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
        guard !validPlacementDrafts.isEmpty else {
            placementMessage = "적용할 작업을 남겨두세요"
            return
        }
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
            drafts: validPlacementDrafts,
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

    private func requestPlacementTemplateDeletion(_ template: TaskTemplate) {
        pendingPlacementTemplateDeletion = template
        showingPlacementTemplateDeleteConfirmation = true
    }

    private func deletePlacementTemplate(_ template: TaskTemplate) {
        let templateName = template.name
        let deletedItemCount = TemplateService.deleteTemplate(
            template,
            items: templateItems,
            in: modelContext
        )
        cancelTemplatePlacement()
        showCalendarNotice("\"\(templateName)\" 템플릿과 작업 \(deletedItemCount)개를 삭제했어요")
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
    var showsActions: Bool
    var onShowTemplates: () -> Void
    var onAddEvent: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 34)
            }
            .accessibilityLabel("이전 달")

            Text(DayKey.monthTitle(visibleMonth))
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 34)
            }
            .accessibilityLabel("다음 달")

            Spacer(minLength: 0)

            if showsActions {
                HStack(spacing: 12) {
                    Button {
                        onShowTemplates()
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 34)
                    }
                    .accessibilityLabel("템플릿 배치")

                    Button {
                        onAddEvent()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 36, height: 34)
                    }
                    .accessibilityLabel("이벤트 추가")
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func moveMonth(by offset: Int) {
        let month = DayKey.startOfMonth(for: DayKey.addingMonths(offset, to: visibleMonth))
        visibleMonth = month
        selectedDate = month
    }
}

private struct CalendarWeekdayHeader: View {
    var body: some View {
        let symbols = DayKey.weekdaySymbols()

        HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                let symbol = symbols[index]

                Text(symbol)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(index == 0 ? Color(red: 0.98, green: 0.40, blue: 0.42) : AppTheme.secondaryText)
                    .background(AppTheme.panel.opacity(0.92))
                    .overlay(alignment: .trailing) {
                        if index < symbols.count - 1 {
                            Rectangle()
                                .fill(AppTheme.border)
                                .frame(width: 1)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}

private struct CalendarTemplatePlacementStatus: View {
    var templateName: String
    var selectedCount: Int
    var taskCount: Int
    var message: String?
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(AppTheme.event)
            VStack(alignment: .leading, spacing: 2) {
                Text(templateName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(message ?? "\(selectedCount)일 선택됨 · 작업 \(taskCount)개")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("선택한 템플릿 삭제")
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
    var templatePlacements: [TemplatePlacement]
    var specialDays: [SpecialDay]
    var showsTrailingDivider: Bool
    var showsBottomDivider: Bool

    private var isCurrentMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var isToday: Bool {
        DayKey.isToday(date)
    }

    private var primarySpecialDay: SpecialDay? {
        specialDays.first
    }

    private var hasPublicHoliday: Bool {
        specialDays.contains { $0.isPublicHoliday }
    }

    private var cellBackground: Color {
        if isPlacementSelected { return AppTheme.event.opacity(0.16) }
        if isSelected { return AppTheme.selectedTab.opacity(0.32) }
        if !isCurrentMonth { return AppTheme.input.opacity(0.38) }
        return AppTheme.panel.opacity(isToday ? 0.92 : 0.72)
    }

    private var dayBackground: Color {
        if isPlacementSelected || isSelected || isToday { return AppTheme.event }
        return Color.clear
    }

    private var dayForeground: Color {
        if isPlacementSelected || isSelected || isToday { return AppTheme.eventText }
        if hasPublicHoliday, isCurrentMonth { return Color(red: 0.98, green: 0.40, blue: 0.42) }
        return isCurrentMonth ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.45)
    }

    private var accessibilityLabel: String {
        var parts = [DayKey.display(date)]
        if isSelected { parts.append("선택됨") }
        if isPlacementSelected { parts.append("배치 선택됨") }
        if let specialDay = specialDays.first { parts.append(specialDay.name) }
        if !events.isEmpty { parts.append("이벤트 \(events.count)개") }
        if !templatePlacements.isEmpty { parts.append("템플릿 배치 \(templatePlacements.count)개") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 3) {
                Text(DayKey.dayNumber(date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(dayForeground)
                    .frame(width: 18, height: 18)
                    .background(dayBackground, in: Circle())

                if let specialDay = primarySpecialDay {
                    Text(specialDay.name)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(specialDayForeground(specialDay))
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                if isPlacementSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.event)
                        .padding(.top, 2)
                } else if !templatePlacements.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "square.grid.3x3.fill")
                        if templatePlacements.count > 1 {
                            Text("\(templatePlacements.count)")
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.event)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(AppTheme.event.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .accessibilityLabel("템플릿 배치 \(templatePlacements.count)개")
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cellBackground)
        .overlay(alignment: .trailing) {
            if showsTrailingDivider {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
            }
        }
        .overlay {
            if isPlacementSelected || isSelected {
                Rectangle()
                    .strokeBorder(AppTheme.event, lineWidth: isPlacementSelected ? 2 : 1.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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

private struct MobileCalendarEventSegment: Identifiable {
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

private struct MobileCalendarEventSpanBar: View {
    var event: CalendarEvent
    var isDimmed: Bool

    var body: some View {
        Text(event.title)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(AppTheme.eventText)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                CalendarEventPalette.color(for: event.color).opacity(isDimmed ? 0.52 : 0.96),
                in: RoundedRectangle(cornerRadius: 2)
            )
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
    var allTasks: [TodoTask] = []
    var onComplete: ((String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var color: String
    @State private var showingAddConfirmation = false
    @State private var showingDeleteConfirmation = false

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

    private var linkedTaskCount: Int {
        guard let event else { return 0 }
        return allTasks.filter { $0.eventId == event.id }.count
    }

    init(
        initialDate: Date,
        event: CalendarEvent? = nil,
        allTasks: [TodoTask] = [],
        onComplete: ((String) -> Void)? = nil
    ) {
        self.initialDate = initialDate
        self.event = event
        self.allTasks = allTasks
        self.onComplete = onComplete
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
                            showingDeleteConfirmation = true
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
                            if saveEvent() {
                                dismiss()
                            }
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
                    if saveEvent() {
                        dismiss()
                    }
                }
            } message: {
                Text("\"\(trimmedTitle)\" 이벤트를 \(DayKey.display(normalizedStartDate))부터 \(DayKey.display(normalizedEndDate))까지 추가합니다.")
            }
            .alert("이벤트를 삭제할까요?", isPresented: $showingDeleteConfirmation) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                if linkedTaskCount > 0 {
                    Text("연결된 작업 \(linkedTaskCount)개의 이벤트 연결도 함께 해제됩니다.")
                } else {
                    Text("삭제한 이벤트는 되돌릴 수 없습니다.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @discardableResult
    private func saveEvent() -> Bool {
        if let event {
            let didUpdate = CalendarEventRules.update(
                event,
                title: trimmedTitle,
                startAt: startDate,
                endAt: endDate,
                note: note,
                color: color
            )
            if didUpdate {
                onComplete?("이벤트를 저장했어요")
            }
            return didUpdate
        } else if let event = CalendarEventRules.makeEvent(
            title: trimmedTitle,
            startAt: startDate,
            endAt: endDate,
            note: note,
            color: color
        ) {
            modelContext.insert(event)
            onComplete?("이벤트를 추가했어요")
            return true
        }
        return false
    }

    private func deleteEvent() {
        guard let event else { return }
        let detachedCount = CalendarEventRules.detachTasks(from: event, in: allTasks)
        modelContext.delete(event)
        if detachedCount > 0 {
            onComplete?("이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
        } else {
            onComplete?("이벤트를 삭제했어요")
        }
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
    var templatePlacements: [TemplatePlacement]
    var tasks: [TodoTask]
    var allTasks: [TodoTask]
    var onOpenBoard: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var eventEditorRoute: MobileEventEditorRoute?
    @State private var pendingDeleteEvent: CalendarEvent?
    @State private var pendingDeletePlacement: TemplatePlacement?
    @State private var showingDeleteConfirmation = false
    @State private var showingPlacementDeleteConfirmation = false
    @State private var dayNotice: String?
    @State private var dayNoticeToken = UUID()

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
                                pendingDeleteEvent = event
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("이벤트 삭제")
                        }
                    }
                }
                Section("템플릿 배치") {
                    if templatePlacements.isEmpty {
                        Text("배치 없음")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templatePlacements) { placement in
                        MobileTemplatePlacementSummaryRow(
                            placement: placement,
                            tasks: placementTasks(for: placement),
                            deleteSummary: placementDeleteSummary(for: placement),
                            onDelete: {
                                pendingDeletePlacement = placement
                                showingPlacementDeleteConfirmation = true
                            }
                        )
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
        .overlay(alignment: .bottom) {
            if let dayNotice {
                CalendarNoticeBanner(message: dayNotice)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: dayNotice)
        .alert("이벤트를 삭제할까요?", isPresented: $showingDeleteConfirmation, presenting: pendingDeleteEvent) { event in
            Button("취소", role: .cancel) {
                pendingDeleteEvent = nil
            }
            Button("삭제", role: .destructive) {
                deleteEvent(event)
            }
        } message: { event in
            let linkedCount = linkedTaskCount(for: event)
            if linkedCount > 0 {
                Text("연결된 작업 \(linkedCount)개의 이벤트 연결도 함께 해제됩니다.")
            } else {
                Text("삭제한 이벤트는 되돌릴 수 없습니다.")
            }
        }
        .alert("템플릿 배치를 삭제할까요?", isPresented: $showingPlacementDeleteConfirmation, presenting: pendingDeletePlacement) { placement in
            Button("취소", role: .cancel) {
                pendingDeletePlacement = nil
            }
            Button("작업 유지") {
                deletePlacement(placement, deleteTasks: false)
            }
            if canDeletePlacementTasks(placement) {
                Button("작업 삭제", role: .destructive) {
                    deletePlacement(placement, deleteTasks: true)
                }
            }
        } message: { placement in
            Text(placementDeleteMessage(for: placement))
        }
        .sheet(item: $eventEditorRoute) { route in
            switch route {
            case .add(let date):
                MobileEventEditorSheet(
                    initialDate: date,
                    onComplete: showDayNotice
                )
            case .edit(let event):
                MobileEventEditorSheet(
                    initialDate: event.startAt,
                    event: event,
                    allTasks: allTasks,
                    onComplete: showDayNotice
                )
            }
        }
    }

    private func linkedTaskCount(for event: CalendarEvent) -> Int {
        allTasks.filter { $0.eventId == event.id }.count
    }

    private func placementTasks(for placement: TemplatePlacement) -> [TodoTask] {
        TemplateService.tasks(for: placement, in: allTasks)
    }

    private func placementDeleteSummary(for placement: TemplatePlacement) -> TemplatePlacementDeleteSummary {
        TemplateService.deleteSummary(for: placement, in: allTasks)
    }

    private func canDeletePlacementTasks(_ placement: TemplatePlacement) -> Bool {
        placementDeleteSummary(for: placement).canDeleteTasks
    }

    private func placementDeleteMessage(for placement: TemplatePlacement) -> String {
        let summary = placementDeleteSummary(for: placement)
        if summary.canDeleteTasks {
            return "이 배치와 연결된 작업 \(summary.taskCount)개를 함께 삭제할 수 있습니다."
        }
        return "진행 중이거나 완료된 작업이 있어 작업 삭제는 사용할 수 없습니다. 작업 유지를 선택하면 배치 연결만 해제됩니다."
    }

    private func deleteEvent(_ event: CalendarEvent) {
        let detachedCount = CalendarEventRules.detachTasks(from: event, in: allTasks)
        modelContext.delete(event)
        pendingDeleteEvent = nil
        if detachedCount > 0 {
            showDayNotice("이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
        } else {
            showDayNotice("이벤트를 삭제했어요")
        }
    }

    private func deletePlacement(_ placement: TemplatePlacement, deleteTasks: Bool) {
        let placementName = placement.templateName
        guard !deleteTasks || canDeletePlacementTasks(placement) else {
            pendingDeletePlacement = nil
            showDayNotice("진행 중이거나 완료된 작업이 있어 작업 삭제를 막았어요")
            return
        }

        let affectedCount = TemplateService.deletePlacement(
            placement,
            tasks: allTasks,
            in: modelContext,
            deleteTasks: deleteTasks
        )
        pendingDeletePlacement = nil
        if deleteTasks {
            showDayNotice("\"\(placementName)\" 배치와 작업 \(affectedCount)개를 삭제했어요")
        } else {
            showDayNotice("\"\(placementName)\" 배치 연결을 작업 \(affectedCount)개에서 해제했어요")
        }
    }

    private func showDayNotice(_ message: String) {
        let token = UUID()
        dayNoticeToken = token
        dayNotice = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard dayNoticeToken == token else { return }
            dayNotice = nil
        }
    }
}

private struct MobileTemplatePlacementSummaryRow: View {
    var placement: TemplatePlacement
    var tasks: [TodoTask]
    var deleteSummary: TemplatePlacementDeleteSummary
    var onDelete: () -> Void

    private var stateSummary: String {
        if deleteSummary.canDeleteTasks {
            return "작업 \(deleteSummary.taskCount)개 · 삭제 가능"
        }
        return "작업 \(deleteSummary.taskCount)개 · 보호 \(deleteSummary.protectedTaskCount)개"
    }

    private var taskSummary: String {
        let titles = tasks
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "연결된 작업 없음" }
        let visibleTitles = titles.prefix(3).joined(separator: " · ")
        if titles.count > 3 {
            return "\(visibleTitles) 외 \(titles.count - 3)개"
        }
        return visibleTitles
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.event)
                .frame(width: 24, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(placement.templateName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(stateSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deleteSummary.canDeleteTasks ? .secondary : AppTheme.event)
                Text(taskSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("템플릿 배치 삭제")
        }
        .padding(.vertical, 4)
    }
}

private struct MobileTemplatePlacementSheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var onStartPlacement: (TaskTemplate, [TemplateTaskDraft]) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: TaskTemplate?
    @State private var detailTemplate: TaskTemplate?
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites
    @State private var message: String?
    @State private var drafts: [TemplateTaskDraft] = []
    @State private var pendingDeleteTemplate: TaskTemplate?

    private var applicableDrafts: [TemplateTaskDraft] {
        drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

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
                                selectTemplate(template, items: templateItems)
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

                            Button(role: .destructive) {
                                pendingDeleteTemplate = template
                            } label: {
                                Image(systemName: "trash")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("템플릿 삭제")
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

                if let selectedTemplate {
                    Section("배치 준비") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTemplate.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text("적용할 작업 \(applicableDrafts.count)개")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if drafts.isEmpty {
                            ContentUnavailableView("적용할 작업 없음", systemImage: "checklist")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach($drafts) { $draft in
                                MobileTemplateDraftEditRow(
                                    draft: $draft,
                                    onRemove: removeDraft
                                )
                            }
                        }
                        if drafts.isEmpty || applicableDrafts.isEmpty {
                            Label("제목이 있는 작업을 하나 이상 남겨두세요", systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
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
                        startPlacement()
                    }
                    .disabled(selectedTemplate == nil || applicableDrafts.isEmpty)
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
                    drafts = []
                }
            }
            .alert("템플릿을 삭제할까요?", isPresented: Binding(
                get: { pendingDeleteTemplate != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteTemplate = nil
                    }
                }
            ), presenting: pendingDeleteTemplate) { template in
                Button("취소", role: .cancel) {
                    pendingDeleteTemplate = nil
                }
                Button("삭제", role: .destructive) {
                    deleteTemplate(template)
                }
            } message: { template in
                Text("\"\(template.name)\" 템플릿과 하위 작업 \(TemplateListRules.itemsForTemplate(template, in: items).count)개를 삭제합니다. 이미 생성된 작업은 삭제되지 않습니다.")
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

    private func selectTemplate(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        selectedTemplate = template
        drafts = TemplateService.drafts(from: template, items: templateItems)
        message = nil
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        template.isFavorite.toggle()
        template.updatedAt = Date()
        if selectedTemplate?.id == template.id && !template.isFavorite && scope == .favorites {
            selectedTemplate = nil
            drafts = []
        }
        message = template.isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요"
    }

    private func removeDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        message = nil
    }

    private func startPlacement() {
        guard let selectedTemplate else { return }
        guard !applicableDrafts.isEmpty else {
            message = "템플릿에 적용할 작업이 없어요"
            return
        }

        message = nil
        onStartPlacement(selectedTemplate, applicableDrafts)
        dismiss()
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        let templateName = template.name
        let deletedItemCount = TemplateService.deleteTemplate(
            template,
            items: items,
            in: modelContext
        )
        if selectedTemplate?.id == template.id {
            selectedTemplate = nil
            drafts = []
        }
        if detailTemplate?.id == template.id {
            detailTemplate = nil
        }
        pendingDeleteTemplate = nil
        message = "\"\(templateName)\" 템플릿과 작업 \(deletedItemCount)개를 삭제했어요"
    }
}

private struct MobileTemplateDraftEditRow: View {
    @Binding var draft: TemplateTaskDraft
    var onRemove: (UUID) -> Void

    private var priority: TaskPriority? {
        draft.priority.flatMap(TaskPriority.init(rawValue:))
    }

    private var tags: [String] {
        draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("작업 제목", text: $draft.title)
                    .font(.subheadline.weight(.semibold))

                Button(role: .destructive) {
                    onRemove(draft.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이번 배치에서 제외")
            }

            TextField("메모", text: $draft.note, axis: .vertical)
                .font(.caption)
                .lineLimit(1...3)

            if priority != nil || draft.estimatedMinutes != nil || !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let priority {
                            Label(priority.title, systemImage: "flag.fill")
                        }
                        if let estimatedMinutes = draft.estimatedMinutes {
                            Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                        }
                        ForEach(tags, id: \.self) { tag in
                            Label("#\(tag)", systemImage: "tag")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
