import SwiftData
import SwiftUI

/// Separate from the timer's TimelineView: ticking never refetches checklist rows.
struct FocusTaskChecklistView: View {
    @Environment(\.modelContext) private var context
    @Query private var rows: [TaskChecklistItem]
    @State private var saveError: String?

    init(taskID: UUID) {
        _rows = Query(TaskChecklistService.descriptor(taskID: taskID))
    }

    private var items: [TaskChecklistItem] {
        // Imports may briefly contain multiple physical records for one item.
        var representatives: [UUID: TaskChecklistItem] = [:]
        for item in rows where item.modelContext != nil && item.supersededAt == nil {
            if let existing = representatives[item.id],
               existing.updatedAt > item.updatedAt ||
                (existing.updatedAt == item.updatedAt && existing.instanceID.uuidString > item.instanceID.uuidString) {
                continue
            }
            representatives[item.id] = item
        }
        return representatives.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.instanceID.uuidString < $1.instanceID.uuidString
        }
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("체크리스트", systemImage: "checklist").font(.headline)
                Spacer()
                Text("\(items.filter(\.isCompleted).count)/\(items.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
            }
            if items.isEmpty {
                Text("이 작업에 등록된 체크리스트가 없어요.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(items, id: \.instanceID) { item in
                Button {
                    do {
                        try PersistenceCommandService.perform(in: context) {
                            TaskChecklistService.setCompletion(!item.isCompleted, for: item)
                        }
                    } catch {
                        saveError = "체크 상태를 저장하지 못했습니다. 다시 시도해 주세요."
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(AppTheme.accent)
                        Text(item.title)
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? AppTheme.secondaryText : AppTheme.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.isCompleted ? "완료" : "미완료")
                .accessibilityHint("두 번 탭하여 체크 상태 변경")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border, lineWidth: 1) }
        .accessibilityIdentifier("focus-checklist")
        .alert("저장 실패", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(saveError ?? "") }
    }
}
