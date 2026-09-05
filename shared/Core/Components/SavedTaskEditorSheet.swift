#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI

struct SavedTaskEditorSheet: View {
    let entry: SavedTaskEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Field: Hashable { case title, note, estimate, alias, checklist, tags }
    @FocusState private var focusedField: Field?
    @State private var draft: TemplateTaskDraft
    @State private var estimatedText: String
    @State private var checklistText: String
    @State private var tagsText: String
    @State private var favorite: Bool
    @State private var quickEntryAlias: String
    @State private var failure: String?
    @State private var showsDiscardConfirmation = false

    init(entry: SavedTaskEntry?) {
        self.entry = entry
        let draft = entry?.draft ?? TemplateTaskDraft(title: "", order: 100)
        _draft = State(initialValue: draft)
        _estimatedText = State(initialValue: draft.estimatedMinutes.map(String.init) ?? "")
        _checklistText = State(initialValue: draft.checklistTitles.joined(separator: "\n"))
        _tagsText = State(initialValue: draft.tags.joined(separator: ", "))
        _favorite = State(initialValue: entry?.isFavorite ?? false)
        _quickEntryAlias = State(initialValue: entry?.quickEntryAlias ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("작업 제목", text: $draft.title).accessibilityIdentifier("saved-task-title")
                        .focused($focusedField, equals: .title)
                    TextField("메모", text: $draft.note, axis: .vertical)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...6 : 3...6)
                        .focused($focusedField, equals: .note)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("예상 시간")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("선택 입력", text: $estimatedText)
                                .focused($focusedField, equals: .estimate)
                                .accessibilityLabel("예상 시간, 분")
                                .accessibilityIdentifier("saved-task-estimate")
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Text("분")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    Toggle("즐겨찾기", isOn: $favorite)
                }
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("/").foregroundStyle(AppTheme.secondaryText)
                        TextField("예: 운동, weekly", text: $quickEntryAlias)
                            .focused($focusedField, equals: .alias)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityLabel("빠른 입력어")
                            .accessibilityIdentifier("saved-task-alias")
                    }
                } header: {
                    Text("빠른 입력어 · 선택")
                } footer: {
                    Text("할 일 입력창에서 /운동처럼 입력하면 바로 추가할 수 있어요. 문자·숫자·밑줄·하이픈 1~24자이며, 비우면 입력어를 해제해요.")
                }
                Section {
                    TextField("항목을 한 줄에 하나씩 입력", text: $checklistText, axis: .vertical)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...10 : 4...10)
                        .focused($focusedField, equals: .checklist)
                        .accessibilityIdentifier("saved-task-checklist")
                } header: {
                    Text("체크리스트")
                } footer: {
                    Text("보드에 추가할 때마다 모든 항목이 미완료 상태로 시작해요.")
                }
                Section("추가 정보") {
                    Picker("우선순위", selection: $draft.priority) {
                        Text("없음").tag(nil as String?)
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(Optional(priority.rawValue))
                        }
                    }
                    TextField("태그(쉼표로 구분)", text: $tagsText)
                        .focused($focusedField, equals: .tags)
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                if let failure {
                    Label {
                        Text(failure)
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(AppTheme.panel)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(failure)
                        .accessibilityIdentifier("saved-task-editor-error")
                }
            }
            .navigationTitle(entry == nil ? "새로 저장" : "저장 내용 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("키보드 닫기") { focusedField = nil }
                        .accessibilityIdentifier("saved-task-keyboard-dismiss")
                }
                #endif
                ToolbarItem(placement: .cancellationAction) { Button("취소", action: requestDismiss) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saved-task-editor-save")
                }
            }
        }
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            onDiscard: { dismiss() }
        )
        .tint(AppTheme.accent)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 540, idealHeight: 620)
        #endif
    }

    private var hasUnsavedChanges: Bool {
        draft.title != (entry?.draft.title ?? "") ||
            draft.note != (entry?.draft.note ?? "") ||
            draft.priority != entry?.draft.priority ||
            estimatedText != (entry?.draft.estimatedMinutes.map(String.init) ?? "") ||
            checklistText != (entry?.draft.checklistTitles.joined(separator: "\n") ?? "") ||
            tagsText != (entry?.draft.tags.joined(separator: ", ") ?? "") ||
            favorite != (entry?.isFavorite ?? false) ||
            quickEntryAlias != (entry?.quickEntryAlias ?? "")
    }

    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges { showsDiscardConfirmation = true }
        else { dismiss() }
    }

    private func save() {
        do {
            let estimate = estimatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !estimate.isEmpty {
                guard let minutes = Int(estimate), minutes >= 0 else {
                    throw SavedTaskLibraryService.Failure.invalidEstimate
                }
                draft.estimatedMinutes = minutes
            } else {
                draft.estimatedMinutes = nil
            }
            draft.checklistTitles = checklistText.components(separatedBy: .newlines)
            draft.tags = tagsText.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            if let entry {
                try SavedTaskLibraryService.update(
                    id: entry.id, draft: draft, isFavorite: favorite, quickEntryAlias: quickEntryAlias, in: context)
            } else {
                try SavedTaskLibraryService.create(draft: draft, isFavorite: favorite,
                                                  quickEntryAlias: quickEntryAlias, in: context)
            }
            dismiss()
        } catch {
            focusedField = nil
            failure = error.localizedDescription
        }
    }
}
#endif
