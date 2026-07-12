#if os(iOS)
import EasyTaskCore
import SwiftData
import SwiftUI

struct MobileTemplatePlacementSheet: View {
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
        do {
            let isFavorite = try PersistenceCommandService.perform(in: modelContext) {
                template.isFavorite.toggle()
                template.updatedAt = Date()
                return template.isFavorite
            }
            if selectedTemplate?.id == template.id && !isFavorite && scope == .favorites {
                selectedTemplate = nil
                drafts = []
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
