import PlanBaseCore
import SwiftData
import SwiftUI

struct DesktopCalendarDayQueryHost: View {
    private let date: Date
    private let events: [CalendarEvent]
    private let templatePlacements: [TemplatePlacement]
    private let onOpenBoard: () -> Void
    @Query private var tasks: [Task]

    init(
        dayKey: String,
        date: Date,
        events: [CalendarEvent],
        templatePlacements: [TemplatePlacement],
        onOpenBoard: @escaping () -> Void
    ) {
        self.date = date
        self.events = events
        self.templatePlacements = templatePlacements
        self.onOpenBoard = onOpenBoard
        _tasks = Query(BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey))
    }

    var body: some View {
        DesktopCalendarDayInspector(
            date: date,
            events: events,
            templatePlacements: templatePlacements,
            tasks: tasks,
            onOpenBoard: onOpenBoard
        )
    }
}

private enum DesktopDayEventSheet: Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            "add"
        case .edit(let instanceID):
            "edit-\(instanceID.uuidString)"
        }
    }
}

private struct DesktopCalendarDayInspector: View {
    var date: Date
    var events: [CalendarEvent]
    var templatePlacements: [TemplatePlacement]
    var tasks: [Task]
    var onOpenBoard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var eventSheet: DesktopDayEventSheet?
    @State private var eventTitle = ""
    @State private var eventStartDate: Date
    @State private var eventEndDate: Date
    @State private var eventColor = CalendarEventPalette.defaultColor
    @State private var eventNote = ""
    @State private var pendingDeleteEvent: CalendarEvent?
    @State private var pendingDeleteEventLinkedTaskCount = 0
    @State private var pendingDeletePlacement: TemplatePlacement?
    @State private var pendingPlacementDeleteSummary: TemplatePlacementDeleteSummary?
    @State private var showingEventDeleteConfirmation = false
    @State private var showingPlacementDeleteConfirmation = false
    @State private var notice: String?

    init(
        date: Date,
        events: [CalendarEvent],
        templatePlacements: [TemplatePlacement],
        tasks: [Task],
        onOpenBoard: @escaping () -> Void
    ) {
        self.date = date
        self.events = events
        self.templatePlacements = templatePlacements
        self.tasks = tasks
        self.onOpenBoard = onOpenBoard
        let normalizedDate = DayKey.startOfDay(for: date)
        _eventStartDate = State(initialValue: normalizedDate)
        _eventEndDate = State(initialValue: normalizedDate)
    }

