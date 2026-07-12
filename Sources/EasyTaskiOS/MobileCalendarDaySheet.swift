#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI

struct MobileCalendarDayQueryHost: View {
    private let date: Date
    private let events: [CalendarEvent]
    private let templatePlacements: [TemplatePlacement]
    private let onOpenBoard: () -> Void
    @Query private var tasks: [TodoTask]

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
        MobileCalendarDaySheet(
            date: date,
            events: events,
            templatePlacements: templatePlacements,
            tasks: tasks,
            onOpenBoard: onOpenBoard
        )
    }
}

private struct MobileCalendarDaySheet: View {
    var date: Date
    var events: [CalendarEvent]
    var templatePlacements: [TemplatePlacement]
    var tasks: [TodoTask]
    var onOpenBoard: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var eventEditorRoute: MobileEventEditorRoute?
    @State private var pendingDeleteEvent: CalendarEvent?
    @State private var pendingDeletePlacement: TemplatePlacement?
    @State private var showingDeleteConfirmation = false
    @State private var showingPlacementDeleteConfirmation = false
    @State private var pendingDeleteEventLinkedTaskCount = 0
    @State private var pendingPlacementDeleteSummary: TemplatePlacementDeleteSummary?
    @State private var dayNotice: String?
    @State private var dayNoticeToken = UUID()

    private var boardTasks: [TodoTask] {
        BoardQueryRules.tasksForBoard(
            tasks,
            selectedDayKey: DayKey.key(for: date)
        )
    }

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
                                requestEventDeletion(event)
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
                        MobileTemplatePlacementSummaryQueryHost(
                            placement: placement,
                            onDelete: {
                                requestPlacementDeletion(placement)
                            }
                        )
                    }
                }
                Section("작업") {
                    ForEach(boardTasks.prefix(6)) { task in
                        HStack {
                            Text(task.title)
                                .lineLimit(2)
                            Spacer()
                            Text((TaskStatus(rawValue: task.status) ?? .todo).title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if boardTasks.count > 6 {
                        Text("외 \(boardTasks.count - 6)개 작업")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if boardTasks.isEmpty {
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
                pendingDeleteEventLinkedTaskCount = 0
            }
            Button("삭제", role: .destructive) {
                deleteEvent(event)
            }
        } message: { event in
            if pendingDeleteEventLinkedTaskCount > 0 {
                Text("연결된 작업 \(pendingDeleteEventLinkedTaskCount)개의 이벤트 연결도 함께 해제됩니다.")
            } else {
                Text("삭제한 이벤트는 되돌릴 수 없습니다.")
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
                    onComplete: showDayNotice
                )
            }
        }
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
            showDayNotice("이벤트 정보를 불러오지 못했어요")
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
            showDayNotice("템플릿 배치 정보를 불러오지 못했어요")
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
                showDayNotice("이벤트를 삭제하고 작업 \(detachedCount)개의 연결을 해제했어요")
            } else {
                showDayNotice("이벤트를 삭제했어요")
            }
        } catch {
            showDayNotice("이벤트를 삭제하지 못했어요")
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
                return TemplateService.deletePlacement(
                    placement,
                    tasks: linkedTasks,
                    in: modelContext,
                    deleteTasks: deleteTasks
                )
            }
            pendingDeletePlacement = nil
            pendingPlacementDeleteSummary = nil
            guard let affectedCount else {
                showDayNotice("진행 중이거나 완료된 작업이 있어 작업 삭제를 막았어요")
                return
            }
            if deleteTasks {
                showDayNotice("\"\(placementName)\" 배치와 작업 \(affectedCount)개를 삭제했어요")
            } else {
                showDayNotice("\"\(placementName)\" 배치 연결을 작업 \(affectedCount)개에서 해제했어요")
            }
        } catch {
            showDayNotice("템플릿 배치를 삭제하지 못했어요")
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
#endif
