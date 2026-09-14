#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A shared library for the board and calendar: choosing a saved routine always comes first.
public struct TemplateLibraryView: View {
    private let selectedDate: Date?
    private let boardTasks: [Task]
    private let onApplied: (String) -> Void
    private let onChooseDates: ((TaskTemplate, [TemplateTaskDraft]) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<TaskTemplate> { $0.supersededAt == nil }) private var templates: [TaskTemplate]
    @Query(filter: #Predicate<TaskTemplateItem> { $0.supersededAt == nil }) private var items: [TaskTemplateItem]
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .all
    @State private var path: [UUID] = []
    @State private var editor: TemplateEditorRequest?
    @State private var notice: String?
    @State private var failure: String?
    @State private var pendingDelete: TemplateContentSnapshot?
    @State private var pendingApply: RoutineApplyRequest?
    @State private var adjustedRequest: RoutineApplyRequest?

    public init(selectedDate: Date, currentBoardTasks: [Task], onApplied: @escaping (String) -> Void) {
        self.selectedDate = selectedDate
        boardTasks = currentBoardTasks
        self.onApplied = onApplied
        onChooseDates = nil
    }

    public init(onChooseDates: @escaping (TaskTemplate, [TemplateTaskDraft]) -> Void) {
        selectedDate = nil
        boardTasks = []
        onApplied = { _ in }
        self.onChooseDates = onChooseDates
    }

    private var visibleTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
    }

