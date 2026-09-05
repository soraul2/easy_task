#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileTemplateLibrarySheet: View {
    private static let messageAnchor = "template-library-message-anchor"

    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var selectedDate: Date
    var existingTasks: [TodoTask]
    var onApplied: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites
    @State private var message: String?
    @State private var messageTone: MobileNoticeTone = .information
    @State private var canRetrySave = false
    @State private var pendingTemplate: TaskTemplate?
    @State private var pendingDeleteTemplate: TaskTemplate?
    @State private var templateName = ""
    @State private var templateDrafts: [TemplateTaskDraft] = []
    @State private var initialTemplateDrafts: [TemplateTaskDraft] = []
    @State private var didLoadCurrentBoardDrafts = false
    @State private var showsDiscardConfirmation = false
    @State private var showsReloadConfirmation = false
    @FocusState private var focusedField: MobileTemplateEditorField?

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(
            templates, items: items, query: searchText, scope: scope)
    }

    private var currentBoardTasks: [TodoTask] {
        let dayKey = DayKey.key(for: selectedDate)
        return
            existingTasks
            .filter {
                $0.supersededAt == nil && $0.archivedAt == nil && $0.plannedDayKey == dayKey
            }
            .sorted { $0.order < $1.order }
    }

    private var validTemplateDrafts: [TemplateTaskDraft] {
        templateDrafts.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasUnsavedChanges: Bool {
        !templateName.isEmpty || templateDrafts != initialTemplateDrafts
    }

    private var isConfirmingTemplateApply: Binding<Bool> {
        Binding(
            get: { pendingTemplate != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTemplate = nil
                }
            }
        )
    }

    private var emptyTitle: String {
        if templates.isEmpty { return "템플릿 없음" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "검색 결과 없음"
        }
        return "즐겨찾기 템플릿 없음"
    }

    private var emptyDescription: Text {
        if templates.isEmpty { return Text("반복할 작업 묶음을 템플릿으로 저장하면 여기에서 적용할 수 있어요.") }
        if scope == .favorites { return Text("전체보기로 전환하면 모든 템플릿을 볼 수 있어요.") }
        return Text("다른 검색어로 다시 시도하세요.")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                List {
                    Section("현재 보드 저장") {
                        if currentBoardTasks.isEmpty {
                            ContentUnavailableView("저장할 작업 없음", systemImage: "checklist")
                                .listRowBackground(Color.clear)
                        } else {
                            TextField("템플릿 이름", text: $templateName)
                                .focused($focusedField, equals: .name)
                                .accessibilityIdentifier("template-draft-name")

                            ForEach($templateDrafts) { $draft in
                                MobileTemplateDraftEditRow(
                                    draft: $draft,
                                    focusedField: $focusedField,
                                    onRemove: removeTemplateDraft
                                )
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    reloadButton
                                    Spacer()
                                    saveButton
                                }
                                VStack(alignment: .leading, spacing: 12) {
                                    reloadButton
                                    saveButton
                                }
                            }
                        }
                    }
                    .listRowBackground(AppTheme.panel)

                    Section {
                        TextField("템플릿 검색", text: $searchText)
                            .focused($focusedField, equals: .search)
                        Picker("보기", selection: $scope) {
                            ForEach(TemplateListScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .planBaseAdaptiveSegmentedPicker()
                        if let message {
                            VStack(alignment: .leading, spacing: 10) {
                                MobileNoticeBanner(message: message, tone: messageTone)
                                    .accessibilityIdentifier("template-library-notice")
                                if canRetrySave {
                                    Button("다시 시도", action: saveCurrentBoardTemplate)
                                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                                        .accessibilityIdentifier("template-save-retry")
                                }
                            }
                            .id(Self.messageAnchor)
                        }
                    }
                    .listRowBackground(AppTheme.panel)

                    ForEach(filteredTemplates) { template in
                        let templateItems = TemplateListRules.itemsForTemplate(
                            template, in: items)
                        HStack(spacing: 10) {
                            Button {
                                toggleFavorite(template)
                            } label: {
                                Image(systemName: template.isFavorite ? "star.fill" : "star")
                                    .font(.headline)
                                    .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                                    .frame(
                                        width: PlanBaseControlMetrics.minimumTargetSize,
                                        height: PlanBaseControlMetrics.minimumTargetSize
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(template.isFavorite ? "즐겨찾기 제거" : "즐겨찾기 추가")

                            Button {
                                requestApply(template, items: templateItems)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(template.name)
                                        .font(.headline)
                                    Text(
                                        templateItems.map(\.title).prefix(3).joined(
                                            separator: " · ")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(AppTheme.panel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteTemplate = template
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                    if filteredTemplates.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "square.on.square",
                            description: emptyDescription
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.accent)
                .navigationTitle("템플릿")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기", action: requestDismiss)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("키보드 닫기") { focusedField = nil }
                            .accessibilityIdentifier("template-editor-keyboard-dismiss")
                    }
                }
                .onAppear {
                    scope = TemplateListRules.preferredScope(for: templates)
                    if !didLoadCurrentBoardDrafts {
                        loadCurrentBoardDrafts()
                    }
                }
                .alert("현재 보드를 다시 불러올까요?", isPresented: $showsReloadConfirmation) {
                    Button("다시 불러오기", role: .destructive, action: loadCurrentBoardDrafts)
                    Button("계속 작성", role: .cancel) {}
                } message: {
                    Text("수정하거나 제외한 작업 목록이 현재 보드 내용으로 바뀝니다. 템플릿 이름은 유지됩니다.")
                }
                .onChange(of: searchText) {
                    clearMessage()
                }
                .onChange(of: scope) {
                    clearMessage()
                }
                .onChange(of: message) { _, newValue in
                    guard newValue != nil else { return }
                    Swift.Task { @MainActor in
                        await Swift.Task.yield()
                        withAnimation {
                            scrollProxy.scrollTo(Self.messageAnchor, anchor: .center)
                        }
                    }
                }
                .alert(
                    "템플릿을 적용할까요?",
                    isPresented: isConfirmingTemplateApply,
                    presenting: pendingTemplate
                ) { template in
                    Button("취소", role: .cancel) {
                        pendingTemplate = nil
                    }
                    Button("적용") {
                        apply(
                            template,
                            items: TemplateListRules.itemsForTemplate(template, in: items)
                        )
                    }
                } message: { template in
                    Text("\"\(template.name)\" 템플릿을 \(DayKey.display(selectedDate))에 적용합니다.")
                }
                .alert(
                    "템플릿을 삭제할까요?",
                    isPresented: Binding(
                        get: { pendingDeleteTemplate != nil },
                        set: { isPresented in
                            if !isPresented {
                                pendingDeleteTemplate = nil
                            }
                        }
                    ), presenting: pendingDeleteTemplate
                ) { template in
                    Button("취소", role: .cancel) {
                        pendingDeleteTemplate = nil
                    }
                    Button("삭제", role: .destructive) {
                        deleteTemplate(template)
                    }
                } message: { template in
                    let count = TemplateListRules.itemsForTemplate(template, in: items).count
                    Text(
                        "\"\(template.name)\" 템플릿과 저장된 작업 \(count)개를 삭제합니다. 이미 보드에 추가된 작업은 삭제되지 않습니다."
                    )
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            onDiscard: { dismiss() }
        )
    }

    private var reloadButton: some View {
        Button {
            if templateDrafts != initialTemplateDrafts {
                showsReloadConfirmation = true
            } else {
                loadCurrentBoardDrafts()
            }
        } label: {
            Label("다시 불러오기", systemImage: "arrow.clockwise")
        }
        .buttonStyle(PlanBaseButtonStyle(.secondary))
        .accessibilityIdentifier("template-draft-reload")
    }

    private var saveButton: some View {
        Button(action: saveCurrentBoardTemplate) {
            Label("템플릿으로 저장", systemImage: "square.on.square")
        }
        .buttonStyle(PlanBaseButtonStyle(.primary))
        .disabled(
            templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || validTemplateDrafts.isEmpty
        )
        .accessibilityIdentifier("template-draft-save")
    }

    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges { showsDiscardConfirmation = true } else { dismiss() }
    }

    private func requestApply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        focusedField = nil
        let hasApplicableItem = templateItems.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard hasApplicableItem else {
            showMessage("템플릿에 적용할 작업이 없어요", tone: .information)
            return
        }

        clearMessage()
        pendingTemplate = template
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        do {
            let isFavorite = try PersistenceCommandService.perform(in: modelContext) {
                template.isFavorite.toggle()
                template.updatedAt = Date()
                return template.isFavorite
            }
            if !isFavorite && scope == .favorites {
                pendingTemplate = nil
            }
            showMessage(
                isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요",
                tone: .success
            )
        } catch {
            showMessage("즐겨찾기를 변경하지 못했어요", tone: .error)
        }
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        let name = template.name
        do {
            _ = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.deleteTemplate(
                    template,
                    items: items,
                    in: modelContext
                )
            }
            pendingDeleteTemplate = nil
            showMessage("\"\(name)\" 템플릿을 삭제했어요", tone: .success)
        } catch {
            pendingDeleteTemplate = nil
            showMessage("템플릿을 삭제하지 못했어요", tone: .error)
        }
    }

    private func loadCurrentBoardDrafts() {
        focusedField = nil
        do {
            let checklistItems = try TaskChecklistService.items(
                for: currentBoardTasks.map(\.id),
                in: modelContext
            )
            templateDrafts = TemplateService.drafts(
                from: currentBoardTasks,
                checklistItems: checklistItems
            )
            initialTemplateDrafts = templateDrafts
            didLoadCurrentBoardDrafts = true
            clearMessage()
        } catch {
            showMessage("현재 보드의 체크리스트를 불러오지 못했어요", tone: .error)
        }
    }

    private func removeTemplateDraft(_ id: UUID) {
        templateDrafts.removeAll { $0.id == id }
    }

    private func saveCurrentBoardTemplate() {
        focusedField = nil
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !validTemplateDrafts.isEmpty else { return }

        do {
            #if DEBUG
            if MobileTemplateLibraryUITestFixture.consumeSaveFailure() {
                throw NSError(domain: "PlanBase.UIFixture", code: 3)
            }
            #endif
            let template = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.saveTemplate(
                    named: name,
                    from: validTemplateDrafts,
                    in: modelContext
                )
            }
            guard template != nil else {
                showMessage("템플릿 이름과 작업을 확인해 주세요", tone: .information)
                return
            }
            templateName = ""
            loadCurrentBoardDrafts()
            scope = .all
            showMessage("\"\(name)\" 템플릿을 저장했어요", tone: .success)
        } catch {
            showMessage(
                "템플릿을 저장하지 못했어요. 작성 중인 이름과 작업은 그대로 유지됩니다.",
                tone: .error,
                canRetrySave: true
            )
        }
    }

    private func apply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        pendingTemplate = nil
        let templateName = template.name
        do {
            let createdCount = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.applyTemplate(
                    template,
                    items: templateItems,
                    selectedDate: selectedDate,
                    existingTasks: existingTasks,
                    in: modelContext
                )
            }
            guard createdCount > 0 else {
                showMessage("추가할 새 작업이 없어요", tone: .information)
                return
            }
            let notice = "\"\(templateName)\" 템플릿으로 \(createdCount)개 작업을 추가했어요"
            if hasUnsavedChanges {
                showMessage(
                    notice + ". 작성 중인 템플릿은 계속 편집할 수 있어요.",
                    tone: .success
                )
            } else {
                onApplied(notice)
                dismiss()
            }
        } catch {
            showMessage("템플릿을 적용하지 못했어요", tone: .error)
        }
    }

    private func clearMessage() {
        message = nil
        messageTone = .information
        canRetrySave = false
    }

    private func showMessage(
        _ value: String,
        tone: MobileNoticeTone,
        canRetrySave: Bool = false
    ) {
        message = value
        messageTone = tone
        self.canRetrySave = canRetrySave
    }
}

#if DEBUG
@MainActor
private enum MobileTemplateLibraryUITestFixture {
    private static var didFailSave = false

    static func consumeSaveFailure() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
            arguments.contains("--ui-testing-template-save-failure-once"),
            !didFailSave
        else { return false }
        didFailSave = true
        return true
    }
}
#endif
#endif
