import SwiftData
import SwiftUI
import EasyTaskCore

struct TemplatePlacementSheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var onSelect: (TaskTemplate) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedScope: TemplateListScope = .favorites
    @State private var message: String?
    @State private var pendingDeleteTemplate: TaskTemplate?

    private var visibleTemplates: [TaskTemplate] {
        TemplateListRules.filterAndSort(
            templates,
            items: items,
            query: searchText,
            scope: selectedScope
        )
    }

    private var emptyTemplateTitle: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "즐겨찾기한 템플릿 없음"
        }
        return "검색 결과 없음"
    }

    private var emptyTemplateMessage: String {
        if selectedScope == .favorites, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "전체보기에서 자주 쓰는 템플릿에 별표를 눌러 추가하세요."
        }
        return "템플릿 이름이나 포함된 작업명으로 다시 검색해보세요."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("템플릿 배치")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            TemplateScopePicker(scope: $selectedScope)

            TemplateSearchField(text: $searchText)

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if templates.isEmpty {
                EmptySheetState(
                    symbol: "square.grid.3x3",
                    title: "저장된 템플릿 없음",
                    message: "칸반보드에서 현재 작업을 템플릿으로 저장하면 사용할 수 있습니다."
                )
            } else if visibleTemplates.isEmpty {
                EmptySheetState(
                    symbol: selectedScope == .favorites ? "star" : "magnifyingglass",
                    title: emptyTemplateTitle,
                    message: emptyTemplateMessage
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            TemplatePlacementRow(
                                template: template,
                                items: itemsForTemplate(template),
                                onToggleFavorite: {
                                    toggleFavorite(template)
                                },
                                onDelete: {
                                    pendingDeleteTemplate = template
                                },
                                onSelect: {
                                    onSelect(template)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 480)
        .background(AppTheme.panel)
        .onAppear {
            selectedScope = TemplateListRules.preferredScope(for: templates)
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
            Text("\"\(template.name)\" 템플릿과 하위 작업 \(itemsForTemplate(template).count)개를 삭제합니다.")
        }
    }

    private func itemsForTemplate(_ template: TaskTemplate) -> [TaskTemplateItem] {
        TemplateListRules.itemsForTemplate(template, in: items)
    }

    private func toggleFavorite(_ template: TaskTemplate) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                template.isFavorite.toggle()
                template.updatedAt = Date()
            }
            message = nil
        } catch {
            message = "즐겨찾기를 변경하지 못했어요."
        }
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TemplateService.deleteTemplate(
                    template,
                    items: items,
                    in: modelContext
                )
            }
            pendingDeleteTemplate = nil
            message = nil
        } catch {
            pendingDeleteTemplate = nil
            message = "템플릿을 삭제하지 못했어요."
        }
    }
}

struct TemplatePlacementRow: View {
    @Bindable var template: TaskTemplate
    var items: [TaskTemplateItem]
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: template.isFavorite ? "star.fill" : "star")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(template.isFavorite ? Color.yellow : AppTheme.secondaryText)
            .help(template.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                }

                if items.isEmpty {
                    Text("비어 있는 템플릿")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text(items.prefix(4).map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("템플릿 삭제")

            Button("선택") {
                onSelect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(items.isEmpty)
        }
        .padding(12)
        .background(AppTheme.columnTodo, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

