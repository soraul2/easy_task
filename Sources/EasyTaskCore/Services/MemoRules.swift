import Foundation

public enum MemoRules {
    public static let emptyTitle = "빈 메모"

    public static func displayTitle(for content: String) -> String {
        content
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? emptyTitle
    }

    public static func preview(for content: String) -> String {
        let nonemptyLines = content
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let remainingLines = nonemptyLines.dropFirst()
        let source = remainingLines.isEmpty ? nonemptyLines : Array(remainingLines)
        return source.joined(separator: " ")
    }

    public static func isBlank(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func matches(_ memo: Memo, query: String) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return true }
        return normalizedSearchText(memo.content).contains(normalizedQuery)
    }

    public static func sorted(_ memos: [Memo]) -> [Memo] {
        memos
            .filter { $0.supersededAt == nil }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    public static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
