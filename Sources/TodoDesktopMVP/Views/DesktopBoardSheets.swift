import SwiftUI
import EasyTaskCore

struct CarryoverSheet: View {
    var tasks: [Task]
    @Binding var failureMessage: String?
    var onBringToToday: (Task) -> Void
    var onCompleteAll: () -> Void
    var onDelete: (Task) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이월함")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("과거 날짜의 미완료 작업을 오늘 할 일로 가져오거나 완료 처리합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if !tasks.isEmpty {
                    Button {
                        onCompleteAll()
                    } label: {
                        Label("모두 완료 처리", systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("이월함의 모든 작업을 완료 상태로 변경")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            if tasks.isEmpty {
                EmptySheetState(
                    symbol: "tray",
                    title: "이월할 작업 없음",
                    message: "과거 날짜에 남아 있는 미완료 작업이 없습니다."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(tasks) { task in
                            CarryoverTaskRow(
                                task: task,
                                onBringToToday: onBringToToday,
                                onDelete: onDelete
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
        .persistenceFailureAlert(message: $failureMessage)
    }
}

struct TemplateLibrarySheet: View {
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    @Binding var templateName: String
    @Binding var failureMessage: String?
    var currentBoardTasks: [Task]
    var onApply: (TaskTemplate) -> Void
    var onSaveCurrentBoard: ([Task]) -> Void
    var onToggleFavorite: (TaskTemplate) -> Void
    var onDelete: (TaskTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedScope: TemplateListScope = .favorites
    @State private var excludedTaskIDs: Set<UUID> = []
    @State private var pendingDeleteTemplate: TaskTemplate?

    private var canSaveCurrentBoard: Bool {
        !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !includedBoardTasks.isEmpty
    }

    private var includedBoardTasks: [Task] {
        currentBoardTasks.filter { !excludedTaskIDs.contains($0.id) }
    }

    private var excludedBoardTaskCount: Int {
        currentBoardTasks.count - includedBoardTasks.count
    }

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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("템플릿")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("저장한 작업 묶음을 현재 날짜에 적용하거나 현재 보드를 템플릿으로 저장합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

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

            HStack(alignment: .top, spacing: 18) {
                templateList
                saveCurrentBoardPanel
            }
        }
        .padding(22)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 430, idealHeight: 540)
        .background(AppTheme.panel)
        .onAppear {
            selectedScope = TemplateListRules.preferredScope(for: templates)
            excludedTaskIDs = []
        }
        .onChange(of: currentBoardTasks.map(\.id)) { _, ids in
            excludedTaskIDs.formIntersection(Set(ids))
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
                onDelete(template)
                pendingDeleteTemplate = nil
            }
        } message: { template in
            Text("\"\(template.name)\" 템플릿과 하위 작업 \(itemsForTemplate(template).count)개를 삭제합니다.")
        }
        .persistenceFailureAlert(message: $failureMessage)
    }

    @ViewBuilder
    private var templateList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("저장된 템플릿")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TemplateScopePicker(scope: $selectedScope)

            TemplateSearchField(text: $searchText)

            if templates.isEmpty {
                EmptySheetState(
                    symbol: "square.on.square",
                    title: "저장된 템플릿 없음",
                    message: "현재 보드의 작업을 저장하면 이곳에서 다시 적용할 수 있습니다."
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
                            TemplateRow(
                                template: template,
                                items: itemsForTemplate(template),
                                onApply: {
                                    onApply(template)
                                },
                                onToggleFavorite: {
                                    onToggleFavorite(template)
                                },
                                onDelete: {
                                    pendingDeleteTemplate = template
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var saveCurrentBoardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("현재 보드 저장")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TextField("템플릿 이름", text: $templateName)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .onSubmit {
                    if canSaveCurrentBoard {
                        onSaveCurrentBoard(includedBoardTasks)
                    }
                }

            HStack(spacing: 8) {
                Text(currentBoardTaskSummary)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                if excludedBoardTaskCount > 0 {
                    Button("제외 초기화") {
                        excludedTaskIDs = []
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.event)
                }
            }

            currentBoardTaskList

            Button {
                onSaveCurrentBoard(includedBoardTasks)
            } label: {
                Label("템플릿으로 저장", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSaveCurrentBoard)

            Spacer()
        }
        .padding(14)
        .frame(width: 290, alignment: .topLeading)
        .frame(minHeight: 260, alignment: .topLeading)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var currentBoardTaskSummary: String {
        if excludedBoardTaskCount > 0 {
            return "저장 대상 \(includedBoardTasks.count)개 · 제외 \(excludedBoardTaskCount)개"
        }
        return "현재 날짜의 작업 \(includedBoardTasks.count)개"
    }

    @ViewBuilder
    private var currentBoardTaskList: some View {
        if includedBoardTasks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("저장할 작업 없음")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(includedBoardTasks) { task in
                        TemplateSourceTaskRow(
                            task: task,
                            onExclude: {
                                excludedTaskIDs.insert(task.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 180)
        }
    }

    private func itemsForTemplate(_ template: TaskTemplate) -> [TaskTemplateItem] {
        TemplateListRules.itemsForTemplate(template, in: items)
    }
}

struct TemplateSourceTaskRow: View {
    var task: Task
    var onExclude: () -> Void

    private var status: TaskStatus {
        TaskStatus(rawValue: task.status) ?? .todo
    }

    private var statusColor: Color {
        switch status {
        case .todo: AppTheme.secondaryText
        case .doing: AppTheme.event
        case .done: AppTheme.done
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Button {
                onExclude()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("템플릿 저장 대상에서 제외")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct TemplateRow: View {
    @Bindable var template: TaskTemplate
    var items: [TaskTemplateItem]
    var onApply: () -> Void
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void

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
                    Text(items.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            Button("적용") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(items.isEmpty)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .help("템플릿 삭제")
        }
        .padding(12)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct EmptySheetState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(18)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct CarryoverTaskRow: View {
    var task: Task
    var onBringToToday: (Task) -> Void
    var onDelete: (Task) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(task.plannedDayKey)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                onBringToToday(task)
            } label: {
                Label("오늘로", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(10)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
    }
}

