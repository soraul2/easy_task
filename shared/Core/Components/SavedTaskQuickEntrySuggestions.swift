#if os(iOS) || os(macOS)
import SwiftUI

public struct SavedTaskQuickEntrySuggestions: View {
    public let controller: SavedTaskQuickEntryController
    private let onAdd: (UUID) -> Void
    private let onManage: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(controller: SavedTaskQuickEntryController, onAdd: @escaping (UUID) -> Void,
                onManage: @escaping () -> Void) {
        self.controller = controller
        self.onAdd = onAdd
        self.onManage = onManage
    }

    public var body: some View {
        if controller.isPresented {
            VStack(alignment: .leading, spacing: 10) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("저장한 작업", systemImage: "bookmark").font(.subheadline.bold())
                        manageButton
                    }
                } else {
                    HStack {
                        Label("저장한 작업", systemImage: "bookmark").font(.subheadline.bold())
                        Spacer(minLength: 8)
                        manageButton
                    }
                }
                if let failure = controller.failure {
                    Label(failure, systemImage: "exclamationmark.circle")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("quick-entry-error")
                }
                if controller.suggestions.isEmpty {
                    Text(controller.entries.isEmpty ? "저장한 작업이 없어요. 입력어 관리에서 작업을 저장해 주세요." : "일치하는 작업이 없어요. 입력어 또는 제목을 확인해 주세요.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("quick-entry-empty")
                } else {
                    #if os(macOS)
                    ScrollViewReader { proxy in
                        ScrollView {
                            suggestionRows
                        }
                        .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 320 : 220)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("quick-entry-results")
                        .onChange(of: controller.highlightedID) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                    #else
                    // The board already scrolls. A second scroll region can trap touch gestures
                    // when large text places the candidate below the keyboard or tab bar.
                    suggestionRows
                    #endif
                }
                Text(footer)
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .foregroundStyle(AppTheme.primaryText)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quick-entry-suggestions")
        }
    }

    private var manageButton: some View {
        Button(action: onManage) {
            Text("입력어 관리").frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(AppTheme.accent)
        .accessibilityIdentifier("quick-entry-manage")
    }

    private var suggestionRows: some View {
        LazyVStack(spacing: 6) {
            ForEach(controller.suggestions) { entry in row(entry).id(entry.id) }
        }
    }

    private var footer: String {
        #if os(macOS)
        "입력어 + Enter로 추가 · ↑↓로 후보 선택 · Esc로 닫기"
        #else
        "작업을 누르거나 입력어를 끝까지 입력해 추가하세요."
        #endif
    }

    private func row(_ entry: SavedTaskEntry) -> some View {
        let selected = controller.highlightedID == entry.id
        let alias = SavedTaskShortcutRules.aliasKey(entry.quickEntryAlias)
        let duplicate = alias != nil && controller.entries.filter {
            SavedTaskShortcutRules.aliasKey($0.quickEntryAlias) == alias
        }.count > 1
        return Button { onAdd(entry.id) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.draft.title).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let alias {
                        Text("/\(alias)\(duplicate ? " · 입력어 중복" : "")")
                            .font(.caption.monospaced()).foregroundStyle(AppTheme.accent)
                    }
                    let details = [entry.draft.estimatedMinutes.map { "예상 \($0)분" },
                                   entry.draft.checklistTitles.isEmpty ? nil : "체크리스트 \(entry.draft.checklistTitles.count)개"]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !details.isEmpty { Text(details).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "return" : "plus")
                    .foregroundStyle(AppTheme.accent).accessibilityHidden(true)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected ? AppTheme.selectedTab : AppTheme.input, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.draft.title)\(alias.map { " /\($0)" } ?? "") 추가")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("quick-entry-result-\(entry.id)")
    }
}
#endif
