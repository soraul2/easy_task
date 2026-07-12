#if os(iOS)
import EasyTaskCore
import SwiftUI

struct MobileTemplateDraftEditRow: View {
    @Binding var draft: TemplateTaskDraft
    var onRemove: (UUID) -> Void

    private var priority: TaskPriority? {
        draft.priority.flatMap(TaskPriority.init(rawValue:))
    }

    private var tags: [String] {
        draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("작업 제목", text: $draft.title)
                    .font(.subheadline.weight(.semibold))

                Button(role: .destructive) {
                    onRemove(draft.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("목록에서 제외")
            }

            TextField("메모", text: $draft.note, axis: .vertical)
                .font(.caption)
                .lineLimit(1...3)

            if priority != nil || draft.estimatedMinutes != nil || !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let priority {
                            Label(priority.title, systemImage: "flag.fill")
                        }
                        if let estimatedMinutes = draft.estimatedMinutes {
                            Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                        }
                        ForEach(tags, id: \.self) { tag in
                            Label("#\(tag)", systemImage: "tag")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