    private var boardTasks: [Task] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: DayKey.key(for: date)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(AppTheme.border)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    eventSection
                    placementSection
                    taskSection
                }
                .padding(22)
            }

            Divider()
                .overlay(AppTheme.border)

            footer
        }
        .frame(width: 620, height: 590)
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .alert(
            "이벤트를 삭제할까요?",
            isPresented: $showingEventDeleteConfirmation,
            presenting: pendingDeleteEvent
        ) { event in
            Button("취소", role: .cancel) {
                pendingDeleteEvent = nil
                pendingDeleteEventLinkedTaskCount = 0
            }
            Button("삭제", role: .destructive) {
                deleteEvent(event)
            }
        } message: { _ in
            if pendingDeleteEventLinkedTaskCount > 0 {
                Text("연결된 작업 \(pendingDeleteEventLinkedTaskCount)개의 이벤트 연결도 함께 해제됩니다.")
            } else {
                Text("삭제한 이벤트는 되돌릴 수 없습니다.")
            }
        }
        .alert(
            "템플릿 배치를 삭제할까요?",
            isPresented: $showingPlacementDeleteConfirmation,
            presenting: pendingDeletePlacement
        ) { placement in
            Button("취소", role: .cancel) {
                pendingDeletePlacement = nil
                pendingPlacementDeleteSummary = nil
            }
            Button("작업 유지") {
                deletePlacement(placement, deleteTasks: false)
            }
            if pendingPlacementDeleteSummary?.canDeleteTasks == true {
                Button("연결 작업 전체 삭제", role: .destructive) {
                    deletePlacement(placement, deleteTasks: true)
                }
            }
        } message: { _ in
            Text(placementDeleteMessage)
        }
        .sheet(item: $eventSheet) { route in
            switch route {
            case .add:
                AddEventSheet(
                    title: $eventTitle,
                    startDate: $eventStartDate,
                    endDate: $eventEndDate,
                    color: $eventColor,
                    note: $eventNote,
                    onAdd: addEvent
                )
            case .edit(let eventInstanceID):
                if let event = events.first(where: {
                    $0.supersededAt == nil && $0.instanceID == eventInstanceID
                }) {
                    EventEditorSheet(
                        event: event,
                        onDelete: deleteEventFromEditor
                    )
                } else {
                    EmptySheetState(
                        symbol: "calendar.badge.exclamationmark",
                        title: "이벤트를 찾을 수 없음",
                        message: "이미 삭제되었거나 다른 기기에서 갱신된 이벤트입니다."
                    )
                    .padding(22)
                    .frame(width: 380)
                    .background(AppTheme.panel)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DayKey.display(date))
                    .font(.title2.weight(.bold))
                Text("이벤트, 템플릿 배치, 작업을 한곳에서 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                prepareAddEvent()
            } label: {
                Label("이벤트 추가", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button("닫기") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(22)
        .background(AppTheme.panel)
    }

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("이벤트", systemImage: "calendar")

            if events.isEmpty {
                emptyRow("이벤트 없음")
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(CalendarEventPalette.color(for: event.color))
                            .frame(width: 6)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)
                            Text("\(event.startDayKey) - \(event.endDayKey)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            if let note = event.note,
                               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Button {
                            eventSheet = .edit(event.instanceID)
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("이벤트 편집")
                        .accessibilityLabel("이벤트 편집")

                        Button(role: .destructive) {
                            requestEventDeletion(event)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("이벤트 삭제")
                        .accessibilityLabel("이벤트 삭제")
                    }
                    .padding(12)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("템플릿 배치", systemImage: "square.grid.3x3")

            if templatePlacements.isEmpty {
                emptyRow("배치 없음")
            } else {
                ForEach(templatePlacements) { placement in
                    DesktopTemplatePlacementSummaryQueryHost(
                        placement: placement,
                        onDelete: {
                            requestPlacementDeletion(placement)
                        }
                    )
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("작업", systemImage: "checklist")

            if boardTasks.isEmpty {
                emptyRow("작업 없음")
            } else {
                ForEach(boardTasks.prefix(6)) { task in
                    HStack(spacing: 10) {
                        Image(systemName: (TaskStatus(rawValue: task.status) ?? .todo).systemImage)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(task.title)
                            .lineLimit(2)
                        Spacer()
                        Text((TaskStatus(rawValue: task.status) ?? .todo).title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                }

                if boardTasks.count > 6 {
                    Text("외 \(boardTasks.count - 6)개 작업")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let notice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                dismiss()
                onOpenBoard()
            } label: {
                Label("이 날짜 칸반보드 열기", systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(AppTheme.panel)
    }

    private var placementDeleteMessage: String {
        guard let summary = pendingPlacementDeleteSummary else {
            return "연결된 작업 정보를 확인하지 못했습니다."
        }
        if summary.canDeleteTasks {
            return "이 배치와 연결된 작업 \(summary.taskCount)개를 모두 삭제할 수 있습니다."
        }
        return "진행 중, 완료 또는 보관된 작업이 있어 연결 작업 삭제는 사용할 수 없습니다. 작업 유지를 선택하면 배치 연결만 해제됩니다."
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(AppTheme.primaryText)
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
    }

    private func prepareAddEvent() {
        eventTitle = ""
        eventNote = ""
        eventStartDate = DayKey.startOfDay(for: date)
        eventEndDate = DayKey.startOfDay(for: date)
        eventColor = CalendarEventPalette.defaultColor
        eventSheet = .add
    }

    private func addEvent() -> String? {
        guard let event = CalendarEventRules.makeEvent(
            title: eventTitle,
            startAt: eventStartDate,
            endAt: eventEndDate,
            note: eventNote,
            color: eventColor
        ) else {
            return "이벤트 정보를 확인해 주세요."
        }

        do {
            try PersistenceCommandService.perform(in: modelContext) {
                modelContext.insert(event)
            }
            notice = "이벤트를 추가했어요."
            return nil
        } catch {
            return "이벤트를 추가하지 못했어요."
        }
    }

    private func requestEventDeletion(_ event: CalendarEvent) {
        do {
            pendingDeleteEventLinkedTaskCount = try BoundedQueryService.tasksLinked(
                toEventID: event.id,
                in: modelContext
            ).count
            pendingDeleteEvent = event
            showingEventDeleteConfirmation = true
        } catch {
            notice = "이벤트 정보를 불러오지 못했어요."
        }
    }

    private func deleteEventFromEditor(_ event: CalendarEvent) -> String? {
        do {
            let detachedCount = try performEventDeletion(event)
            notice = detachedCount > 0
                ? "이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요."
                : "이벤트를 삭제했어요."
            return nil
        } catch {
            return "이벤트를 삭제하지 못했어요."
        }
    }

    private func deleteEvent(_ event: CalendarEvent) {
        do {
            let detachedCount = try performEventDeletion(event)
            pendingDeleteEvent = nil
            pendingDeleteEventLinkedTaskCount = 0
            notice = detachedCount > 0
                ? "이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요."
                : "이벤트를 삭제했어요."
        } catch {
            notice = "이벤트를 삭제하지 못했어요."
        }
    }

    private func performEventDeletion(_ event: CalendarEvent) throws -> Int {
        try PersistenceCommandService.perform(in: modelContext) {
            let linkedTasks = try BoundedQueryService.tasksLinked(
                toEventID: event.id,
                in: modelContext
            )
            let detachedCount = CalendarEventRules.detachTasks(from: event, in: linkedTasks)
            modelContext.delete(event)
            return detachedCount
        }
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
            notice = "템플릿 배치 정보를 불러오지 못했어요."
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
                notice = "작업 상태가 바뀌어 연결 작업 삭제를 중단했어요."
                return
            }

            notice = deleteTasks
                ? "\"\(placementName)\" 배치와 연결 작업 \(affectedCount)개를 삭제했어요."
                : "\"\(placementName)\" 배치 연결을 작업 \(affectedCount)개에서 해제했어요."
        } catch {
            notice = "템플릿 배치를 삭제하지 못했어요."
        }
    }
}

private struct DesktopTemplatePlacementSummaryQueryHost: View {
    var placement: TemplatePlacement
    var onDelete: () -> Void
    @Query private var linkedTasks: [Task]

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
        let summary = TemplateService.deleteSummary(
            for: placement,
            in: linkedTasks
        )

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(AppTheme.event)
                .frame(width: 24, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(placement.templateName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(
                    summary.canDeleteTasks
                        ? "작업 \(summary.taskCount)개 · 전체 삭제 가능"
                        : "작업 \(summary.taskCount)개 · 보호 \(summary.protectedTaskCount)개"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    summary.canDeleteTasks
                        ? AppTheme.secondaryText
                        : AppTheme.event
                )
                Text(taskSummary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("템플릿 배치 삭제")
            .accessibilityLabel("템플릿 배치 삭제")
        }
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var taskSummary: String {
        let titles = linkedTasks
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "연결된 작업 없음" }
        let visibleTitles = titles.prefix(3).joined(separator: " · ")
        return titles.count > 3
            ? "\(visibleTitles) 외 \(titles.count - 3)개"
            : visibleTitles
    }
}
