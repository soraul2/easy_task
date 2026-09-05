#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI

struct MobileTemplatePlacementSheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var onStartPlacement: (TaskTemplate, [TemplateTaskDraft]) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTemplate: TaskTemplate?
    @State private var detailTemplate: TaskTemplate?
    @State private var searchText = ""
    @State private var scope: TemplateListScope = .favorites
    @State private var message: String?
    @State private var drafts: [TemplateTaskDraft] = []
    @State private var initialDrafts: [TemplateTaskDraft] = []
    @State private var pendingSelection: TaskTemplate?
    @State private var showsDiscardConfirmation = false
    @State private var pendingDeleteTemplate: TaskTemplate?
    @FocusState private var focusedField: MobileTemplateEditorField?

    private var applicableDrafts: [TemplateTaskDraft] {
        drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var hasUnsavedChanges: Bool { drafts != initialDrafts }

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
                        .focused($focusedField, equals: .search)
                    Picker("보기", selection: $scope) {
                        ForEach(TemplateListScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .planBaseAdaptiveSegmentedPicker()
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredTemplates) { template in
                        let templateItems = TemplateListRules.itemsForTemplate(template, in: items)
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                requestSelection(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(template.name)
                                            .font(.headline)
                                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                        if selectedTemplate?.id == template.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppTheme.accent)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                }
                                .frame(maxWidth: .infinity, minHeight: PlanBaseControlMetrics.minimumTargetSize, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(template.name)
                            .accessibilityValue(selectedTemplate?.id == template.id ? "선택됨" : "")
                            .accessibilityAddTraits(selectedTemplate?.id == template.id ? .isSelected : [])
                            .accessibilityIdentifier("template-placement-select-\(template.name)")

                            HStack(spacing: 8) {
                                Button {
                                    focusedField = nil
                                    detailTemplate = template
                                } label: {
                                    Label("상세", systemImage: "list.bullet.rectangle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(template.name) 상세 보기")

                                Spacer(minLength: 8)

                                Button {
                                    toggleFavorite(template)
                                } label: {
                                    Image(systemName: template.isFavorite ? "star.fill" : "star")
                                        .font(.headline)
                                        .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                                        .frame(width: PlanBaseControlMetrics.minimumTargetSize, height: PlanBaseControlMetrics.minimumTargetSize)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(template.name) \(template.isFavorite ? "즐겨찾기 제거" : "즐겨찾기 추가")")

                                Button(role: .destructive) {
                                    focusedField = nil
                                    pendingDeleteTemplate = template
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: PlanBaseControlMetrics.minimumTargetSize, height: PlanBaseControlMetrics.minimumTargetSize)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(template.name) 템플릿 삭제")
                            }
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
                    Section {
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
                                    focusedField: $focusedField,
                                    onRemove: removeDraft
                                )
                            }
                        }
                        if drafts.isEmpty || applicableDrafts.isEmpty {
                            Label("제목이 있는 작업을 하나 이상 남겨두세요", systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("배치 준비")
                    } footer: {
                        Text("여기서 수정한 내용은 이번 배치에만 적용되며 저장된 템플릿은 바뀌지 않아요.")
                    }
                }
            }
            .listRowBackground(AppTheme.panel)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("템플릿 배치")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: requestDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("배치") {
                        startPlacement()
                    }
                    .disabled(selectedTemplate == nil || applicableDrafts.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("키보드 닫기") { focusedField = nil }
                        .accessibilityIdentifier("template-editor-keyboard-dismiss")
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
                Text("\"\(template.name)\" 템플릿과 저장된 작업 \(TemplateListRules.itemsForTemplate(template, in: items).count)개를 삭제합니다. 이미 보드에 추가된 작업은 삭제되지 않습니다.\(selectedTemplate?.id == template.id && hasUnsavedChanges ? " 작성 중인 배치 내용도 사라집니다." : "")")
            }
        }
        .tint(AppTheme.accent)
        .presentationDetents([.large])
        .presentationBackground(AppTheme.background)
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            message: pendingSelection == nil
                ? "이번 배치를 위해 수정한 내용이 사라집니다. 저장된 템플릿은 바뀌지 않습니다."
                : "다른 템플릿을 선택하면 이번 배치를 위해 수정한 내용이 사라집니다.",
            onDiscard: {
                if let pendingSelection {
                    selectTemplate(pendingSelection)
                } else {
                    dismiss()
                }
            }
        )
        .onChange(of: showsDiscardConfirmation) { _, isPresented in
            if !isPresented { pendingSelection = nil }
        }
        .sheet(item: $detailTemplate) { template in
            MobileTemplateDetailSheet(
                template: template,
                items: TemplateListRules.itemsForTemplate(template, in: items)
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
    }

    private func requestDismiss() {
        focusedField = nil
        pendingSelection = nil
        if hasUnsavedChanges { showsDiscardConfirmation = true }
        else { dismiss() }
    }

    private func requestSelection(_ template: TaskTemplate) {
        focusedField = nil
        guard selectedTemplate?.id != template.id else { return }
        if hasUnsavedChanges {
            pendingSelection = template
            showsDiscardConfirmation = true
        } else {
            selectTemplate(template)
        }
    }

    private func selectTemplate(_ template: TaskTemplate) {
        selectedTemplate = template
        drafts = TemplateService.drafts(from: template, items: TemplateListRules.itemsForTemplate(template, in: items))
        initialDrafts = drafts
        pendingSelection = nil
        message = nil
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        do {
            let isFavorite = try PersistenceCommandService.perform(in: modelContext) {
                template.isFavorite.toggle()
                template.updatedAt = Date()
                return template.isFavorite
            }
            message = isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요"
        } catch {
            message = "즐겨찾기를 변경하지 못했어요"
        }
    }

    private func removeDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        message = nil
    }

    private func startPlacement() {
        focusedField = nil
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
        let templateID = template.id
        let templateName = template.name
        do {
            let deletedItemCount = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.deleteTemplate(
                    template,
                    items: items,
                    in: modelContext
                )
            }
            if selectedTemplate?.id == templateID {
                selectedTemplate = nil
                drafts = []
                initialDrafts = []
            }
            if detailTemplate?.id == templateID {
                detailTemplate = nil
            }
            pendingDeleteTemplate = nil
            message = "\"\(templateName)\" 템플릿과 작업 \(deletedItemCount)개를 삭제했어요"
        } catch {
            message = "템플릿을 삭제하지 못했어요"
        }
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle("상세 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .tint(AppTheme.accent)
        .presentationBackground(AppTheme.background)
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