    private var sourceTasks: [Task] {
        guard let selectedDate else { return [] }
        return boardTasks.filter {
            $0.supersededAt == nil && $0.archivedAt == nil && $0.plannedDayKey == DayKey.key(for: selectedDate)
        }.sorted { $0.order < $1.order }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if let selectedDate {
                        Label("\(DayKey.display(selectedDate))에 추가", systemImage: "calendar")
                            .font(.headline)
                            .accessibilityIdentifier("template-target-date")
                    } else {
                        Label("루틴을 고른 뒤 날짜를 선택하세요", systemImage: "calendar")
                            .font(.headline)
                    }
                    Text("자주 쓰는 작업 묶음을 한 번에 추가하세요.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    if !templates.isEmpty {
                        TemplateSearchField(text: $searchText)
                        TemplateScopePicker(scope: $scope)
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("전체 루틴에서 검색합니다")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .accessibilityIdentifier("template-library-notice")
                    }
                }
                .listRowBackground(AppTheme.panel)
                if templates.isEmpty {
                    Section {
                        ContentUnavailableView("첫 루틴을 만들어 보세요", systemImage: "square.on.square",
                            description: Text("아침 준비나 운동처럼 자주 하는 작업을 묶어 저장하세요."))
                        Button("직접 만들기", action: createEmpty)
                            .accessibilityIdentifier("template-create-empty")
                        if !sourceTasks.isEmpty {
                            Button("현재 보드에서 만들기", action: createFromBoard)
                                .accessibilityIdentifier("template-create-from-board")
                        }
                    }
                } else if visibleTemplates.isEmpty {
                    Section {
                        ContentUnavailableView(searchText.isEmpty ? "즐겨찾기한 루틴이 없어요" : "검색 결과가 없어요",
                            systemImage: searchText.isEmpty ? "star" : "magnifyingglass",
                            description: Text("전체 목록을 보거나 다른 검색어로 찾아보세요."))
                        Button("전체 루틴 보기") { searchText = ""; scope = .all }
                    }
                } else {
                    Section("저장한 루틴 \(visibleTemplates.count)개") {
                        ForEach(visibleTemplates) { template in
                            routineRow(template)
                        }
                    }
                    Section {
                        Text("작업 한 개짜리 루틴은 ‘저장한 작업’에서도 사용할 수 있어요. 같은 항목이므로 편집·삭제가 함께 반영됩니다.")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("템플릿")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("키보드 닫기") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("template-editor-keyboard-dismiss")
                }
                #endif
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("직접 만들기", action: createEmpty)
                        if !sourceTasks.isEmpty { Button("현재 보드에서 만들기", action: createFromBoard) }
                    } label: { Label("만들기", systemImage: "plus") }
                    .accessibilityIdentifier("template-create-menu")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let template = templates.first(where: { $0.id == id && $0.supersededAt == nil }) {
                    detail(template)
                } else {
                    ContentUnavailableView("루틴을 찾을 수 없어요", systemImage: "square.on.square")
                }
            }
        }
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.accent)
        .sheet(item: $editor, onDismiss: {
            if let request = adjustedRequest {
                adjustedRequest = nil
                requestApply(id: request.id, drafts: request.drafts)
            }
        }) { request in
            TemplateRoutineEditor(request: request, onSaved: {
                notice = $0
                searchText = ""
                scope = .all
            }, onAdjusted: { drafts in
                guard let original = request.original else { return }
                adjustedRequest = RoutineApplyRequest(id: original.id, name: original.name, drafts: drafts,
                    summary: TemplateApplicationSummary(totalCount: drafts.count, newCount: drafts.count))
            })
            .id(request.id)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .alert("추가할 작업을 선택하세요", isPresented: Binding(
            get: { pendingApply != nil }, set: { if !$0 { pendingApply = nil } }
        ), presenting: pendingApply) { request in
            if request.summary.newCount > 0 {
                Button("새 작업 \(request.summary.newCount)개만 추가") { apply(request, skipDuplicates: true) }
            }
            Button("전체 \(request.summary.totalCount)개 다시 추가") { apply(request, skipDuplicates: false) }
            Button("취소", role: .cancel) { pendingApply = nil }
        } message: { request in
            Text("\(selectedDate.map(DayKey.display) ?? "")에 같은 제목의 작업이 \(request.summary.duplicateCount)개 있어요. 기존 작업은 유지됩니다.")
        }
        .alert("루틴을 삭제할까요?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { value in
            Button("삭제", role: .destructive) { delete(value.id) }
            Button("취소", role: .cancel) {}
        } message: { value in
            Text("‘\(value.name)’ 루틴과 저장된 작업 \(value.drafts.count)개를 삭제합니다. 이미 보드에 추가된 작업은 유지됩니다." +
                 (value.drafts.count == 1 ? " ‘저장한 작업’ 목록에서도 삭제됩니다." : ""))
        }
        .alert("처리하지 못했어요", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(failure ?? "") }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 540, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
        #endif
    }

    private func routineRow(_ template: TaskTemplate) -> some View {
        let drafts = TemplateService.drafts(from: template, items: items)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink(value: template.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if template.isFavorite { Image(systemName: "star.fill").foregroundStyle(AppTheme.accent) }
                            Text(template.name).font(.headline)
                        }
                        Text("작업 \(drafts.count)개" + estimatedSummary(drafts))
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        Text(drafts.prefix(3).map(\.title).joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                }
                .accessibilityIdentifier("template-detail-\(template.name)")
            }
            if let selectedDate {
                let summary = TemplateApplicationRules.summary(drafts: drafts, dates: [selectedDate], tasks: sourceTasks)
                if summary.duplicateCount > 0 {
                    Label("같은 제목의 작업 \(summary.duplicateCount)개 있음", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            let actionLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            actionLayout {
                Menu { managementActions(template) } label: {
                    Label("관리", systemImage: "ellipsis")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("\(template.name) 관리")
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button(selectedDate == nil ? "날짜 선택" : "작업 \(drafts.count)개 추가") {
                    requestApply(id: template.id)
                }
                .buttonStyle(PlanBaseButtonStyle(.primary))
                .disabled(drafts.isEmpty)
                .accessibilityLabel("\(template.name) \(selectedDate == nil ? "날짜 선택" : "추가")")
                .accessibilityIdentifier("template-apply-\(template.name)")
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(AppTheme.panel)
    }

    private func detail(_ template: TaskTemplate) -> some View {
        let drafts = TemplateService.drafts(from: template, items: items)
        return List {
            Section {
                Text(template.name).font(.title2.bold())
                Text("작업 \(drafts.count)개" + estimatedSummary(drafts)).foregroundStyle(AppTheme.secondaryText)
                if let selectedDate {
                    Label("\(DayKey.display(selectedDate))에 추가", systemImage: "calendar")
                }
            }
            ForEach(drafts) { draft in
                Section {
                    Text(draft.title).font(.headline)
                    if !draft.note.isEmpty { Text(draft.note) }
                    if let minutes = draft.estimatedMinutes {
                        Label(EstimatedTimeFormatter.short(minutes), systemImage: "clock")
                    }
                    if let priority = draft.priority.flatMap(TaskPriority.init(rawValue:)) {
                        Label(priority.title, systemImage: "flag")
                    }
                    if !draft.tags.isEmpty { Text(draft.tags.map { "#\($0)" }.joined(separator: " ")) }
                    ForEach(Array(draft.checklistTitles.enumerated()), id: \.offset) { _, title in
                        Label(title, systemImage: "square").font(.subheadline)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("루틴 상세")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu { managementActions(template) } label: { Label("관리", systemImage: "ellipsis") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(selectedDate == nil ? "날짜 선택" : "작업 \(drafts.count)개 추가") {
                    requestApply(id: template.id)
                }
                .buttonStyle(PlanBaseButtonStyle(.primary))
                .disabled(drafts.isEmpty)
                Button("이번에만 조정") { openEditor(template.id, adjustment: true) }
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .disabled(drafts.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .padding(16).background(AppTheme.panel)
        }
    }

    @ViewBuilder private func managementActions(_ template: TaskTemplate) -> some View {
        Button("루틴 편집", systemImage: "pencil") { openEditor(template.id) }
        Button("복제", systemImage: "plus.square.on.square") { openEditor(template.id, copy: true) }
        Button(template.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가", systemImage: "star") {
            do {
                try PersistenceCommandService.perform(in: context) {
                    template.isFavorite.toggle()
                    template.updatedAt = Date()
                }
            } catch { failure = error.localizedDescription }
        }
        Divider()
        Button("삭제", systemImage: "trash", role: .destructive) {
            do { pendingDelete = try TemplateEditingService.snapshot(id: template.id, in: context) }
            catch { failure = error.localizedDescription }
        }
    }

    private func estimatedSummary(_ drafts: [TemplateTaskDraft]) -> String {
        let estimates = drafts.compactMap(\.estimatedMinutes)
        guard !estimates.isEmpty else { return "" }
        return " · \(estimates.count == drafts.count ? "예상" : "입력된 시간") \(EstimatedTimeFormatter.short(estimates.reduce(0, +)))"
    }

    private func createEmpty() {
        editor = TemplateEditorRequest(name: "", drafts: [TemplateTaskDraft(title: "", order: 100)])
    }

    private func createFromBoard() {
        do {
            let checklist = try TaskChecklistService.items(for: sourceTasks.map(\.id), in: context)
            editor = TemplateEditorRequest(name: "", drafts: TemplateService.drafts(from: sourceTasks, checklistItems: checklist))
        } catch { failure = "현재 보드의 작업을 불러오지 못했어요. " + error.localizedDescription }
    }

    private func openEditor(_ id: UUID, copy: Bool = false, adjustment: Bool = false) {
        do {
            let value = try TemplateEditingService.snapshot(id: id, in: context)
            editor = TemplateEditorRequest(original: copy ? nil : value,
                name: value.name + (copy ? " 복사본" : ""), drafts: value.drafts,
                favorite: copy ? false : value.isFavorite, adjustment: adjustment)
        } catch { failure = error.localizedDescription }
    }

    private func requestApply(id: UUID, drafts: [TemplateTaskDraft]? = nil) {
        do {
            let value = try TemplateEditingService.snapshot(id: id, in: context)
            let drafts = drafts ?? value.drafts
            guard !drafts.isEmpty else { notice = "추가할 작업이 없어요"; return }
            if let onChooseDates, let template = templates.first(where: { $0.id == id }) {
                onChooseDates(template, drafts)
                dismiss()
                return
            }
            guard let selectedDate else { return }
            let key = DayKey.key(for: selectedDate)
            let tasks = try BoundedQueryService.tasks(from: key, through: key, in: context)
            let summary = TemplateApplicationRules.summary(drafts: drafts, dates: [selectedDate], tasks: tasks)
            let request = RoutineApplyRequest(id: id, name: value.name, drafts: drafts, summary: summary)
            if summary.duplicateCount > 0 { pendingApply = request }
            else { apply(request, skipDuplicates: true) }
        } catch { failure = error.localizedDescription }
    }

    private func apply(_ request: RoutineApplyRequest, skipDuplicates: Bool) {
        pendingApply = nil
        guard let selectedDate else { return }
        do {
            _ = try TemplateEditingService.snapshot(id: request.id, in: context)
            guard let template = templates.first(where: { $0.id == request.id && $0.supersededAt == nil })
            else { throw TemplateEditingService.Failure.unavailable }
            let count = try PersistenceCommandService.perform(in: context) {
                let key = DayKey.key(for: selectedDate)
                let tasks = try BoundedQueryService.tasks(from: key, through: key, in: context)
                return TemplateService.applyTemplate(template, drafts: request.drafts,
                    selectedDates: [selectedDate], existingTasks: tasks, in: context, skipDuplicateTitles: skipDuplicates)
            }
            guard count > 0 else { notice = "같은 제목의 작업이 모두 있어요. 다시 추가하려면 루틴의 추가 버튼을 누르세요."; return }
            onApplied("\(DayKey.display(selectedDate))에 ‘\(request.name)’ 작업 \(count)개를 추가했어요")
            dismiss()
        } catch { failure = error.localizedDescription }
    }

    private func delete(_ id: UUID) {
        do {
            try TemplateEditingService.delete(id: id, in: context)
            pendingDelete = nil
            path.removeAll { $0 == id }
            notice = "루틴을 삭제했어요"
        } catch { failure = error.localizedDescription }
    }
}

private struct RoutineApplyRequest: Identifiable {
    var id: UUID
    var name: String
    var drafts: [TemplateTaskDraft]
    var summary: TemplateApplicationSummary
}
#endif
