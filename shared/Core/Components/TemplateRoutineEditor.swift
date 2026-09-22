#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TemplateEditorRequest: Identifiable {
    let id = UUID()
    var original: TemplateContentSnapshot?
    var name: String
    var drafts: [TemplateTaskDraft]
    var favorite: Bool = false
    var adjustment = false
}

struct TemplateRoutineEditor: View {
    let request: TemplateEditorRequest
    var onSaved: (String) -> Void
    var onAdjusted: ([TemplateTaskDraft]) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var drafts: [TemplateTaskDraft]
    @State private var favorite: Bool
    @State private var failure: String?
    @State private var showsDiscard = false
    @State private var saveAsCopy = false
    @FocusState private var nameFocused: Bool

    init(request: TemplateEditorRequest, onSaved: @escaping (String) -> Void,
         onAdjusted: @escaping ([TemplateTaskDraft]) -> Void) {
        self.request = request
        self.onSaved = onSaved
        self.onAdjusted = onAdjusted
        _name = State(initialValue: request.name)
        _drafts = State(initialValue: request.drafts)
        _favorite = State(initialValue: request.favorite)
    }

    private var hasChanges: Bool {
        name != request.name || drafts != request.drafts || favorite != request.favorite
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !drafts.isEmpty &&
        drafts.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.estimatedMinutes ?? 0) >= 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("template-editor-error")
                        Button("다시 시도", action: save)
                            .accessibilityIdentifier("template-save-retry")
                        if request.original != nil && !request.adjustment {
                            Button("새 템플릿으로 저장") {
                                saveAsCopy = true
                                save()
                            }
                        }
                    }
                }
                Section {
                    if request.adjustment {
                        Text(name).font(.headline)
                        Text("이번에 추가할 작업만 조정합니다. 저장된 템플릿은 그대로 유지돼요.")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        TextField("템플릿 이름", text: $name)
                            .focused($nameFocused)
                            .accessibilityIdentifier("template-draft-name")
                        Toggle("즐겨찾기", isOn: $favorite)
                    }
                } footer: {
                    if request.original?.drafts.count == 1 && !request.adjustment {
                        Text("‘저장한 작업’과 같은 항목입니다. 수정하면 두 목록에 함께 반영돼요.")
                    }
                }
                Section {
                    ForEach($drafts) { $draft in
                        TemplateRoutineDraftRow(draft: $draft,
                            canMoveUp: drafts.first?.id != draft.id,
                            canMoveDown: drafts.last?.id != draft.id,
                            onMove: { offset in move(draft.id, by: offset) },
                            onRemove: { drafts.removeAll { $0.id == draft.id } })
                    }
                    Button {
                        drafts.append(TemplateTaskDraft(title: "", order: Double(drafts.count + 1) * 100))
                    } label: {
                        Label("작업 추가", systemImage: "plus")
                    }
                    .accessibilityIdentifier("template-editor-add-task")
                } header: {
                    Text("작업 \(drafts.count)개")
                } footer: {
                    Text(request.adjustment
                         ? "추가되는 작업과 체크리스트는 미완료 상태로 시작해요."
                         : "수정한 템플릿은 다음에 추가할 때부터 사용돼요. 이미 보드에 추가한 작업은 유지됩니다.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle(request.adjustment ? "이번에만 조정" : request.original == nil ? "템플릿 만들기" : "템플릿 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if hasChanges { showsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.adjustment ? "계속" : "저장", action: save)
                        .disabled(!isValid)
                        .accessibilityIdentifier("template-draft-save")
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("키보드 닫기") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("template-editor-keyboard-dismiss")
                }
                #endif
            }
        }
        .tint(AppTheme.accent)
        .planBaseDiscardConfirmation(isPresented: $showsDiscard, hasUnsavedChanges: hasChanges,
                                    onDiscard: { dismiss() })
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 580, minHeight: 540, idealHeight: 680)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = drafts.firstIndex(where: { $0.id == id }),
              drafts.indices.contains(index + offset) else { return }
        drafts.swapAt(index, index + offset)
    }

    private func save() {
        guard isValid else { return }
        let ordered = drafts.enumerated().map { index, draft in
            var draft = draft
            draft.order = Double(index + 1) * 100
            return draft
        }
        if request.adjustment {
            onAdjusted(ordered)
            dismiss()
            return
        }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-template-save-failure-once"),
               !TemplateRoutineEditorFixture.didFailSave {
                TemplateRoutineEditorFixture.didFailSave = true
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            _ = try TemplateEditingService.save(original: saveAsCopy ? nil : request.original,
                name: name, drafts: ordered, isFavorite: favorite, in: context)
            onSaved("‘\(name.trimmingCharacters(in: .whitespacesAndNewlines))’ 템플릿을 저장했어요")
            dismiss()
        } catch {
            failure = error.localizedDescription + "\n작성한 이름과 작업은 그대로 유지됩니다."
        }
    }
}

private struct TemplateRoutineDraftRow: View {
    @Binding var draft: TemplateTaskDraft
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onMove: (Int) -> Void
    var onRemove: () -> Void
    @State private var expanded = false
    @State private var estimatedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("작업 제목", text: $draft.title)
                .font(.headline)
                .accessibilityIdentifier("template-editor-task-title")
            HStack {
                Button { onMove(-1) } label: { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                    .disabled(!canMoveUp)
                    .accessibilityLabel("\(draft.title) 위로 이동")
                Button { onMove(1) } label: { Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44) }
                    .disabled(!canMoveDown)
                    .accessibilityLabel("\(draft.title) 아래로 이동")
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                }
                    .accessibilityLabel("\(draft.title) 목록에서 제외")
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            DisclosureGroup("메모·체크리스트·추가 정보", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("메모", text: $draft.note, axis: .vertical).lineLimit(2...5)
                    TextField("체크리스트 · 한 줄에 하나씩", text: Binding(
                        get: { draft.checklistTitles.joined(separator: "\n") },
                        set: { draft.checklistTitles = $0.components(separatedBy: .newlines) }
                    ), axis: .vertical).lineLimit(2...8)
                    HStack {
                        Text("예상 시간")
                        TextField("선택 입력", text: $estimatedText)
                            .accessibilityLabel("\(draft.title) 예상 시간, 분")
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("분")
                    }
                    if (draft.estimatedMinutes ?? 0) < 0 {
                        Text("예상 시간은 0 이상의 숫자로 입력해 주세요.")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Picker("우선순위", selection: $draft.priority) {
                        Text("없음").tag(nil as String?)
                        ForEach(TaskPriority.allCases) { Text($0.title).tag(Optional($0.rawValue)) }
                    }
                    TextField("태그 · 쉼표로 구분", text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = $0.components(separatedBy: ",") }
                    ))
                }.padding(.top, 10)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 8)
        .onAppear { estimatedText = draft.estimatedMinutes.map(String.init) ?? "" }
        .onChange(of: estimatedText) { _, value in
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.estimatedMinutes = value.isEmpty ? nil : (Int(value) ?? -1)
        }
    }
}

#if DEBUG
@MainActor private enum TemplateRoutineEditorFixture {
    static var didFailSave = false
}
#endif
#endif
