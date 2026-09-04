#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI

struct SavedTaskEditorSheet: View {
    let entry: SavedTaskEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TemplateTaskDraft
    @State private var estimatedText: String
    @State private var checklistText: String
    @State private var tagsText: String
    @State private var favorite: Bool
    @State private var failure: String?

    init(entry: SavedTaskEntry?) {
        self.entry = entry
        let draft = entry?.draft ?? TemplateTaskDraft(title: "", order: 100)
        _draft = State(initialValue: draft)
        _estimatedText = State(initialValue: draft.estimatedMinutes.map(String.init) ?? "")
        _checklistText = State(initialValue: draft.checklistTitles.joined(separator: "\n"))
        _tagsText = State(initialValue: draft.tags.joined(separator: ", "))
        _favorite = State(initialValue: entry?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("작업 제목", text: $draft.title).accessibilityIdentifier("saved-task-title")
                    TextField("메모", text: $draft.note, axis: .vertical).lineLimit(3...6)
                    TextField("예상 시간(분)", text: $estimatedText)
                        .accessibilityIdentifier("saved-task-estimate")
                    Toggle("즐겨찾기", isOn: $favorite)
                }
                Section {
                    TextField("항목을 한 줄에 하나씩 입력", text: $checklistText, axis: .vertical)
                        .lineLimit(4...10)
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
                }
                if let failure {
                    Text(failure).foregroundStyle(.red).accessibilityIdentifier("saved-task-editor-error")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "새로 저장" : "저장 내용 편집")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("저장", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saved-task-editor-save")
                }
            }
        }
        .tint(AppTheme.accent)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 540, idealHeight: 620)
        #endif
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
                    id: entry.id, draft: draft, isFavorite: favorite, in: context)
            } else {
                try SavedTaskLibraryService.create(draft: draft, isFavorite: favorite, in: context)
            }
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
#endif
