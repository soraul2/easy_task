#if os(iOS)
import EasyTaskCore
import SwiftUI

struct MobileTemplateDraftEditRow: View {
    @Binding var draft: TemplateTaskDraft
    var onRemove: (UUID) -> Void
    @State private var isChecklistExpanded = false

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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(draft.title) 목록에서 제외")
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

            DisclosureGroup(isExpanded: $isChecklistExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    if draft.checklistTitles.isEmpty {
                        Label("체크리스트 없음", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        ForEach(Array(draft.checklistTitles.indices), id: \.self) { index in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)

                                TextField(
                                    "체크리스트 항목 \(index + 1)",
                                    text: $draft.checklistTitles[index]
                                )
                                .font(.subheadline)
                                .frame(minHeight: 44)
                                .accessibilityLabel("체크리스트 항목 \(index + 1) 제목")

                                Button(role: .destructive) {
                                    removeChecklistTitle(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    "\(checklistAccessibilityTitle(at: index)) 체크리스트 항목 삭제"
                                )
                            }
                        }
                    }
                }
                .padding(.top, 2)
            } label: {
                HStack(spacing: 8) {
                    Label("체크리스트", systemImage: "checklist")
                    Spacer()
                    Text("\(draft.checklistTitles.count)")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("\(draft.title) 체크리스트")
            .accessibilityValue("항목 \(draft.checklistTitles.count)개")
        }
        .padding(.vertical, 4)
    }

    private func removeChecklistTitle(at index: Int) {
        guard draft.checklistTitles.indices.contains(index) else { return }
        draft.checklistTitles.remove(at: index)
    }

    private func checklistAccessibilityTitle(at index: Int) -> String {
        guard draft.checklistTitles.indices.contains(index) else {
            return "제목 없는"
        }
        let title = draft.checklistTitles[index]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없는" : title
    }
}
#endif
