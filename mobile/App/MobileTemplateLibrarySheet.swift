#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileTemplateLibrarySheet: View {
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
    @State private var pendingTemplate: TaskTemplate?
    @State private var pendingDeleteTemplate: TaskTemplate?
    @State private var templateName = ""
    @State private var templateDrafts: [TemplateTaskDraft] = []

    private var filteredTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(templates, items: items, query: searchText, scope: scope)
    }

    private var currentBoardTasks: [TodoTask] {
        let dayKey = DayKey.key(for: selectedDate)
        return existingTasks
            .filter {
                $0.supersededAt == nil &&
                    $0.archivedAt == nil &&
                    $0.plannedDayKey == dayKey
            }
            .sorted { $0.order < $1.order }
    }

    private var validTemplateDrafts: [TemplateTaskDraft] {
        templateDrafts.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "검색 결과 없음" }
        return "즐겨찾기 템플릿 없음"
    }

    private var emptyDescription: Text {
        if templates.isEmpty { return Text("반복할 작업 묶음을 템플릿으로 저장하면 여기에서 적용할 수 있어요.") }
        if scope == .favorites { return Text("전체보기로 전환하면 모든 템플릿을 볼 수 있어요.") }
        return Text("다른 검색어로 다시 시도하세요.")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("현재 보드 저장") {
                    if currentBoardTasks.isEmpty {
                        ContentUnavailableView("저장할 작업 없음", systemImage: "checklist")
                            .listRowBackground(Color.clear)
                    } else {
                        TextField("템플릿 이름", text: $templateName)

                        ForEach($templateDrafts) { $draft in
                            MobileTemplateDraftEditRow(
                                draft: $draft,
                                onRemove: removeTemplateDraft
                            )
                        }

                        HStack {
                            Button {
                                loadCurrentBoardDrafts()
                            } label: {
                                Label("다시 불러오기", systemImage: "arrow.clockwise")
                            }

                            Spacer()

                            Button {
                                saveCurrentBoardTemplate()
                            } label: {
                                Label("템플릿으로 저장", systemImage: "square.on.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                    validTemplateDrafts.isEmpty
                            )
                        }
                    }
                }

                Section {
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
                }

                ForEach(filteredTemplates) { template in
                    let templateItems = TemplateListRules.itemsForTemplate(template, in: items)
                    HStack(spacing: 10) {
                        Button {
                            toggleFavorite(template)
                        } label: {
                            Image(systemName: template.isFavorite ? "star.fill" : "star")
                                .font(.headline)
                                .foregroundStyle(template.isFavorite ? .yellow : .secondary)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(template.isFavorite ? "즐겨찾기 제거" : "즐겨찾기 추가")

                        Button {
                            requestApply(template, items: templateItems)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(template.name)
                                    .font(.headline)
                                Text(templateItems.map(\.title).prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
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
            .navigationTitle("템플릿")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                scope = TemplateListRules.preferredScope(for: templates)
                if templateDrafts.isEmpty {
                    loadCurrentBoardDrafts()
                }
            }
            .onChange(of: searchText) {
                message = nil
            }
            .onChange(of: scope) {
                message = nil
            }
            .alert(
                "템플릿을 적용하시겠습니까?",
                isPresented: isConfirmingTemplateApply,
                presenting: pendingTemplate
            ) { template in
                Button("미적용", role: .cancel) {
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
                let count = TemplateListRules.itemsForTemplate(template, in: items).count
                Text("\"\(template.name)\" 템플릿과 하위 작업 \(count)개를 삭제합니다.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func requestApply(_ template: TaskTemplate, items templateItems: [TaskTemplateItem]) {
        let hasApplicableItem = templateItems.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard hasApplicableItem else {
            message = "템플릿에 적용할 작업이 없어요"
            return
        }

        message = nil
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
            message = isFavorite ? "즐겨찾기에 추가했어요" : "즐겨찾기에서 제거했어요"
        } catch {
            message = "즐겨찾기를 변경하지 못했습니다"
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
            message = "\"\(name)\" 템플릿을 삭제했어요"
        } catch {
            pendingDeleteTemplate = nil
            message = "템플릿을 삭제하지 못했습니다"
        }
    }

    private func loadCurrentBoardDrafts() {
        do {
            let checklistItems = try TaskChecklistService.items(
                for: currentBoardTasks.map(\.id),
                in: modelContext
            )
            templateDrafts = TemplateService.drafts(
                from: currentBoardTasks,
                checklistItems: checklistItems
            )
            message = nil
        } catch {
            message = "현재 보드의 체크리스트를 불러오지 못했습니다"
        }
    }

    private func removeTemplateDraft(_ id: UUID) {
        templateDrafts.removeAll { $0.id == id }
    }

    private func saveCurrentBoardTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !validTemplateDrafts.isEmpty else { return }

        do {
            let template = try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.saveTemplate(
                    named: name,
                    from: validTemplateDrafts,
                    in: modelContext
                )
            }
            guard template != nil else {
                message = "템플릿 이름과 작업을 확인해 주세요"
                return
            }
            templateName = ""
            loadCurrentBoardDrafts()
            scope = .all
            message = "\"\(name)\" 템플릿을 저장했어요"
        } catch {
            message = "템플릿을 저장하지 못했습니다"
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
                message = "추가할 새 작업이 없어요"
                return
            }
            onApplied("\"\(templateName)\" 템플릿으로 \(createdCount)개 작업을 추가했어요")
            dismiss()
        } catch {
            message = "템플릿을 적용하지 못했습니다"
        }
    }
}
#endif
