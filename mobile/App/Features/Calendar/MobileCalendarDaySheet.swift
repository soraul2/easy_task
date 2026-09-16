#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI

struct MobileCalendarDayQueryHost: View {
    private let date: Date
    @Query private var events: [CalendarEvent]
    @Query private var templatePlacements: [TemplatePlacement]
    private let onOpenBoard: () -> Void
    private let onClose: (() -> Void)?
    @Query private var tasks: [TodoTask]

    init(
        dayKey: String,
        date: Date,
        onOpenBoard: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.date = date
        self.onOpenBoard = onOpenBoard
        self.onClose = onClose
        _events = Query(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: dayKey, endDayKey: dayKey
        ))
        _templatePlacements = Query(BoundedQueryService.templatePlacementsDescriptor(
            from: dayKey, through: dayKey
        ))
        _tasks = Query(BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey))
    }

    var body: some View {
        MobileCalendarDaySheet(
            date: date,
            events: CalendarEventRules.events(on: date, in: events),
            templatePlacements: TemplateService.placements(on: date, in: templatePlacements),
            tasks: tasks,
            onOpenBoard: onOpenBoard,
            onClose: onClose
        )
    }
}

private struct MobileCalendarDaySheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var date: Date
    var events: [CalendarEvent]
    var templatePlacements: [TemplatePlacement]
    var tasks: [TodoTask]
    var onOpenBoard: () -> Void
    var onClose: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var eventEditorRoute: MobileEventEditorRoute?
    @State private var pendingDeleteEvent: CalendarEvent?
    @State private var pendingDeletePlacement: TemplatePlacement?
    @State private var showingDeleteConfirmation = false
    @State private var showingPlacementDeleteConfirmation = false
    @State private var pendingDeleteEventLinkedTaskCount = 0
    @State private var pendingPlacementDeleteSummary: TemplatePlacementDeleteSummary?
    @State private var dayNotice: String?
    @State private var dayNoticeTone: MobileNoticeTone = .success
    @State private var dayNoticeToken = UUID()
    @State private var pendingEditorNotice: String?

    private var boardTasks: [TodoTask] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: DayKey.key(for: date)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("일정") {
                    Button {
                        eventEditorRoute = .add(date)
                    } label: {
                        Label("일정 추가", systemImage: "plus.circle")
                    }
                    if events.isEmpty {
                        Text("일정 없음")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    ForEach(events) { event in
                        eventRow(event)
                        .contextMenu {
                            Button {
                                duplicateEvent(event)
                            } label: {
                                Label("일정 복제", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) {
                                requestEventDeletion(event)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.panel)
                Section("템플릿 배치") {
                    if templatePlacements.isEmpty {
                        Text("배치 없음")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    ForEach(templatePlacements) { placement in
                        MobileTemplatePlacementSummaryQueryHost(
                            placement: placement,
                            onDelete: {
                                requestPlacementDeletion(placement)
                            }
                        )
                    }
                }
                .listRowBackground(AppTheme.panel)
                Section("작업") {
                    ForEach(boardTasks.prefix(6)) { task in
                        HStack {
                            Text(task.title)
                                .lineLimit(2)
                            Spacer()
                            Text((TaskStatus(rawValue: task.status) ?? .todo).title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    if boardTasks.count > 6 {
                        Text("외 \(boardTasks.count - 6)개 작업")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if boardTasks.isEmpty {
                        Text("작업 없음")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .listRowBackground(AppTheme.panel)
                Button {
                    if onClose == nil { dismiss() }
                    onOpenBoard()
                } label: {
                    Label("이 날짜 칸반보드 열기", systemImage: "rectangle.3.group")
                }
                .listRowBackground(AppTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.accent)
            .navigationTitle(DayKey.display(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
        .overlay(alignment: .bottom) {
            if let dayNotice {
                CalendarNoticeBanner(message: dayNotice, tone: dayNoticeTone)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: dayNotice)
        .alert("일정을 삭제할까요?", isPresented: $showingDeleteConfirmation, presenting: pendingDeleteEvent) { event in
            Button("취소", role: .cancel) {
                pendingDeleteEvent = nil
                pendingDeleteEventLinkedTaskCount = 0
            }
            Button("삭제", role: .destructive) {
                deleteEvent(event)
            }
        } message: { event in
            if pendingDeleteEventLinkedTaskCount > 0 {
                Text("연결된 작업 \(pendingDeleteEventLinkedTaskCount)개의 일정 연결도 함께 해제됩니다.")
            } else {
                Text("삭제한 일정은 되돌릴 수 없습니다.")
            }
        }
        .alert("템플릿 배치를 삭제할까요?", isPresented: $showingPlacementDeleteConfirmation, presenting: pendingDeletePlacement) { placement in
            Button("취소", role: .cancel) {
                pendingDeletePlacement = nil
                pendingPlacementDeleteSummary = nil
            }
            Button("작업 유지") {
                deletePlacement(placement, deleteTasks: false)
            }
            if pendingPlacementDeleteSummary?.canDeleteTasks == true {
                Button("작업 삭제", role: .destructive) {
                    deletePlacement(placement, deleteTasks: true)
                }
            }
        } message: { placement in
            Text(placementDeleteMessage)
        }
        .sheet(item: $eventEditorRoute, onDismiss: showPendingEditorNotice) { route in
            Group {
                switch route {
                case .add(let date):
                    MobileEventEditorSheet(
                        initialDate: date,
                        onComplete: { pendingEditorNotice = $0 }
                    )
                case .edit(let event):
                    MobileEventEditorSheet(
                        initialDate: event.startAt,
                        event: event,
                        onComplete: { pendingEditorNotice = $0 }
                    )
                case .duplicate(let event, let targetDate):
                    MobileEventEditorSheet(
                        initialDate: targetDate,
                        duplicateDraft: CalendarEventReuseRules.duplicateDraft(
                            from: event,
                            targetStartAt: targetDate
                        ),
                        onComplete: { pendingEditorNotice = $0 }
                    )
                }
            }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 0) {
            HStack(alignment: .top, spacing: 10) {
                eventSummary(event)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                    eventActions(event)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    eventActions(event)
                }
            }
        }
    }

    private func eventSummary(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .lineLimit(2)
            Text(eventDateRangeText(event))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("calendar-day-event-date-range")
                .accessibilityLabel(eventDateRangeAccessibilityLabel(event))
            if let note = event.note,
               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventActions(_ event: CalendarEvent) -> some View {
        HStack(spacing: 4) {
            Button {
                eventEditorRoute = .edit(event)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("일정 편집")

            Menu {
                Button {
                    duplicateEvent(event)
                } label: {
                    Label("일정 복제", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    requestEventDeletion(event)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(event.title) 일정 메뉴")
        }
    }

    private func eventDateRangeText(_ event: CalendarEvent) -> String {
        CalendarEventTimeline.dateRangeText(for: event)
    }

    private func eventDateRangeAccessibilityLabel(_ event: CalendarEvent) -> String {
        let start = DayKey.startOfDay(for: event.startAt)
        let end = DayKey.startOfDay(for: event.endAt)
        if start == end {
            return "일정 날짜 \(DayKey.display(start))"
        }
        return "일정 기간 \(DayKey.display(start))부터 \(DayKey.display(end))까지"
    }

    private var placementDeleteMessage: String {
        guard let summary = pendingPlacementDeleteSummary else {
            return "연결된 작업 정보를 확인하지 못했습니다."
        }
        if summary.canDeleteTasks {
            return "이 배치와 연결된 작업 \(summary.taskCount)개를 함께 삭제할 수 있습니다."
        }
        return "진행 중이거나 완료된 작업이 있어 작업 삭제는 사용할 수 없습니다. 작업 유지를 선택하면 배치 연결만 해제됩니다."
    }

    private func requestEventDeletion(_ event: CalendarEvent) {
        do {
            pendingDeleteEventLinkedTaskCount = try BoundedQueryService.tasksLinked(
                toEventID: event.id,
                in: modelContext
            ).count
            pendingDeleteEvent = event
            showingDeleteConfirmation = true
        } catch {
            showDayNotice("일정 정보를 불러오지 못했어요", tone: .error)
        }
    }

    private func duplicateEvent(_ event: CalendarEvent) {
        eventEditorRoute = .duplicate(
            event,
            DayKey.startOfDay(for: date)
        )
    }

    private func requestPlacementDeletion(_ placement: TemplatePlacement) {
        do {
            let linkedTasks = try BoundedQueryService.tasksLinked(
                toTemplatePlacementID: placement.id,
                in: modelContext
            )
            pendingPlacementDeleteSummary = TemplateService.deleteSummary(
                for: placement,
                in: linkedTasks
            )
            pendingDeletePlacement = placement
            showingPlacementDeleteConfirmation = true
        } catch {
            showDayNotice("템플릿 배치 정보를 불러오지 못했어요", tone: .error)
        }
    }

    private func deleteEvent(_ event: CalendarEvent) {
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
            pendingDeleteEvent = nil
            pendingDeleteEventLinkedTaskCount = 0
            if detachedCount > 0 {
                showDayNotice("일정을 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
            } else {
                showDayNotice("일정을 삭제했어요")
            }
        } catch {
            showDayNotice("일정을 삭제하지 못했어요", tone: .error)
        }
    }

    private func deletePlacement(_ placement: TemplatePlacement, deleteTasks: Bool) {
        let placementName = placement.templateName
        do {
            let affectedCount: Int? = try PersistenceCommandService.perform(in: modelContext) {
                let linkedTasks = try BoundedQueryService.tasksLinked(
                    toTemplatePlacementID: placement.id,
                    in: modelContext
                )
                guard !deleteTasks || TemplateService.canDeleteTasks(
                    for: placement,
                    in: linkedTasks
                ) else {
                    return nil
                }
                return try TemplateService.deletePlacement(
                    placement,
                    tasks: linkedTasks,
                    in: modelContext,
                    deleteTasks: deleteTasks
                )
            }
            pendingDeletePlacement = nil
            pendingPlacementDeleteSummary = nil
            guard let affectedCount else {
                showDayNotice("진행 중이거나 완료된 작업이 있어 작업 삭제를 막았어요", tone: .information)
                return
            }
            if deleteTasks {
                showDayNotice("\"\(placementName)\" 배치와 작업 \(affectedCount)개를 삭제했어요")
            } else {
                showDayNotice("\"\(placementName)\" 배치 연결을 작업 \(affectedCount)개에서 해제했어요")
            }
        } catch {
            showDayNotice("템플릿 배치를 삭제하지 못했어요", tone: .error)
        }
    }

    private func showPendingEditorNotice() {
        guard let message = pendingEditorNotice else { return }
        pendingEditorNotice = nil
        showDayNotice(message)
    }

    private func showDayNotice(_ message: String, tone: MobileNoticeTone = .success) {
        let token = UUID()
        dayNoticeToken = token
        dayNotice = message
        dayNoticeTone = tone

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard dayNoticeToken == token else { return }
            dayNotice = nil
        }
    }
}

private struct MobileTemplatePlacementSummaryQueryHost: View {
    var placement: TemplatePlacement
    var onDelete: () -> Void
    @Query private var linkedTasks: [TodoTask]

    init(
        placement: TemplatePlacement,
        onDelete: @escaping () -> Void
    ) {
        self.placement = placement
        self.onDelete = onDelete
        _linkedTasks = Query(
            BoundedQueryService.tasksLinkedToTemplatePlacementDescriptor(
                placementID: placement.id
            )
        )
    }

    var body: some View {
        MobileTemplatePlacementSummaryRow(
            placement: placement,
            tasks: linkedTasks,
            deleteSummary: TemplateService.deleteSummary(
                for: placement,
                in: linkedTasks
            ),
            onDelete: onDelete
        )
    }
}

private struct MobileTemplatePlacementSummaryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        placementIcon
                        Text(placement.templateName)
                            .font(.headline.weight(.bold))
                    }

                    placementDetails

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("템플릿 배치 삭제", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: PlanBaseControlMetrics.minimumTargetSize,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("calendar-template-placement-delete")
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    placementIcon

                    VStack(alignment: .leading, spacing: 4) {
                        Text(placement.templateName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                        placementDetails
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(
                                width: PlanBaseControlMetrics.minimumTargetSize,
                                height: PlanBaseControlMetrics.minimumTargetSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel("템플릿 배치 삭제")
                    .accessibilityIdentifier("calendar-template-placement-delete")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var placementIcon: some View {
        Image(systemName: "square.grid.3x3.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 24, height: 28)
            .accessibilityHidden(true)
    }

    private var placementDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stateSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    deleteSummary.canDeleteTasks
                        ? AppTheme.secondaryText
                        : AppTheme.accent
                )
            Text(taskSummary)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
    }
}
#endif
